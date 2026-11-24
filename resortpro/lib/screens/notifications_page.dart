import 'package:flutter/material.dart';

import '../services/notifications.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'chat_page.dart';
import 'my_booking_page.dart';

/// Alerts tab: lahat ng notification ng client, may search at filter.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, this.embedded = false});

  /// True kapag nasa loob ng bottom navigation (walang sariling app bar).
  final bool embedded;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final service = UserNotifications.instance;
  final _search = TextEditingController();
  String _query = '';
  String _filter = 'all'; // all, unread, booking, payment, account

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(Map<String, dynamic> n) {
    service.markRead(n);
    final category = notificationCategory(n['type'] as String?);
    if (category == 'chat') {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const ChatPage()));
    } else if (category == 'booking' || category == 'payment') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const MyBookingPage()),
      );
    }
  }

  static Color _colorOf(String category) => switch (category) {
        'payment' => const Color(0xFF16A34A),
        'account' => const Color(0xFF2563EB),
        'chat' => const Color(0xFF6366F1),
        _ => AppColors.primary,
      };

  Widget _pill(String label, bool selected, VoidCallback onTap, {int? count}) {
    return Material(
      color: selected ? AppColors.ink : Colors.white,
      shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.ink : AppColors.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 8, count == null ? 14 : 10, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? Colors.white : AppColors.text,
                  )),
              if (count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white24 : const Color(0xFFE6EBF0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$count',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: selected ? Colors.white : AppColors.muted,
                      )),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(IconData icon, String title, String message) => Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.10), shape: BoxShape.circle),
              child: Icon(icon, size: 30, color: AppColors.primary),
            ),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final content = ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final q = _query.trim().toLowerCase();
        bool inCategory(Map<String, dynamic> n, String f) {
          if (f == 'unread') return n['is_read'] != true;
          if (const ['booking', 'payment', 'account'].contains(f)) {
            return notificationCategory(n['type'] as String?) == f;
          }
          return true;
        }

        final items = service.items.where((n) {
          if (!inCategory(n, _filter)) return false;
          if (q.isEmpty) return true;
          return notificationTitle(n).toLowerCase().contains(q) ||
              notificationBody(n).toLowerCase().contains(q);
        }).toList();

        final filters = {
          'all': 'All',
          'unread': 'Unread',
          'booking': 'Bookings',
          'payment': 'Payments',
          'account': 'Account',
        };

        // Today / Yesterday / Earlier
        final today = DateUtils.dateOnly(DateTime.now());
        String groupOf(Map<String, dynamic> n) {
          final d = parseDate(n['created_at'])?.toLocal();
          if (d == null) return 'Earlier';
          final day = DateUtils.dateOnly(d);
          if (day == today) return 'Today';
          if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
          return 'Earlier';
        }

        final groups = <String, List<Map<String, dynamic>>>{};
        for (final n in items) {
          groups.putIfAbsent(groupOf(n), () => []).add(n);
        }
        final unread = service.unreadCount;

        return RefreshIndicator(
          onRefresh: service.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              // ---- Buod ----
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 14, offset: Offset(0, 6))],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(color: AppColors.inkRaised, borderRadius: BorderRadius.circular(13)),
                      child: Badge(
                        isLabelVisible: unread > 0,
                        label: Text('$unread'),
                        child: const Icon(Icons.notifications_rounded, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            unread == 0 ? "You're All Caught Up" : '$unread Unread',
                            style: const TextStyle(
                                fontFamily: 'Poppins', color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          const Text('Updates about your bookings and payments',
                              style: TextStyle(color: AppColors.inkText, fontSize: 12)),
                        ],
                      ),
                    ),
                    if (unread > 0)
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: Colors.white),
                        onPressed: service.markAllRead,
                        icon: const Icon(Icons.done_all_rounded, size: 18),
                        label: const Text('Read All'),
                      ),
                  ],
                ),
              ),
              const _BackgroundNotice(),
              const SizedBox(height: 14),
              SearchField(
                controller: _search,
                hint: 'Search notifications',
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final e in filters.entries) ...[
                      _pill(e.value, _filter == e.key, () => setState(() => _filter = e.key),
                          count: service.items.where((n) => inCategory(n, e.key)).length),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (!service.available)
                _empty(Icons.cloud_off_rounded, 'Not Available',
                    'Notifications are not available right now. Pull down to try again.')
              else if (items.isEmpty)
                service.items.isEmpty
                    ? _empty(Icons.notifications_none_rounded, 'No Notifications Yet',
                        'Updates about your bookings will appear here.')
                    : _empty(Icons.search_off_rounded, 'Nothing Here', 'No notifications match your filter.')
              else
                for (final g in const ['Today', 'Yesterday', 'Earlier'])
                  if (groups[g] != null) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
                      child: Text(g.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.muted)),
                    ),
                    for (final n in groups[g]!) _tile(n),
                    const SizedBox(height: 6),
                  ],
            ],
          ),
        );
      },
    );

    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: content,
    );
  }

  Widget _tile(Map<String, dynamic> n) {
    final unread = n['is_read'] != true;
    final category = notificationCategory(n['type'] as String?);
    final color = _colorOf(category);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: unread ? AppColors.primary.withValues(alpha: 0.35) : AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(n),
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: unread ? color : Colors.transparent, width: 3)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(notificationIcon(n['type'] as String?), color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notificationTitle(n),
                              style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600, fontSize: 14.5),
                            ),
                          ),
                          if (unread)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(notificationBody(n),
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.35)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.schedule_rounded, size: 13, color: AppColors.muted),
                          const SizedBox(width: 4),
                          Text(timeAgo(n['created_at']),
                              style: const TextStyle(color: AppColors.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paalala kapag pinapatay ng battery saver ang app: baka hindi dumating ang
/// notifications kapag sarado ang app. May button para payagan.
class _BackgroundNotice extends StatefulWidget {
  const _BackgroundNotice();

  @override
  State<_BackgroundNotice> createState() => _BackgroundNoticeState();
}

class _BackgroundNoticeState extends State<_BackgroundNotice> with WidgetsBindingObserver {
  bool _allowed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Pagbalik galing sa settings ng Android, i-check ulit.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final ok = await BatterySaver.isAllowed();
    if (mounted && ok != _allowed) setState(() => _allowed = ok);
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.battery_alert_rounded, color: AppColors.warning),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Your phone may stop updates when ResortPro is closed. Allow it to run in the background.',
              style: TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.text),
            ),
          ),
          TextButton(onPressed: BatterySaver.request, child: const Text('Allow')),
        ],
      ),
    );
  }
}
