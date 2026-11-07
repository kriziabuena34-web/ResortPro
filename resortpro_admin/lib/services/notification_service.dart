import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_strings.dart';
import 'admin_data.dart';

/// Real-time notifications para sa admin.
///
/// Galing ang notifications sa `notifications` table (ginagawa ng database
/// triggers kapag may bagong booking, payment, o verification request).
/// Kapag wala pa ang table (hindi pa na-run ang admin_setup.sql),
/// `available = false` at hindi magka-crash ang app.
class NotificationService extends ChangeNotifier {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  SupabaseClient get _db => Supabase.instance.client;

  List<Map<String, dynamic>> items = [];
  bool available = true;
  bool loaded = false;
  RealtimeChannel? _channel;

  int get unreadCount => items.where((n) => n['is_read'] != true).length;

  Future<void> load() async {
    try {
      final rows = await _db
          .from('notifications')
          .select()
          .eq('audience', 'admin')
          .order('created_at', ascending: false)
          .limit(100);
      items = List<Map<String, dynamic>>.from(rows);
      available = true;
    } catch (_) {
      available = false;
    }
    loaded = true;
    notifyListeners();
  }

  /// Makinig sa bagong notifications. Tinatawag ang [onNew] sa bawat bago.
  void subscribe(void Function(Map<String, dynamic> notification) onNew) {
    unsubscribe();
    _channel = _db
        .channel('admin-notifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          callback: (payload) {
            final row = Map<String, dynamic>.from(payload.newRecord);
            if (row['audience'] != 'admin') return;
            items = [row, ...items];
            notifyListeners();
            onNew(row);
          },
        )
        .subscribe();
  }

  void unsubscribe() {
    final channel = _channel;
    if (channel != null) {
      _db.removeChannel(channel);
      _channel = null;
    }
  }

  Future<void> markRead(Map<String, dynamic> notification) async {
    if (notification['is_read'] == true) return;
    notification['is_read'] = true;
    notifyListeners();
    try {
      await _db.from('notifications').update({'is_read': true}).eq('id', notification['id']);
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    final unread = items.where((n) => n['is_read'] != true).toList();
    if (unread.isEmpty) return;
    for (final n in unread) {
      n['is_read'] = true;
    }
    notifyListeners();
    try {
      await _db
          .from('notifications')
          .update({'is_read': true})
          .eq('audience', 'admin')
          .eq('is_read', false);
    } catch (_) {}
  }

  /// Magpadala ng notification sa isang client (makikita sa client app
  /// kapag nalagyan na ito ng notifications screen).
  static Future<void> notifyClient(
    String? clientId,
    String type,
    Map<String, dynamic> data, {
    String? refId,
  }) async {
    if (clientId == null || clientId.isEmpty) return;
    try {
      await Supabase.instance.client.from('notifications').insert({
        'audience': 'client',
        'recipient_id': clientId,
        'type': type,
        'data': data,
        'ref_id': refId,
      });
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Pagpapakita ng notification
// ---------------------------------------------------------------------------

Map<String, dynamic> notificationData(Map<String, dynamic> n) {
  final d = n['data'];
  return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
}

String notificationTitle(Map<String, dynamic> n) {
  switch (n['type']) {
    case 'new_booking':
      return tr('notifNewBookingTitle');
    case 'client_payment':
      return tr('notifPaymentTitle');
    case 'verification_request':
      return tr('notifVerificationTitle');
    case 'refund_request':
      return tr('notifRefundTitle');
    default:
      return capitalize('${n['type'] ?? ''}'.replaceAll('_', ' '));
  }
}

String notificationBody(Map<String, dynamic> n) {
  final d = notificationData(n);
  switch (n['type']) {
    case 'new_booking':
      return tr('notifNewBookingBody', {
        'client': '${d['client'] ?? ''}'.toUpperCase(),
        'package': d['package'] ?? '',
        'date': formatDate(parseDate(d['date'])),
      });
    case 'client_payment':
      return tr('notifPaymentBody', {
        'client': '${d['client'] ?? ''}'.toUpperCase(),
        'amount': peso(asDouble(d['amount'])),
        'method': methodLabel(d['method'] as String?),
        'package': d['package'] ?? '',
      });
    case 'verification_request':
      return tr('notifVerificationBody', {'client': '${d['client'] ?? ''}'.toUpperCase()});
    case 'refund_request':
      return tr('notifRefundBody', {
        'client': '${d['client'] ?? ''}'.toUpperCase(),
        'package': d['package'] ?? '',
        'date': formatDate(parseDate(d['date'])),
        'amount': peso(asDouble(d['amount'])),
      });
    default:
      return '';
  }
}

IconData notificationIcon(String? type) {
  switch (type) {
    case 'new_booking':
      return Icons.event_available;
    case 'client_payment':
      return Icons.payments;
    case 'verification_request':
      return Icons.badge_outlined;
    case 'refund_request':
      return Icons.currency_exchange;
    default:
      return Icons.notifications;
  }
}

Color notificationColor(String? type) {
  switch (type) {
    case 'new_booking':
      return const Color(0xFF2F6FED);
    case 'client_payment':
      return const Color(0xFF2E9E5B);
    case 'verification_request':
      return const Color(0xFFE08A00);
    default:
      return const Color(0xFF7A7F87);
  }
}

/// Filter na ipapasa sa module (hal. Payments → pending tab).
String? notificationFilter(String? type) =>
    type == 'client_payment' ? 'pending' : (type == 'refund_request' ? 'refunds' : null);

/// Module na bubuksan kapag pinindot ang notification.
int notificationModule(String? type) {
  switch (type) {
    case 'client_payment':
    case 'refund_request':
      return 5; // Payments
    case 'verification_request':
      return 4; // Verifications
    default:
      return 1; // Bookings
  }
}

String timeAgo(dynamic createdAt) {
  final d = parseDate(createdAt);
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return tr('justNow');
  if (diff.inMinutes < 60) return tr('minutesAgo', {'n': diff.inMinutes});
  if (diff.inHours < 24) return tr('hoursAgo', {'n': diff.inHours});
  if (diff.inDays < 7) return tr('daysAgo', {'n': diff.inDays});
  return formatDate(d);
}

// ---------------------------------------------------------------------------
// Reminders: kinukuwenta mula sa data (hindi naka-save sa database)
// ---------------------------------------------------------------------------

class AdminReminder {
  const AdminReminder({
    required this.icon,
    required this.color,
    required this.title,
    required this.count,
    required this.module,
    this.bookingStatus,
  });

  final IconData icon;
  final Color color;
  final String title;
  final int count;

  /// Module na bubuksan (index sa sidebar).
  final int module;

  /// Filter na gagamitin sa Bookings module.
  final String? bookingStatus;
}

List<AdminReminder> remindersFor(AdminData data) {
  final today = DateUtils.dateOnly(DateTime.now());
  final in3Days = today.add(const Duration(days: 3));

  bool isOn(Map<String, dynamic> b, DateTime day) => bookingDateOf(b) == day;

  final toConfirm = data.bookings.where((b) => b['status'] == 'reserved').length;

  final checkInsToday = data.bookings
      .where((b) =>
          isOn(b, today) && (b['status'] == 'confirmed' || b['status'] == 'fully_paid'))
      .length;

  final overdue = data.bookings.where((b) {
    final d = bookingDateOf(b);
    return d != null &&
        d.isBefore(today) &&
        const ['reserved', 'confirmed', 'fully_paid'].contains(b['status']);
  }).length;

  final balanceDue = data.activeBookings.where((b) {
    final d = bookingDateOf(b);
    return d != null &&
        !d.isBefore(today) &&
        !d.isAfter(in3Days) &&
        remainingOf(b) > 0 &&
        b['status'] != 'completed';
  }).length;

  final stillCheckedIn = data.bookings
      .where((b) {
        final d = bookingDateOf(b);
        return b['status'] == 'checked_in' && d != null && d.isBefore(today);
      })
      .length;

  final pending = data.pendingAccounts.length;
  final pendingProofs = data.pendingPayments.length;

  return [
    if (pendingProofs > 0)
      AdminReminder(
        icon: Icons.fact_check_outlined,
        color: const Color(0xFFE08A00),
        title: tr('remPendingProofs', {'n': pendingProofs}),
        count: pendingProofs,
        module: 5,
        bookingStatus: 'pending',
      ),
    if (toConfirm > 0)
      AdminReminder(
        icon: Icons.pending_actions,
        color: const Color(0xFFE08A00),
        title: tr('remToConfirm', {'n': toConfirm}),
        count: toConfirm,
        module: 1,
        bookingStatus: 'reserved',
      ),
    if (checkInsToday > 0)
      AdminReminder(
        icon: Icons.login,
        color: const Color(0xFF0E9AA7),
        title: tr('remCheckInsToday', {'n': checkInsToday}),
        count: checkInsToday,
        module: 1,
        bookingStatus: 'today',
      ),
    if (balanceDue > 0)
      AdminReminder(
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFFD64545),
        title: tr('remBalanceDue', {'n': balanceDue}),
        count: balanceDue,
        module: 1,
        bookingStatus: 'balance',
      ),
    if (overdue > 0)
      AdminReminder(
        icon: Icons.history,
        color: const Color(0xFF8D6E63),
        title: tr('remOverdue', {'n': overdue}),
        count: overdue,
        module: 1,
        bookingStatus: 'overdue',
      ),
    if (stillCheckedIn > 0)
      AdminReminder(
        icon: Icons.logout,
        color: const Color(0xFF6B5BD2),
        title: tr('remStillCheckedIn', {'n': stillCheckedIn}),
        count: stillCheckedIn,
        module: 1,
        bookingStatus: 'checked_in',
      ),
    if (pending > 0)
      AdminReminder(
        icon: Icons.badge_outlined,
        color: const Color(0xFF2F6FED),
        title: tr('remPendingVerification', {'n': pending}),
        count: pending,
        module: 4,
      ),
  ];
}
