import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/admin_data.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/list_controls.dart';

/// Panel sa kanan (end drawer) na may reminders at notifications.
class NotificationsPanel extends StatefulWidget {
  const NotificationsPanel({
    super.key,
    required this.data,
    required this.onOpen,
  });

  final AdminData? data;

  /// Buksan ang isang module (at optional na booking filter).
  final void Function(int module, String? bookingFilter) onOpen;

  @override
  State<NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<NotificationsPanel> {
  final service = NotificationService.instance;
  bool _unreadOnly = false;
  String? _type;

  static const _caps = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.muted);

  @override
  Widget build(BuildContext context) {
    final reminders = widget.data == null ? <AdminReminder>[] : remindersFor(widget.data!);

    return Drawer(
      width: 420,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(left: Radius.circular(24))),
      clipBehavior: Clip.antiAlias,
      child: ListenableBuilder(
        listenable: service,
        builder: (context, _) {
          final types = service.items.map((n) => '${n['type']}').toSet().toList()..sort();
          final items = service.items.where((n) {
            if (_unreadOnly && n['is_read'] == true) return false;
            if (_type != null && n['type'] != _type) return false;
            return true;
          }).toList();

          // Hatiin ayon sa araw: Today / Yesterday / Earlier
          final today = DateUtils.dateOnly(DateTime.now());
          String groupOf(Map<String, dynamic> n) {
            final d = parseDate(n['created_at'])?.toLocal();
            if (d == null) return 'ntEarlier';
            final day = DateUtils.dateOnly(d);
            if (day == today) return 'ntToday';
            if (day == today.subtract(const Duration(days: 1))) return 'ntYesterday';
            return 'ntEarlier';
          }

          final groups = <String, List<Map<String, dynamic>>>{};
          for (final n in items) {
            groups.putIfAbsent(groupOf(n), () => []).add(n);
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    // ---------------- Reminders ----------------
                    if (reminders.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFF5C451), width: 1.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.notification_important_outlined, size: 18, color: Color(0xFF92400E)),
                                const SizedBox(width: 6),
                                Text(tr('needsAttention'),
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            for (final r in reminders)
                              InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () {
                                  Navigator.pop(context);
                                  widget.onOpen(r.module, r.bookingStatus);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 7),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 30,
                                        height: 30,
                                        decoration: BoxDecoration(
                                          color: r.color.withValues(alpha: 0.14),
                                          borderRadius: BorderRadius.circular(9),
                                        ),
                                        child: Icon(r.icon, color: r.color, size: 16),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(r.title,
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                      ),
                                      const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.muted),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    // ---------------- Notifications ----------------
                    if (!service.available)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(tr('notifSetupNeeded'), style: const TextStyle(color: AppColors.muted)),
                      )
                    else ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          CountTabs<bool>(
                            value: _unreadOnly,
                            onChanged: (v) => setState(() => _unreadOnly = v),
                            items: [
                              (value: false, label: tr('filterAll'), count: service.items.length),
                              (value: true, label: tr('unread'), count: service.unreadCount),
                            ],
                          ),
                          if (types.length > 1)
                            PopupMenuButton<String>(
                              tooltip: tr('ntType'),
                              position: PopupMenuPosition.under,
                              onSelected: (v) => setState(() => _type = v == '__all' ? null : v),
                              itemBuilder: (context) => [
                                CheckedPopupMenuItem(value: '__all', checked: _type == null, child: Text(tr('ntAllTypes'))),
                                for (final t in types)
                                  CheckedPopupMenuItem(
                                    value: t,
                                    checked: _type == t,
                                    child: Text(titleCase(notificationTitle({'type': t}))),
                                  ),
                              ],
                              child: FilterPill(
                                icon: _type == null ? Icons.filter_list_rounded : notificationIcon(_type),
                                label: _type == null ? tr('ntAllTypes') : titleCase(notificationTitle({'type': _type})),
                                active: _type != null,
                                dropdown: true,
                                onClear: () => setState(() => _type = null),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (items.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.10),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.notifications_none_rounded, color: AppColors.primary, size: 28),
                              ),
                              const SizedBox(height: 10),
                              Text(tr('noNotifications'),
                                  textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
                            ],
                          ),
                        ),
                      for (final g in const ['ntToday', 'ntYesterday', 'ntEarlier'])
                        if (groups[g] != null) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
                            child: Text(tr(g).toUpperCase(), style: _caps),
                          ),
                          for (final n in groups[g]!) _notificationTile(n),
                          const SizedBox(height: 6),
                        ],
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context) {
    final unread = service.unreadCount;
    return Container(
      color: AppColors.ink,
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 18, 12, 18),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.inkRaised, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.notifications_rounded, color: Colors.white, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('notifications'),
                    style: const TextStyle(
                        fontFamily: 'Poppins', color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700)),
                Text(
                  unread == 0 ? tr('ntAllCaughtUp') : tr('ntUnreadCount', {'n': unread}),
                  style: const TextStyle(color: AppColors.inkText, fontSize: 12.5),
                ),
              ],
            ),
          ),
          if (unread > 0)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: service.markAllRead,
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: Text(tr('markAllRead')),
            ),
          IconButton(
            tooltip: tr('close'),
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _notificationTile(Map<String, dynamic> n) {
    final unread = n['is_read'] != true;
    final type = n['type'] as String?;
    final color = notificationColor(type);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: unread ? AppColors.primary.withValues(alpha: 0.35) : AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            service.markRead(n);
            Navigator.pop(context);
            widget.onOpen(notificationModule(type), notificationOpenFilter(n));
          },
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: unread ? color : Colors.transparent, width: 3)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
                  child: Icon(notificationIcon(type), color: color, size: 19),
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
                              titleCase(notificationTitle(n)),
                              style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600, fontSize: 14),
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
