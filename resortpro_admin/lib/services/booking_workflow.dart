import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_data.dart';
import 'notification_service.dart';

/// Isang hakbang sa booking workflow (hal. Confirm, Check in).
class WorkflowAction {
  const WorkflowAction({
    required this.key,
    required this.toStatus,
    required this.icon,
    this.primary = false,
    this.destructive = false,
  });

  /// Translation key ng button (hal. 'actConfirm').
  final String key;
  final String toStatus;
  final IconData icon;

  /// Ang pangunahing susunod na hakbang (malaking button).
  final bool primary;
  final bool destructive;
}

/// Booking workflow:
///
///   reserved ──confirm──▶ confirmed ──check in──▶ checked_in ──check out──▶ completed
///      │                   (fully_paid kapag bayad na lahat)
///      ├──decline──▶ cancelled
///      └── (kapag lumipas ang petsa) ──▶ no_show
class BookingWorkflow {
  BookingWorkflow._();

  static SupabaseClient get _db => Supabase.instance.client;

  static List<WorkflowAction> actionsFor(Map<String, dynamic> booking) {
    final status = booking['status'];
    final date = bookingDateOf(booking);
    final today = DateUtils.dateOnly(DateTime.now());
    final dateReached = date == null || !date.isAfter(today);

    switch (status) {
      case 'reserved':
        return [
          const WorkflowAction(key: 'actConfirm', toStatus: 'confirmed', icon: Icons.check_circle_outline, primary: true),
          const WorkflowAction(key: 'actDecline', toStatus: 'cancelled', icon: Icons.block, destructive: true),
        ];
      case 'confirmed':
      case 'fully_paid':
        return [
          WorkflowAction(key: 'actCheckIn', toStatus: 'checked_in', icon: Icons.login, primary: dateReached),
          if (dateReached)
            const WorkflowAction(key: 'actNoShow', toStatus: 'no_show', icon: Icons.person_off_outlined, destructive: true),
          const WorkflowAction(key: 'actCancel', toStatus: 'cancelled', icon: Icons.cancel_outlined, destructive: true),
        ];
      case 'checked_in':
        return [
          const WorkflowAction(key: 'actCheckOut', toStatus: 'completed', icon: Icons.logout, primary: true),
        ];
      case 'cancelled':
      case 'no_show':
        return [
          const WorkflowAction(key: 'actReopen', toStatus: 'reserved', icon: Icons.restore),
        ];
      default:
        return const [];
    }
  }

  /// Palitan ang status ng booking, i-log, at abisuhan ang client.
  static Future<void> changeStatus(
    Map<String, dynamic> booking,
    String toStatus, {
    String? note,
  }) async {
    final from = '${booking['status']}';
    final List updated;
    try {
      updated = await _db
          .from('bookings')
          .update({'status': toStatus})
          .eq('id', booking['id'])
          .select('id');
    } on PostgrestException catch (e) {
      // Kadalasan: hindi pa tinatanggap ng database ang bagong status
      // (hindi pa na-run ang supabase/admin_setup.sql).
      if (e.code == '23514' || e.code == '22P02') {
        throw Exception(
          'The database does not accept the status "$toStatus" yet. '
          'Run supabase/admin_setup.sql in the Supabase SQL Editor. (${e.message})',
        );
      }
      rethrow;
    }
    // Walang error pero walang na-update: hinarang ng RLS (walang admin policy).
    if (updated.isEmpty) {
      throw Exception(
        'The booking was not updated. This admin account has no permission to edit bookings yet. '
        'Run supabase/admin_setup.sql in the Supabase SQL Editor, and make sure this account is an admin.',
      );
    }

    await log(booking['id'], 'status_change', fromStatus: from, toStatus: toStatus, note: note);
    await NotificationService.notifyClient(
      booking['client_id']?.toString(),
      'booking_$toStatus',
      {
        'package': packageNameOf(booking),
        'date': booking['booking_date'],
        if (note != null && note.isNotEmpty) 'note': note,
      },
      refId: '${booking['id']}',
    );
  }

  /// Tawagin pagkatapos mag-record ng payment.
  /// Kapag bayad na lahat at hindi pa naka-check in, gagawing fully_paid.
  static Future<bool> afterPayment(
    Map<String, dynamic> booking,
    double amount,
    String method,
  ) async {
    final newPaid = paidOf(booking) + amount;
    final fullyPaid = newPaid >= totalOf(booking) - 0.01;
    final status = booking['status'];

    await log(booking['id'], 'payment', note: '${peso(amount)} · ${methodLabel(method)}');

    if (fullyPaid && (status == 'reserved' || status == 'confirmed')) {
      await _db.from('bookings').update({'status': 'fully_paid'}).eq('id', booking['id']);
      await log(booking['id'], 'status_change', fromStatus: '$status', toStatus: 'fully_paid');
    }

    await NotificationService.notifyClient(
      booking['client_id']?.toString(),
      fullyPaid ? 'payment_complete' : 'payment_received',
      {
        'package': packageNameOf(booking),
        'amount': amount,
        'balance': (totalOf(booking) - newPaid).clamp(0, double.infinity),
      },
      refId: '${booking['id']}',
    );
    return fullyPaid;
  }

  /// I-verify ang proof of payment ng client.
  /// Kapag bayad na lahat, gagawing fully_paid ang booking (kung hindi pa naka-check in).
  static Future<bool> verifyPayment(
    Map<String, dynamic> payment,
    Map<String, dynamic> booking,
  ) async {
    await _db.from('payments').update({
      'status': 'verified',
      'reviewed_by': _db.auth.currentUser?.id,
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      'reject_reason': null,
    }).eq('id', payment['id']);

    final amount = asDouble(payment['amount']);
    final newPaid = paidOf(booking) + amount;
    final fullyPaid = newPaid >= totalOf(booking) - 0.01;
    final status = booking['status'];

    await log(
      booking['id'],
      'payment_verified',
      note: '${peso(amount)} · ${methodLabel(payment['method'] as String?)}'
          '${payment['reference_no'] != null ? ' · Ref ${payment['reference_no']}' : ''}',
    );

    if (fullyPaid && (status == 'reserved' || status == 'confirmed')) {
      await _db.from('bookings').update({'status': 'fully_paid'}).eq('id', booking['id']);
      await log(booking['id'], 'status_change', fromStatus: '$status', toStatus: 'fully_paid');
    } else if (status == 'reserved' && newPaid + 0.01 >= (totalOf(booking) * 0.5).roundToDouble()) {
      // Verified na ang 50% downpayment: kusang naka-reserve (confirmed) na ang petsa.
      await _db.from('bookings').update({'status': 'confirmed'}).eq('id', booking['id']);
      await log(booking['id'], 'status_change', fromStatus: 'reserved', toStatus: 'confirmed',
          note: 'Downpayment verified');
      await NotificationService.notifyClient(
        booking['client_id']?.toString(),
        'booking_confirmed',
        {'package': packageNameOf(booking), 'date': booking['booking_date']},
        refId: '${booking['id']}',
      );
    }

    await NotificationService.notifyClient(
      booking['client_id']?.toString(),
      fullyPaid ? 'payment_complete' : 'payment_verified',
      {
        'package': packageNameOf(booking),
        'amount': amount,
        'balance': math.max(0.0, totalOf(booking) - newPaid),
        'reference_no': payment['reference_no'],
      },
      refId: '${booking['id']}',
    );
    return fullyPaid;
  }

  /// I-reject ang proof of payment (hal. maling reference number).
  static Future<void> rejectPayment(
    Map<String, dynamic> payment,
    Map<String, dynamic> booking,
    String reason,
  ) async {
    await _db.from('payments').update({
      'status': 'rejected',
      'reviewed_by': _db.auth.currentUser?.id,
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      'reject_reason': reason.isEmpty ? null : reason,
    }).eq('id', payment['id']);

    await log(
      booking['id'],
      'payment_rejected',
      note: '${peso(asDouble(payment['amount']))}${reason.isEmpty ? '' : ' · $reason'}',
    );

    await NotificationService.notifyClient(
      booking['client_id']?.toString(),
      'payment_rejected',
      {
        'package': packageNameOf(booking),
        'amount': asDouble(payment['amount']),
        'reference_no': payment['reference_no'],
        if (reason.isNotEmpty) 'reason': reason,
      },
      refId: '${booking['id']}',
    );
  }

  /// Gawing user-friendly ang error mula sa database guard.
  static String friendlyError(Object e) {
    final text = '$e';
    if (text.contains('DATE_TAKEN')) return 'DATE_TAKEN';
    if (text.contains('DATE_BLOCKED')) return 'DATE_BLOCKED';
    return text;
  }

  static Future<void> saveNotes(Map<String, dynamic> booking, String notes) async {
    await _db.from('bookings').update({'admin_notes': notes}).eq('id', booking['id']);
    await log(booking['id'], 'note', note: notes);
  }

  /// Isulat sa activity log. Tahimik na lalaktawan kapag wala pa ang table.
  static Future<void> log(
    dynamic bookingId,
    String action, {
    String? fromStatus,
    String? toStatus,
    String? note,
  }) async {
    try {
      await _db.from('booking_logs').insert({
        'booking_id': '$bookingId',
        'action': action,
        'from_status': fromStatus,
        'to_status': toStatus,
        'note': note,
      });
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> logsFor(dynamic bookingId) async {
    try {
      final rows = await _db
          .from('booking_logs')
          .select()
          .eq('booking_id', '$bookingId')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      return [];
    }
  }
}
