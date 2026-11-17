import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/offline_cache.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

class MyReceiptPage extends StatefulWidget {
  final String bookingId;

  const MyReceiptPage({super.key, required this.bookingId});

  @override
  State<MyReceiptPage> createState() => _MyReceiptPageState();
}

class _MyReceiptPageState extends State<MyReceiptPage> {
  final supabase = Supabase.instance.client;
  Map<String, dynamic>? _booking;
  List<Map<String, dynamic>> _payments = [];
  bool _isLoading = true;
  String? _errorMessage;
  DateTime? _offlineSavedAt;

  @override
  void initState() {
    super.initState();
    _fetchReceipt();
  }

  Future<void> _fetchReceipt() async {
    try {
      final booking = await supabase
          .from('bookings')
          .select('*, packages(name, price, start_time, end_time)')
          .eq('id', widget.bookingId)
          .single();

      final payments = await supabase
          .from('payments')
          .select()
          .eq('booking_id', widget.bookingId)
          .order('created_at', ascending: true);

      // Naka-save para maipakita ang e-receipt sa resort kahit walang signal.
      OfflineCache.save('receipt_${widget.bookingId}', {'booking': booking, 'payments': payments});
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _payments = List<Map<String, dynamic>>.from(payments);
        _offlineSavedAt = null;
        _errorMessage = null;
        _isLoading = false;
      });
    } catch (e) {
      final cached = isOfflineError(e) ? await OfflineCache.load('receipt_${widget.bookingId}') : null;
      if (!mounted) return;
      setState(() {
        if (cached != null) {
          final d = Map<String, dynamic>.from(cached.data as Map);
          _booking = Map<String, dynamic>.from(d['booking'] as Map);
          _payments = [for (final p in d['payments'] as List) Map<String, dynamic>.from(p as Map)];
          _offlineSavedAt = cached.savedAt;
        } else {
          _errorMessage = friendlyError(e, action: 'load your receipt');
        }
        _isLoading = false;
      });
    }
  }

  // Verified na bayad lang ang binibilang sa "Amount Paid".
  double get _totalPaid => verifiedPaid(_payments);

  double get _pendingPaid => pendingPaid(_payments);

  double get _totalAmount {
    return (_booking?['total_amount'] as num?)?.toDouble() ?? 0.0;
  }

  double get _remainingBalance => _totalAmount - _totalPaid;

  String _formatPeso(double amount) {
    return '₱${amount.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
    )}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage != null || _booking == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Receipt')),
        body: _errorMessage != null
            ? OfflineEmpty(
                message: _errorMessage!,
                onRetry: () {
                  setState(() {
                    _isLoading = true;
                    _errorMessage = null;
                  });
                  _fetchReceipt();
                },
              )
            : const Center(child: Text('Booking not found.')),
      );
    }

    final b = _booking!;
    final pkg = b['packages'] as Map<String, dynamic>?;
    final packageName = pkg?['name'] ?? 'Unknown Package';
    final status = b['status'] as String?;
    final ref = '#${widget.bookingId.split('-').first.toUpperCase()}';
    final balance = _remainingBalance.clamp(0, double.infinity).toDouble();
    final guests = [
      ('Infant/Toddler', b['infants']),
      ('Child', b['children']),
      ('Teen', b['teens']),
      ('Adult', b['adults']),
      ('Elderly', b['elderly']),
    ].where((g) => asDouble(g.$2) > 0).map((g) => '${asDouble(g.$2).toStringAsFixed(0)} ${g.$1}').join(', ');

    return Scaffold(
      appBar: AppBar(title: const Text('E-Receipt')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_offlineSavedAt != null)
              OfflineNotice(savedAt: _offlineSavedAt!, margin: const EdgeInsets.only(bottom: 16)),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 8))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---- Header ----
                  Container(
                    color: AppColors.ink,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                    child: Row(
                      children: [
                        Image.asset('assets/images/aryana_logo.png', width: 48, height: 48),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Aryana's Guests House",
                                  style: TextStyle(
                                      fontFamily: 'Poppins', color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15.5)),
                              Text('Official E-Receipt', style: TextStyle(color: AppColors.inkText, fontSize: 12.5)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('REF NO.',
                                style: TextStyle(
                                    color: AppColors.inkText, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                            Text(ref,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ---- Package at status ----
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text('$packageName',
                              style: const TextStyle(
                                  fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
                        ),
                        const SizedBox(width: 8),
                        StatusChip(status: status),
                      ],
                    ),
                  ),
                  if (status == 'no_show')
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: _note(Icons.person_off_outlined,
                          'No check-in on the booking date. Payments are non-refundable.', AppColors.danger),
                    ),

                  // ---- Booking details ----
                  _sectionTitle('Booking Details'),
                  _row('Stay Date', formatDate(parseDate(b['booking_date']))),
                  if (pkg?['start_time'] != null && pkg?['end_time'] != null)
                    _row('Time', '${_time(pkg!['start_time'])} – ${_time(pkg['end_time'])}'),
                  _row('Guests', '${b['total_pax']} pax'),
                  if (guests.isNotEmpty) _row('Breakdown', guests, small: true),
                  if (b['event_type'] != null) _row('Event Type', '${b['event_type']}'),
                  _row('Booked On', formatDateTime(parseDate(b['created_at']))),

                  const _DashedDivider(),

                  // ---- Payments ----
                  _sectionTitle('Payments'),
                  if (_payments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Text('No payments recorded yet.', style: TextStyle(color: AppColors.muted)),
                    )
                  else
                    for (final p in _payments) _paymentRow(p),

                  const _DashedDivider(),

                  // ---- Totals ----
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Column(
                      children: [
                        _totalRow('Total Amount', _formatPeso(_totalAmount)),
                        _totalRow('Amount Paid (Verified)', _formatPeso(_totalPaid), color: AppColors.success),
                        if (_pendingPaid > 0)
                          _totalRow('Waiting for Verification', _formatPeso(_pendingPaid), color: const Color(0xFFB45309)),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: (balance > 0 ? AppColors.danger : AppColors.success).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: (balance > 0 ? AppColors.danger : AppColors.success).withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        Icon(balance > 0 ? Icons.account_balance_wallet_outlined : Icons.task_alt_rounded,
                            color: balance > 0 ? AppColors.danger : AppColors.success),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(balance > 0 ? 'Remaining Balance' : 'Fully Paid',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                        ),
                        Text(
                          _formatPeso(balance),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            color: balance > 0 ? AppColors.danger : AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ---- Footer ----
                  Container(
                    color: AppColors.subtle,
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                    child: Column(
                      children: [
                        const Text('Thank you for choosing Aryana\'s Guests House!',
                            textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        const SizedBox(height: 2),
                        Text('Show this e-receipt at the resort if asked · Issued ${formatDate(DateTime.now())}',
                            textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _time(dynamic t) {
    final parts = '$t'.split(':');
    if (parts.length < 2) return '$t';
    var h = int.tryParse(parts[0]) ?? 0;
    final period = h >= 12 ? 'PM' : 'AM';
    h = h % 12;
    if (h == 0) h = 12;
    return '$h:${parts[1]} $period';
  }

  static String _titleWord(String s) =>
      s.isEmpty ? s : s.split('_').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

  static String _method(String m) => switch (m) {
        'gcash' => 'GCash',
        'maya' => 'Maya',
        'cash' => 'Cash',
        _ => _titleWord(m),
      };

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Text(t.toUpperCase(),
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.muted)),
      );

  Widget _row(String label, String value, {bool small = false}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 100, child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13.5))),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: small ? 12.5 : 13.5),
              ),
            ),
          ],
        ),
      );

  Widget _totalRow(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13.5))),
            Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: color ?? AppColors.text)),
          ],
        ),
      );

  Widget _note(IconData icon, String text, Color color) => Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12.5))),
          ],
        ),
      );

  Widget _paymentRow(Map<String, dynamic> p) {
    final status = p['status'] as String?;
    final color = paymentStatusColor(status);
    final ref = '${p['reference_no'] ?? ''}'.trim();
    final reason = '${p['reject_reason'] ?? ''}'.trim();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.subtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            status == 'pending'
                ? Icons.hourglass_top_rounded
                : status == 'rejected'
                    ? Icons.cancel_rounded
                    : Icons.check_circle_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_titleWord('${p['kind'] ?? 'payment'}')} · ${_method('${p['method'] ?? ''}')}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text(
                  [
                    formatDate(parseDate(p['created_at'])),
                    if (ref.isNotEmpty) 'Ref $ref',
                  ].join('  ·  '),
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(paymentStatusLabel(status),
                    style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
                if (reason.isNotEmpty)
                  Text('Reason: $reason', style: const TextStyle(color: AppColors.danger, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatPeso((p['amount'] as num).toDouble()),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              decoration: status == 'rejected' ? TextDecoration.lineThrough : null,
              color: status == 'rejected' ? AppColors.muted : AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// Putol-putol na guhit, parang resibo.
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: LayoutBuilder(
        builder: (context, c) {
          final n = (c.maxWidth / 10).floor();
          return Row(
            children: [
              for (var i = 0; i < n; i++)
                Expanded(
                  child: Container(
                    height: 1.2,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    color: AppColors.border,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
