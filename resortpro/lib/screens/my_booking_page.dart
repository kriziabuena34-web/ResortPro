import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/cancel_booking.dart';
import '../services/checkin_qr.dart';
import '../services/claim_booking.dart';
import '../services/offline_cache.dart';
import '../services/payment_proof.dart';
import '../utils/format.dart';
import 'my_receipt_page.dart';

/// Listahan ng bookings ng client, may search, filter, at sort.
/// Ginagamit din bilang "Booking History" (initialFilter: 'past').
class MyBookingPage extends StatefulWidget {
  const MyBookingPage({super.key, this.embedded = false, this.initialFilter = 'all'});

  /// True kapag nasa loob ng bottom navigation (walang sariling app bar).
  final bool embedded;

  /// 'all', 'upcoming', 'past', o 'cancelled'
  final String initialFilter;

  @override
  State<MyBookingPage> createState() => _MyBookingPageState();
}

class _MyBookingPageState extends State<MyBookingPage> {
  final supabase = Supabase.instance.client;
  final _search = TextEditingController();
  List<Map<String, dynamic>> _bookings = [];
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  String? _errorMessage;
  DateTime? _offlineSavedAt;
  String _query = '';
  late String _filter = widget.initialFilter;
  bool _newestFirst = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _errorMessage = 'Not signed in.';
          _isLoading = false;
        });
        return;
      }

      final profile = await supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      final bookings = await supabase
          .from('bookings')
          .select('*, packages(name, start_time, end_time), payments(*)')
          .eq('client_id', userId)
          .order('booking_date', ascending: false);

      // Refund ng bawat na-cancel na booking (kung mayroon).
      final list = List<Map<String, dynamic>>.from(bookings);
      try {
        final refunds = await supabase.from('refund_requests').select().eq('client_id', userId);
        for (final r in refunds) {
          for (final b in list) {
            if ('${b['id']}' == '${r['booking_id']}') b['_refund'] = r;
          }
        }
      } catch (_) {}

      OfflineCache.save('my_bookings', {'profile': profile, 'bookings': list});
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _bookings = list;
        _offlineSavedAt = null;
        _isLoading = false;
      });
    } catch (e) {
      final cached = isOfflineError(e) ? await OfflineCache.load('my_bookings') : null;
      if (!mounted) return;
      setState(() {
        if (cached != null) {
          final d = Map<String, dynamic>.from(cached.data as Map);
          _profile = Map<String, dynamic>.from(d['profile'] as Map);
          _bookings = [for (final b in d['bookings'] as List) Map<String, dynamic>.from(b as Map)];
          _offlineSavedAt = cached.savedAt;
        } else {
          _errorMessage = friendlyError(e, action: 'load your bookings');
        }
        _isLoading = false;
      });
    }
  }

  String _formatTime(String? time) {
    if (time == null) return 'TBD';
    final parts = time.split(':');
    int hour = int.parse(parts[0]);
    final minute = parts[1];
    final period = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;
    return '$hour:$minute $period';
  }

  String _formatScheduleTime(Map<String, dynamic>? pkg) {
    if (pkg == null) return '';
    final start = pkg['start_time'] as String?;
    final end = pkg['end_time'] as String?;
    if (start == null || end == null) return 'Contact us for schedule';
    return '${_formatTime(start)} - ${_formatTime(end)}';
  }

  DateTime? _dateOf(Map<String, dynamic> b) {
    final d = parseDate(b['booking_date']);
    return d == null ? null : DateUtils.dateOnly(d);
  }

  bool _isUpcoming(Map<String, dynamic> b) {
    final d = _dateOf(b);
    final today = DateUtils.dateOnly(DateTime.now());
    return d != null &&
        !d.isBefore(today) &&
        !isInactiveStatus(b['status'] as String?) &&
        b['status'] != 'completed';
  }

  double _paid(Map<String, dynamic> b) => verifiedPaid(b['payments'] as List?);

  Future<void> _payBalance(Map<String, dynamic> booking, double amount, {required String kind}) async {
    final sent = await showPayBalanceSheet(
      context,
      bookingId: '${booking['id']}',
      balance: amount,
      kind: kind,
    );
    if (!sent || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Payment proof sent! The resort will verify it soon.')),
    );
    await _fetchData();
  }

  bool _passesFilter(Map<String, dynamic> b, String filter) {
    final status = b['status'] as String?;
    switch (filter) {
      case 'upcoming':
        return _isUpcoming(b);
      case 'past':
        return !_isUpcoming(b) && !isInactiveStatus(status);
      case 'cancelled':
        return isInactiveStatus(status);
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    final list = _bookings.where((b) {
      final status = b['status'] as String?;
      if (!_passesFilter(b, _filter)) return false;
      if (q.isEmpty) return true;
      final pkg = b['packages'] as Map<String, dynamic>?;
      return '${pkg?['name'] ?? ''}'.toLowerCase().contains(q) ||
          '${b['event_type'] ?? ''}'.toLowerCase().contains(q) ||
          statusLabel(status).toLowerCase().contains(q) ||
          '${b['booking_date']}'.contains(q);
    }).toList();

    list.sort((a, b) {
      final da = _dateOf(a), db = _dateOf(b);
      if (da == null || db == null) return 0;
      return _newestFirst ? db.compareTo(da) : da.compareTo(db);
    });
    return list;
  }

  Future<void> _claimWalkIn() async {
    final linked = await showClaimBookingDialog(context);
    if (!linked || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Booking added to your account. You can now see it here and in My Receipt.')),
    );
    setState(() => _filter = 'all');
    await _fetchData();
  }

  Widget _refundInfo(Map<String, dynamic> r) {
    final status = '${r['status']}';
    final amount = peso(asDouble(r['amount']));
    final (Color color, String text) = switch (status) {
      'refunded' => (
          Colors.green.shade700,
          'Refund of $amount sent${'${r['refund_reference'] ?? ''}'.isEmpty ? '' : ' · Ref ${r['refund_reference']}'}',
        ),
      'rejected' => (
          Colors.red.shade700,
          'Refund not approved${'${r['admin_note'] ?? ''}'.isEmpty ? '' : ': ${r['admin_note']}'}',
        ),
      _ => (Colors.orange.shade800, 'Refund request of $amount is being reviewed by the resort.'),
    };
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(Icons.currency_exchange, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  int _count(String filter) => _bookings.where((b) => _passesFilter(b, filter)).length;

  @override
  Widget build(BuildContext context) {
    final body = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _errorMessage != null
            ? OfflineEmpty(message: _errorMessage!, onRetry: _fetchData)
            : _buildList();

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialFilter == 'past' ? 'Booking History' : 'My Booking'),
      ),
      body: body,
    );
  }

  Widget _buildList() {
    final filtered = _filtered;
    final filters = {
      'all': 'All',
      'upcoming': 'Upcoming',
      'past': 'Past',
      'cancelled': 'Cancelled',
    };

    return Column(
      children: [
        if (_offlineSavedAt != null) OfflineNotice(savedAt: _offlineSavedAt!, onRetry: _fetchData),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SearchField(
            controller: _search,
            hint: 'Search package, event, or status',
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        FilterChipsRow(
          children: [
            for (final e in filters.entries)
              ChoiceChip(
                label: Text('${e.value} (${_count(e.key)})'),
                selected: _filter == e.key,
                onSelected: (_) => setState(() => _filter = e.key),
              ),
            ActionChip(
              avatar: Icon(_newestFirst ? Icons.arrow_downward : Icons.arrow_upward, size: 18),
              label: Text(_newestFirst ? 'Newest first' : 'Oldest first'),
              onPressed: () => setState(() => _newestFirst = !_newestFirst),
            ),
          ],
        ),
        // Booking na ginawa sa resort (walk-in o tawag): i-link gamit ang code sa resibo.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _claimWalkIn,
              icon: const Icon(Icons.confirmation_number_outlined, size: 18),
              label: const Text('Booked at the resort? Add it with your receipt code'),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchData,
            child: filtered.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 80),
                      const Icon(Icons.event_busy, size: 56, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(
                        _bookings.isEmpty
                            ? 'You have no bookings yet.'
                            : 'No bookings match your filter.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) => _buildCard(filtered[index]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(Map<String, dynamic> booking) {
    final pkg = booking['packages'] as Map<String, dynamic>?;
    final packageName = pkg?['name'] ?? 'Unknown Package';
    final status = booking['status'] as String?;
    final total = asDouble(booking['total_amount']);
    final paid = _paid(booking);
    final payments = ((booking['payments'] as List?) ?? []).whereType<Map>().toList();
    final pending = pendingPaid(payments);
    final balance = (total - paid).clamp(0, double.infinity).toDouble();
    final unpaid = (balance - pending).clamp(0, double.infinity).toDouble();
    final hasVerifiedDown = payments.any((p) => p['kind'] == 'downpayment' && isVerifiedPayment(p));
    final rejected = payments.where((p) => p['status'] == 'rejected').toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: statusColor(status), width: 4)),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Text(
            packageName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusChip(status: status),
                const SizedBox(height: 6),
                Text('${formatDate(_dateOf(booking))} · ${_formatScheduleTime(pkg)}'),
                if (pending > 0)
                  Text(
                    '${peso(pending)} waiting for verification',
                    style: const TextStyle(color: Color(0xFFE08A00), fontWeight: FontWeight.w600),
                  ),
                if (rejected.isNotEmpty && unpaid > 0 && !isInactiveStatus(status))
                  const Text(
                    'A payment was rejected. Please send a new proof.',
                    style: TextStyle(color: Color(0xFFD64545), fontWeight: FontWeight.w600),
                  )
                else if (unpaid > 0 && !isInactiveStatus(status))
                  Text(
                    'Balance: ${peso(unpaid)}',
                    style: const TextStyle(color: Color(0xFFD64545), fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
          children: [
            const Divider(),
            Text('Booker: ${_profile?['full_name'] ?? _profile?['google_display_name'] ?? 'Not set'}'),
            Text('Phone: ${_profile?['phone'] ?? 'Not set'}'),
            Text(
              'Booked on: ${formatDateTime(parseDate(booking['created_at']))}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (booking['event_type'] != null) ...[
              const SizedBox(height: 6),
              Text('Type of Event: ${booking['event_type']}'),
            ],
            const SizedBox(height: 12),
            const Text('GUESTS', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Infant/Toddler (0-3): ${booking['infants']}'),
            Text('Child (4-12): ${booking['children']}'),
            Text('Teen (13-19): ${booking['teens']}'),
            Text('Adult (20-59): ${booking['adults']}'),
            Text('Elderly (60+): ${booking['elderly']}'),
            const SizedBox(height: 6),
            Text(
              'Total: ${booking['total_pax']} pax',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text('PAYMENTS', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            if (payments.isEmpty) const Text('No payments yet.'),
            for (final p in payments)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      p['status'] == 'pending'
                          ? Icons.hourglass_top
                          : p['status'] == 'rejected'
                              ? Icons.cancel
                              : Icons.check_circle,
                      size: 18,
                      color: paymentStatusColor(p['status'] as String?),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${peso(asDouble(p['amount']))} · ${'${p['kind'] ?? ''}'} · '
                        '${paymentStatusLabel(p['status'] as String?)}'
                        '${'${p['reject_reason'] ?? ''}'.isEmpty ? '' : '\nReason: ${p['reject_reason']}'}',
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text('Verified: ${peso(paid)} of ${peso(total)}'),
            const SizedBox(height: 8),
            if (unpaid > 0 && !isInactiveStatus(status) && status != 'completed')
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.icon(
                  onPressed: () => _payBalance(
                    booking,
                    hasVerifiedDown || pending > 0 ? unpaid : (total * 0.5).roundToDouble().clamp(0, unpaid).toDouble(),
                    kind: hasVerifiedDown || pending > 0 ? 'balance' : 'downpayment',
                  ),
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: Text(
                    hasVerifiedDown || pending > 0 ? 'Pay balance (${peso(unpaid)})' : 'Send downpayment proof',
                  ),
                ),
              ),
            // QR para sa check-in / check-out (gumagana kahit offline)
            if (canShowCheckinQr(booking))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.tonalIcon(
                  onPressed: () => showCheckinQr(context, booking),
                  icon: const Icon(Icons.qr_code_2, size: 18),
                  label: Text(booking['checked_in_at'] != null ? 'Show check-out QR' : 'Show check-in QR'),
                ),
              ),
            // Naka-out na: survey para matapos ang stay
            if (needsCheckoutSurvey(booking))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.icon(
                  onPressed: () async {
                    if (await showGuestSurvey(context, booking) && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Thank you! Your stay is now complete.')),
                      );
                      await _fetchData();
                    }
                  },
                  icon: const Icon(Icons.rate_review_outlined, size: 18),
                  label: const Text('Answer check-out survey'),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MyReceiptPage(bookingId: '${booking['id']}'),
                ),
              ),
              icon: const Icon(Icons.receipt_long, size: 18),
              label: const Text('View receipt'),
            ),
            // Refund (kapag na-cancel)
            if (booking['_refund'] is Map) _refundInfo(Map<String, dynamic>.from(booking['_refund'] as Map)),
            // Pag-cancel ayon sa refund policy
            if (canCancelBooking(booking) && _offlineSavedAt == null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                  onPressed: () async {
                    if (await showCancelBookingSheet(context, booking) && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Booking cancelled. If you asked for a refund, the resort will review your reason.')),
                      );
                      await _fetchData();
                    }
                  },
                  icon: const Icon(Icons.event_busy_outlined, size: 18),
                  label: const Text('Cancel booking'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
