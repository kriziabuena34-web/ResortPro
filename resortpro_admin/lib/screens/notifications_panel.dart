import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/admin_data.dart';
import '../services/notification_service.dart';

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

enum _NotifFilter { all, unread }

class _NotificationsPanelState extends State<NotificationsPanel> {
  final service = NotificationService.instance;
  _NotifFilter _filter = _NotifFilter.all;
  String? _type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reminders = widget.data == null ? <AdminReminder>[] : remindersFor(widget.data!);

    return Drawer(
      width: 400,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: service,
          builder: (context, _) {
            final types = service.items.map((n) => '${n['type']}').toSet().toList()..sort();
            final items = service.items.where((n) {
              if (_filter == _NotifFilter.unread && n['is_read'] == true) return false;
              if (_type != null && n['type'] != _type) return false;
              return true;
            }).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr('notifications'),
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (service.unreadCount > 0)
                        TextButton(
                          onPressed: service.markAllRead,
                          child: Text(tr('markAllRead')),
                        ),
                      IconButton(
                        tooltip: tr('close'),
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      // ---------------- Reminders ----------------
                      if (reminders.isNotEmpty) ...[
                        _sectionLabel(theme, tr('needsAttention')),
                        for (final r in reminders)
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: r.color.withValues(alpha: 0.15),
                              child: Icon(r.icon, color: r.color, size: 20),
                            ),
                            title: Text(r.title),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.pop(context);
                              widget.onOpen(r.module, r.bookingStatus);
                            },
                          ),
                        const Divider(),
                      ],

                      // ---------------- Notifications ----------------
                      _sectionLabel(theme, tr('recentActivity')),
                      if (!service.available)
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(tr('notifSetupNeeded'), style: theme.textTheme.bodyMedium),
                        )
                      else ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              ChoiceChip(
                                label: Text(tr('filterAll')),
                                selected: _filter == _NotifFilter.all && _type == null,
                                onSelected: (_) => setState(() {
                                  _filter = _NotifFilter.all;
                                  _type = null;
                                }),
                              ),
                              ChoiceChip(
                                label: Text('${tr('unread')} (${service.unreadCount})'),
                                selected: _filter == _NotifFilter.unread,
                                onSelected: (_) => setState(() {
                                  _filter = _filter == _NotifFilter.unread
                                      ? _NotifFilter.all
                                      : _NotifFilter.unread;
                                }),
                              ),
                              for (final t in types)
                                ChoiceChip(
                                  avatar: Icon(notificationIcon(t), size: 16),
                                  label: Text(notificationTitle({'type': t})),
                                  selected: _type == t,
                                  onSelected: (_) => setState(() => _type = _type == t ? null : t),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              children: [
                                Icon(Icons.notifications_none, size: 48, color: theme.colorScheme.outline),
                                const SizedBox(height: 8),
                                Text(tr('noNotifications'), textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                        for (final n in items) _notificationTile(theme, n),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 1.1,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _notificationTile(ThemeData theme, Map<String, dynamic> n) {
    final unread = n['is_read'] != true;
    final type = n['type'] as String?;
    final color = notificationColor(type);

    return Material(
      color: unread ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25) : Colors.transparent,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(notificationIcon(type), color: color, size: 20),
        ),
        title: Text(
          notificationTitle(n),
          style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.normal),
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
        onTap: () {
          service.markRead(n);
          Navigator.pop(context);
          widget.onOpen(notificationModule(type), notificationOpenFilter(n));
        },
      ),
    );
  }
}
