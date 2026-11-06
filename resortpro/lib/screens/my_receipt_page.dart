import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/offline_cache.dart';
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
          .select('*, packages(name, price)')
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

    final packageName = _booking!['packages']?['name'] ?? 'Unknown Package';

    return Scaffold(
      appBar: AppBar(title: const Text('E-Receipt')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_offlineSavedAt != null)
              OfflineNotice(savedAt: _offlineSavedAt!, margin: const EdgeInsets.only(bottom: 16)),
            Center(
              child: Column(
                children: [
                  const Icon(Icons.receipt_long, size: 48),
                  const SizedBox(height: 8),
                  Text(
                    packageName,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text('Booking #${widget.bookingId.substring(0, 8)}'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Divider(),

            _receiptRow('Date', formatDate(parseDate(_booking!['booking_date']))),
            _receiptRow('Guests', '${_booking!['total_pax']}'),
            if (_booking!['event_type'] != null)
              _receiptRow('Event Type', '${_booking!['event_type']}'),
            _receiptRow('Status', statusLabel(_booking!['status'] as String?)),

            const Divider(height: 32),

            const Text('PAYMENT DETAILS',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 12),

            if (_payments.isEmpty)
              const Text('No payments recorded yet.')
            else
              ..._payments.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p['kind'].toString().toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'via ${p['method']}'
                            '${p['reference_no'] != null ? ' · Ref ${p['reference_no']}' : ''}',
                          ),
                          Text(
                            paymentStatusLabel(p['status'] as String?) +
                                ('${p['reject_reason'] ?? ''}'.isEmpty ? '' : ' — ${p['reject_reason']}'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: paymentStatusColor(p['status'] as String?),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(_formatPeso((p['amount'] as num).toDouble())),
                  ],
                ),
              )),

            const Divider(height: 32),

            _receiptRow('Total Amount', _formatPeso(_totalAmount), bold: true),
            _receiptRow('Amount Paid (verified)', _formatPeso(_totalPaid), bold: true),
            if (_pendingPaid > 0)
              _receiptRow(
                'Waiting for verification',
                _formatPeso(_pendingPaid),
                color: const Color(0xFFE08A00),
              ),
            _receiptRow(
              'Remaining Balance',
              _formatPeso(_remainingBalance),
              bold: true,
              color: _remainingBalance > 0 ? Colors.red : Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _receiptRow(String label, String value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}