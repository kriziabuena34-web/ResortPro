import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_strings.dart';

/// Lahat ng data na kailangan ng admin panel, kinukuha nang sabay-sabay
/// para iisang refresh lang ang kailangan ng bawat module.
class AdminData {
  AdminData({
    required this.bookings,
    required this.clients,
    required this.packages,
    this.blockedDates = const [],
    this.pricingRules = const [],
    this.refunds = const [],
  });

  /// Galing sa refund_requests (Part 10 ng SQL), pinakabago muna.
  final List<Map<String, dynamic>> refunds;

  List<Map<String, dynamic>> get pendingRefunds => refunds.where((r) => r['status'] == 'pending').toList();

  Map<String, dynamic>? bookingById(dynamic id) {
    for (final b in bookings) {
      if ('${b['id']}' == '$id') return b;
    }
    return null;
  }

  final List<Map<String, dynamic>> bookings;
  final List<Map<String, dynamic>> clients;
  final List<Map<String, dynamic>> packages;

  /// Galing sa blocked_dates (walang laman kapag hindi pa na-setup).
  final List<Map<String, dynamic>> blockedDates;

  /// Galing sa pricing_rules (walang laman kapag hindi pa na-setup).
  final List<Map<String, dynamic>> pricingRules;

  /// Lahat ng bayad na naghihintay ng verification, pinakaluma muna.
  List<({Map<String, dynamic> payment, Map<String, dynamic> booking})> get pendingPayments {
    final list = [
      for (final b in bookings)
        for (final p in paymentsOf(b))
          if (p['status'] == 'pending') (payment: p, booking: b),
    ];
    list.sort((a, b) => '${a.payment['created_at']}'.compareTo('${b.payment['created_at']}'));
    return list;
  }

  /// Blocked dates para sa isang araw (kasama ang para sa buong resort).
  List<Map<String, dynamic>> blocksOn(DateTime day, {dynamic packageId}) {
    final key = dateKey(day);
    return blockedDates.where((b) {
      if ('${b['block_date']}' != key) return false;
      if (packageId == null) return true;
      return b['package_id'] == null || '${b['package_id']}' == '$packageId';
    }).toList();
  }

  /// Anong bahagi ng araw ang ginagamit ng package ('day' at/o 'night').
  /// Iisang lugar ang buong resort, kaya bawal magsabay ang magkapatong na oras.
  /// (Kapareho ng public.package_slots sa database.)
  Set<String> slotsOf(dynamic packageId) {
    final p = packageById(packageId);
    if (p == null) return {'day', 'night'};
    int? mins(dynamic t) {
      final parts = '${t ?? ''}'.split(':');
      if (parts.length < 2) return null;
      final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
      return h == null || m == null ? null : h * 60 + m;
    }

    final st = mins(p['start_time']), en = mins(p['end_time']);
    if (st == null || en == null) {
      final name = '${p['name']}'.toLowerCase();
      if (name.contains('22')) return {'day', 'night'};
      if (name.contains('overnight')) return {'night'};
      return {'day'};
    }
    final s = <String>{};
    if (st < 17 * 60) s.add('day');
    if (en <= st || st >= 17 * 60) s.add('night');
    return s.isEmpty ? {'day'} : s;
  }

  /// May aktibong booking na ba na kasabay ng oras ng [packageId] sa [day]?
  bool isTimeTaken(DateTime day, dynamic packageId, {dynamic excludeBookingId}) {
    final mine = slotsOf(packageId);
    return bookings.any((b) =>
        !isInactive(b) &&
        bookingDateOf(b) == day &&
        (excludeBookingId == null || '${b['id']}' != '$excludeBookingId') &&
        slotsOf(b['package_id']).intersection(mine).isNotEmpty);
  }

  Map<String, dynamic>? packageById(dynamic id) {
    for (final p in packages) {
      if ('${p['id']}' == '$id') return p;
    }
    return null;
  }

  List<Map<String, dynamic>> get pendingAccounts => clients
      .where((c) => c['verification_status'] == 'pending')
      .toList();

  /// Bookings na hindi cancelled o no-show (ito ang binibilang sa revenue).
  List<Map<String, dynamic>> get activeBookings =>
      bookings.where((b) => !isInactive(b)).toList();

  List<Map<String, dynamic>> bookingsOfClient(String clientId) =>
      bookings.where((b) => '${b['client_id']}' == clientId).toList();

  static Future<AdminData> fetch() async {
    final supabase = Supabase.instance.client;

    // Kusang "No-show": hindi nag-check in at lumipas na ang oras ng package (Part 13 ng SQL).
    try {
      await supabase.rpc('mark_no_shows');
    } catch (_) {}

    final bookings = await supabase
        .from('bookings')
        .select(
          '*, packages(name, price), '
          'profiles!bookings_client_id_fkey(google_display_name, first_name, last_name, phone), '
          'payments(*)',
        )
        .order('booking_date', ascending: false);

    final clients =
        await supabase.from('profiles').select().eq('role', 'client');

    final packages = await supabase.from('packages').select().order('id');

    // Pangalan ng mga admin/staff (para sa "Received by", "Verified by", at pagbati).
    try {
      final admins = await supabase.from('profiles').select('id, first_name, last_name').eq('role', 'admin');
      _staffNames.clear();
      for (final a in admins) {
        final n = _plainName(a['first_name'], a['last_name']);
        if (n.isNotEmpty) _staffNames['${a['id']}'] = n;
      }
    } catch (_) {}

    // Opsyonal: gagana pa rin ang app kahit hindi pa na-run ang Part 2 ng SQL.
    List<Map<String, dynamic>> blocked = [];
    List<Map<String, dynamic>> rules = [];
    try {
      blocked = List<Map<String, dynamic>>.from(
        await supabase.from('blocked_dates').select().order('block_date'),
      );
    } catch (_) {}
    try {
      rules = List<Map<String, dynamic>>.from(
        await supabase.from('pricing_rules').select().order('priority', ascending: false),
      );
    } catch (_) {}
    List<Map<String, dynamic>> refunds = [];
    try {
      refunds = List<Map<String, dynamic>>.from(
        await supabase.from('refund_requests').select().order('created_at', ascending: false),
      );
    } catch (_) {}

    return AdminData(
      bookings: List<Map<String, dynamic>>.from(bookings),
      clients: List<Map<String, dynamic>>.from(clients),
      packages: List<Map<String, dynamic>>.from(packages),
      blockedDates: blocked,
      pricingRules: rules,
      refunds: refunds,
    );
  }
}

// ---------------------------------------------------------------------------
// Pangalan ng staff (admin)
// ---------------------------------------------------------------------------

final Map<String, String> _staffNames = {};

String _plainName(dynamic first, dynamic last) {
  String part(dynamic v) {
    final t = '${v ?? ''}'.trim();
    return t.toUpperCase() == 'N/A' ? '' : t;
  }

  return [part(first), part(last)].where((e) => e.isNotEmpty).join(' ');
}

/// "John Sairon" ng admin na may ganitong id (null kapag hindi admin o wala pang pangalan).
String? staffNameOf(dynamic id) => id == null ? null : _staffNames['$id'];

/// Pangalan ng naka-login na admin; email kapag wala pang pangalan.
String currentStaffName() {
  final u = Supabase.instance.client.auth.currentUser;
  return staffNameOf(u?.id) ?? u?.email ?? 'Admin';
}

/// Unang pangalan ng naka-login na admin (para sa pagbati), o null.
String? currentStaffFirstName() {
  final n = staffNameOf(Supabase.instance.client.auth.currentUser?.id);
  return n?.split(' ').first;
}

/// I-save ang sariling pangalan ng naka-login na admin.
Future<void> saveMyStaffName(String first, String last) async {
  final supabase = Supabase.instance.client;
  final id = supabase.auth.currentUser!.id;
  await supabase.from('profiles').update({'first_name': first.trim(), 'last_name': last.trim()}).eq('id', id);
  final n = _plainName(first, last);
  if (n.isEmpty) {
    _staffNames.remove(id);
  } else {
    _staffNames[id] = n;
  }
}

// ---------------------------------------------------------------------------
// Helpers para sa booking at payment data
// ---------------------------------------------------------------------------

double asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

int asInt(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

List<Map<String, dynamic>> paymentsOf(Map<String, dynamic> booking) {
  final list = booking['payments'] as List? ?? [];
  return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

double totalOf(Map<String, dynamic> booking) =>
    asDouble(booking['total_amount']);

/// Verified na bayad lang ang binibilang (ang pending/rejected ay hindi).
bool isVerifiedPayment(Map<String, dynamic> p) =>
    p['status'] == null || p['status'] == 'verified';

double paidOf(Map<String, dynamic> booking) => paymentsOf(booking)
    .where(isVerifiedPayment)
    .fold<double>(0, (sum, p) => sum + asDouble(p['amount']));

double pendingPaidOf(Map<String, dynamic> booking) => paymentsOf(booking)
    .where((p) => p['status'] == 'pending')
    .fold<double>(0, (sum, p) => sum + asDouble(p['amount']));

double remainingOf(Map<String, dynamic> booking) =>
    math.max(0.0, totalOf(booking) - paidOf(booking));

bool isCancelled(Map<String, dynamic> booking) =>
    booking['status'] == 'cancelled';

/// Cancelled o no-show: hindi na aktibo ang booking.
bool isInactive(Map<String, dynamic> booking) =>
    booking['status'] == 'cancelled' || booking['status'] == 'no_show';

/// Lahat ng booking status, sunod sa daloy ng workflow.
const bookingStatuses = [
  'reserved',
  'confirmed',
  'fully_paid',
  'checked_in',
  'completed',
  'no_show',
  'cancelled',
];

String packageNameOf(Map<String, dynamic> booking) {
  final pkg = booking['packages'];
  if (pkg is Map && pkg['name'] != null) return pkg['name'].toString();
  return tr('unknownPackage');
}

/// Pangalan ng booker: "JUAN DELA CRUZ" (first name, last name, all caps).
String clientNameOf(Map<String, dynamic> booking) {
  final p = booking['profiles'];
  if (p is Map) {
    final n = upperFirstLast(p['first_name'], p['last_name'], fallback: p['google_display_name']);
    if (n.isNotEmpty) return n;
  }
  final guest = '${booking['guest_name'] ?? ''}'.trim();
  if (guest.isNotEmpty) return guest.replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
  return tr('unknownClient');
}

/// Pangalan para sa resibo at notification: "JUAN DELA CRUZ" (first name, last name, all caps).
String upperFirstLast(dynamic first, dynamic last, {dynamic fallback}) {
  String part(dynamic v) {
    final t = '${v ?? ''}'.trim();
    return t.toUpperCase() == 'N/A' ? '' : t;
  }

  final full = [part(first), part(last)].where((e) => e.isNotEmpty).join(' ');
  final name = full.isNotEmpty ? full : part(fallback);
  return name.replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
}

/// Pangalan ng guest sa resibo: "JUAN DELA CRUZ".
String receiptNameOf(Map<String, dynamic> booking) {
  final p = booking['profiles'];
  if (p is Map) {
    final n = upperFirstLast(p['first_name'], p['last_name'], fallback: p['google_display_name']);
    if (n.isNotEmpty) return n;
  }
  final guest = '${booking['guest_name'] ?? ''}'.trim();
  return guest.isEmpty ? tr('unknownClient').toUpperCase() : guest.toUpperCase();
}

String? clientPhoneOf(Map<String, dynamic> booking) {
  final p = booking['profiles'];
  if (p is Map && p['phone'] != null) return '${p['phone']}';
  final guestPhone = '${booking['guest_phone'] ?? ''}'.trim();
  return guestPhone.isEmpty ? null : guestPhone;
}

/// Saan galing ang booking: online (app), walk_in, o phone.
String bookingSourceOf(Map<String, dynamic> booking) => '${booking['source'] ?? 'online'}';

String sourceLabel(String? source) {
  switch (source) {
    case 'walk_in':
      return tr('sourceWalkIn');
    case 'phone':
      return tr('sourcePhone');
    default:
      return tr('sourceOnline');
  }
}

IconData sourceIcon(String? source) {
  switch (source) {
    case 'walk_in':
      return Icons.directions_walk;
    case 'phone':
      return Icons.phone_in_talk_outlined;
    default:
      return Icons.phone_android;
  }
}

String paymentStatusLabel(String? status) {
  switch (status) {
    case 'pending':
      return tr('payPending');
    case 'rejected':
      return tr('payRejected');
    default:
      return tr('payVerified');
  }
}

Color paymentStatusColor(String? status) {
  switch (status) {
    case 'pending':
      return const Color(0xFFE08A00);
    case 'rejected':
      return const Color(0xFFD64545);
    default:
      return const Color(0xFF2E9E5B);
  }
}

String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Kinukuwenta ang presyo ayon sa pricing rules (katulad ng price_for sa database).
/// Ginagamit sa preview at analytics; ang database pa rin ang masusunod sa booking.
double priceForLocal(
  Map<String, dynamic> package,
  DateTime date,
  List<Map<String, dynamic>> rules,
) {
  final base = asDouble(package['price']);
  final day = DateUtils.dateOnly(date);
  final matches = rules.where((r) {
    if (r['is_active'] == false) return false;
    if (r['package_id'] != null && '${r['package_id']}' != '${package['id']}') return false;
    final start = parseDate(r['start_date']);
    final end = parseDate(r['end_date']);
    if (start != null && day.isBefore(DateUtils.dateOnly(start))) return false;
    if (end != null && day.isAfter(DateUtils.dateOnly(end))) return false;
    final days = (r['days_of_week'] as List?)?.map((e) => asInt(e)).toList() ?? const <int>[];
    if (days.isNotEmpty && !days.contains(day.weekday)) return false;
    return true;
  }).toList()
    ..sort((a, b) {
      final byPriority = asInt(b['priority']).compareTo(asInt(a['priority']));
      if (byPriority != 0) return byPriority;
      final aPkg = a['package_id'] != null ? 1 : 0;
      final bPkg = b['package_id'] != null ? 1 : 0;
      if (aPkg != bPkg) return bPkg.compareTo(aPkg);
      return asInt(b['id']).compareTo(asInt(a['id']));
    });

  if (matches.isEmpty) return base;
  final r = matches.first;
  final value = asDouble(r['value']);
  switch (r['adjust_type']) {
    case 'percent':
      return (base * (1 + value / 100)).roundToDouble();
    case 'fixed_amount':
      return math.max(0.0, base + value);
    default:
      return value;
  }
}

int guestsOf(Map<String, dynamic> booking) => asInt(booking['total_pax']);

DateTime? parseDate(dynamic v) {
  if (v == null) return null;
  final d = DateTime.tryParse(v.toString());
  return d?.toLocal();
}

DateTime? bookingDateOf(Map<String, dynamic> booking) {
  final d = parseDate(booking['booking_date']);
  return d == null ? null : DateUtils.dateOnly(d);
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

// Naka-translate ayon sa napiling wika (tingnan ang l10n/app_strings.dart).
List<String> get monthNames => monthNamesTr;
List<String> get monthShort => monthShortTr;

String peso(num value) {
  final negative = value < 0;
  final digits = value.abs().round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return '${negative ? '-' : ''}₱$buf';
}

String pesoCompact(num value) {
  final v = value.abs();
  if (v >= 1000000) return '₱${(value / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '₱${(value / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}k';
  return '₱${value.round()}';
}

String formatDate(DateTime? d) {
  if (d == null) return '—';
  return '${monthShort[d.month - 1]} ${d.day}, ${d.year}';
}

String formatDateTime(DateTime? d) {
  if (d == null) return '—';
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  return '${formatDate(d)} $h12:$minute ${d.hour >= 12 ? 'PM' : 'AM'}';
}

String formatTime(dynamic value) {
  if (value == null) return '';
  final parts = value.toString().split(':');
  if (parts.length < 2) return value.toString();
  final hour = int.tryParse(parts[0]) ?? 0;
  final period = hour >= 12 ? 'PM' : 'AM';
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$h12:${parts[1]} $period';
}

String capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// ---------------------------------------------------------------------------
// Status at payment method
// ---------------------------------------------------------------------------

String statusLabel(String? status) {
  switch (status) {
    case 'reserved':
      return tr('statusReserved');
    case 'confirmed':
      return tr('statusConfirmed');
    case 'fully_paid':
      return tr('statusFullyPaid');
    case 'checked_in':
      return tr('statusCheckedIn');
    case 'completed':
      return tr('statusCompleted');
    case 'no_show':
      return tr('statusNoShow');
    case 'cancelled':
      return tr('statusCancelled');
    default:
      return capitalize((status ?? 'unknown').replaceAll('_', ' '));
  }
}

Color statusColor(String? status) {
  switch (status) {
    case 'reserved':
      return const Color(0xFFB45309);
    case 'confirmed':
      return const Color(0xFF2563EB);
    case 'fully_paid':
      return const Color(0xFF15803D);
    case 'checked_in':
      return const Color(0xFF0F766E);
    case 'completed':
      return const Color(0xFF7C3AED);
    case 'no_show':
      return const Color(0xFF78716C);
    case 'cancelled':
      return const Color(0xFFDC2626);
    default:
      return const Color(0xFF64748B);
  }
}

String methodLabel(String? method) {
  switch (method) {
    case 'gcash':
      return 'GCash';
    case 'maya':
      return 'Maya';
    case 'cash':
      return 'Cash';
    default:
      return (method == null || method == 'other') ? tr('methodOther') : capitalize(method);
  }
}

Color methodColor(String? method) {
  switch (method) {
    case 'gcash':
      return const Color(0xFF2F6FED);
    case 'maya':
      return const Color(0xFF1FA67A);
    case 'cash':
      return const Color(0xFFB7791F);
    default:
      return const Color(0xFF7A7F87);
  }
}

String kindLabel(String? kind) {
  switch (kind) {
    case 'downpayment':
      return tr('kindDownpayment');
    case 'balance':
      return tr('kindBalance');
    case 'refund':
      return tr('kindRefund');
    default:
      return capitalize((kind ?? '').replaceAll('_', ' '));
  }
}

// ---------------------------------------------------------------------------
// Verification status ng client
// ---------------------------------------------------------------------------

String verificationLabel(String? status) {
  switch (status) {
    case 'verified':
      return tr('statVerified');
    case 'pending':
      return tr('statPending');
    case 'rejected':
      return tr('statRejected');
    default:
      return tr('statUnverified');
  }
}

Color verificationColor(String? status) {
  switch (status) {
    case 'verified':
      return const Color(0xFF2E9E5B);
    case 'pending':
      return const Color(0xFFE08A00);
    case 'rejected':
      return const Color(0xFFD64545);
    default:
      return const Color(0xFF7A7F87);
  }
}
