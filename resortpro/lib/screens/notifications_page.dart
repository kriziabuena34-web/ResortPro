import 'package:flutter/material.dart';

import '../services/notifications.dart';
import '../utils/format.dart';
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
    if (category == 'booking' || category == 'payment') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const MyBookingPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final q = _query.trim().toLowerCase();
        final items = service.items.where((n) {
          if (_filter == 'unread' && n['is_read'] == true) return false;
          if (const ['booking', 'payment', 'account'].contains(_filter) &&
              notificationCategory(n['type'] as String?) != _filter) {
            return false;
          }
          if (q.isEmpty) return true;
          return notificationTitle(n).toLowerCase().contains(q) ||
              notificationBody(n).toLowerCase().contains(q);
        }).toList();

        final filters = {
          'all': 'All',
          'unread': 'Unread (${service.unreadCount})',
          'booking': 'Bookings',
          'payment': 'Payments',
          'account': 'Account',
        };

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: SearchField(
                      controller: _search,
                      hint: 'Search notifications',
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  if (service.unreadCount > 0)
                    TextButton(
                      onPressed: service.markAllRead,
                      child: const Text('Mark all read'),
                    ),
                ],
              ),
            ),
            FilterChipsRow(
              children: [
                for (final e in filters.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _filter == e.key,
                    onSelected: (_) => setState(() => _filter = e.key),
                  ),
              ],
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: service.load,
                child: !service.available
                    ? ListView(
                        children: const [
                          SizedBox(height: 80),
                          Icon(Icons.cloud_off, size: 48),
                          SizedBox(height: 12),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              'Notifications are not available right now. Pull down to try again.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      )
                    : items.isEmpty
                        ? ListView(
                            children: [
                              const SizedBox(height: 80),
                              Icon(
                                Icons.notifications_none,
                                size: 56,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                service.items.isEmpty
                                    ? 'No notifications yet.\nUpdates about your bookings will appear here.'
                                    : 'No notifications match your search.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: items.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, i) => _tile(items[i]),
                          ),
              ),
            ),
          ],
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
    final theme = Theme.of(context);
    final unread = n['is_read'] != true;
    final category = notificationCategory(n['type'] as String?);
    final color = switch (category) {
      'payment' => const Color(0xFF238B45),
      'account' => const Color(0xFF2F6FED),
      _ => const Color(0xFFE08A00),
    };

    return Material(
      color: unread ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25) : Colors.transparent,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(notificationIcon(n['type'] as String?), color: color),
        ),
        title: Text(
          notificationTitle(n),
          style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.w500),
        ),
        subtitle: Text('${notificationBody(n)}\n${timeAgo(n['created_at'])}'),
        isThreeLine: true,
        trailing: unread
            ? Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
              )
            : null,
        onTap: () => _open(n),
      ),
    );
  }
}
