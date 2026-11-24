import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/cancel_booking.dart';
import '../services/checkin_qr.dart';
import '../services/claim_booking.dart';
import '../services/offline_cache.dart';
import '../services/payment_proof.dart';
import '../theme/app_theme.dart';
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

  Widget _noShowInfo() => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade100),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.person_off_outlined, color: Colors.red.shade700, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'You did not check in on your booking date, so this booking was marked as no-show. '
                'Payments are non-refundable. Please contact the resort if you have a valid reason.',
                style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.w600, height: 1.35),
              ),
            ),
          ],
        ),
      );

  Widget _refundInfo(Map<String, dynamic> r) {
    final status = '${r['status']}';
    final amount = peso(asDouble(r['amount']));
    // Resort ang nag-cancel: hinihintay ang account ng guest.
    if (refundNeedsAccount(r)) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.currency_exchange_rounded, size: 18, color: AppColors.primaryDark),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'The resort cancelled this booking. Tell us where to send your $amount refund.',
                    style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w600, height: 1.35),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _offlineSavedAt != null
                  ? null
                  : () async {
                      if (await showClaimRefundSheet(context, r) && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Thank you! The resort will send your refund to that account.')),
                        );
                        await _fetchData();
                      }
                    },
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
              label: const Text('Claim your refund'),
            ),
          ],
        ),
      );
    }
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

  Widget _pill(String label, bool selected, VoidCallback onTap, {IconData? icon, int? count}) {
    return Material(
      color: selected ? AppColors.ink : Colors.white,
      shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.ink : AppColors.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: selected ? Colors.white : AppColors.muted),
                const SizedBox(width: 6),
              ],
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
              ] else
                const SizedBox(width: 4),
            ],
          ),
        ),
      ),
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
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: SearchField(
            controller: _search,
            hint: 'Search package, event, or status',
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final e in filters.entries) ...[
                _pill(e.value, _filter == e.key, () => setState(() => _filter = e.key), count: _count(e.key)),
                const SizedBox(width: 8),
              ],
              _pill(
                _newestFirst ? 'Newest First' : 'Oldest First',
                false,
                () => setState(() => _newestFirst = !_newestFirst),
                icon: _newestFirst ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchData,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                // Booking na ginawa sa resort (walk-in o tawag): i-link gamit ang code sa resibo.
                Material(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: AppColors.primary.withValues(alpha: 0.25)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _claimWalkIn,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.confirmation_number_outlined, color: Colors.white, size: 21),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Booked at the Resort?', style: TextStyle(fontWeight: FontWeight.w800)),
                                SizedBox(height: 2),
                                Text(
                                  'Add it using the code on your receipt',
                                  style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_rounded, size: 16, color: Colors.white),
                                SizedBox(width: 2),
                                Text('Add',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (filtered.isEmpty)
                  Container(
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
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.10),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.event_note_outlined, size: 30, color: AppColors.primary),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _bookings.isEmpty ? 'No Bookings Yet' : 'Nothing Here',
                          style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _bookings.isEmpty
                              ? 'Your bookings will show up here once you book a package.'
                              : 'No bookings match your filter.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  )
                else
                  for (final b in filtered) _buildCard(b),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static const _caps = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.muted);

  Widget _section(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title.toUpperCase(), style: _caps),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );

  Widget _boxed(List<Widget> rows) => Container(
        decoration: BoxDecoration(
          color: AppColors.subtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppColors.border),
              rows[i],
            ],
          ],
        ),
      );

  Widget _infoRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: AppColors.muted),
            const SizedBox(width: 8),
            SizedBox(width: 92, child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          ],
        ),
      );

  Widget _alert(IconData icon, String text, Color color) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5))),
          ],
        ),
      );

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
    final inactive = isInactiveStatus(status);
    final date = _dateOf(booking);
    final today = DateUtils.dateOnly(DateTime.now());
    final isToday = date != null && date == today;
    final progress = total <= 0 ? 0.0 : (paid / total).clamp(0.0, 1.0);
    final color = statusColor(status);

    final guests = [
      ('Infant/Toddler (0-3)', booking['infants']),
      ('Child (4-12)', booking['children']),
      ('Teen (13-19)', booking['teens']),
      ('Adult (20-59)', booking['adults']),
      ('Elderly (60+)', booking['elderly']),
    ].where((g) => asDouble(g.$2) > 0).toList();

    final fullWidth = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(46)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isToday ? AppColors.primary : AppColors.border, width: isToday ? 1.5 : 1),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: inactive ? 0.75 : 1,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            shape: const Border(),
            collapsedShape: const Border(),
            leading: Container(
              width: 50,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: isToday ? AppColors.primary : color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    date == null ? '' : formatDate(date).split(' ').first.toUpperCase(),
                    style: TextStyle(
                        fontSize: 10.5, fontWeight: FontWeight.w800, color: isToday ? Colors.white : color),
                  ),
                  Text(
                    date == null ? '?' : '${date.day}',
                    style: TextStyle(
                      fontSize: 19,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: isToday ? Colors.white : AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
            // Pangalan sa itaas, status sa ilalim: hindi na naiipit ang pangalan ng
            // package kapag mahaba ang status (hal. "Waiting for confirmation").
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$packageName',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15.5, color: AppColors.ink),
                ),
                const SizedBox(height: 4),
                StatusChip(status: status),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${isToday ? 'Today · ' : ''}${formatDate(date)} · ${_formatScheduleTime(pkg)}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 6,
                            backgroundColor: const Color(0xFFE6EBF0),
                            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${peso(paid)} / ${peso(total)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text),
                      ),
                    ],
                  ),
                  if (pending > 0)
                    _alert(Icons.hourglass_top_rounded, '${peso(pending)} waiting for verification',
                        const Color(0xFFB45309)),
                  if (rejected.isNotEmpty && unpaid > 0 && !inactive)
                    _alert(Icons.error_outline_rounded, 'A payment was rejected. Please send a new proof.',
                        AppColors.danger)
                  else if (unpaid > 0 && !inactive)
                    _alert(Icons.account_balance_wallet_outlined, 'Balance: ${peso(unpaid)}', AppColors.danger),
                ],
              ),
            ),
            children: [
              const Divider(height: 1, color: AppColors.border),
              _section(
                'Booking Details',
                _boxed([
                  _infoRow(Icons.person_outline, 'Booker',
                      '${_profile?['full_name'] ?? _profile?['google_display_name'] ?? 'Not set'}'),
                  _infoRow(Icons.phone_outlined, 'Phone', '${_profile?['phone'] ?? 'Not set'}'),
                  if (booking['event_type'] != null)
                    _infoRow(Icons.celebration_outlined, 'Event', '${booking['event_type']}'),
                  _infoRow(Icons.schedule_rounded, 'Booked on', formatDateTime(parseDate(booking['created_at']))),
                ]),
              ),
              _section(
                'Guests · ${booking['total_pax']} pax',
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final g in guests)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.subtle,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                                text: '${asDouble(g.$2).toStringAsFixed(0)}  ',
                                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
                            TextSpan(text: g.$1),
                          ]),
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                  ],
                ),
              ),
              _section(
                'Payments',
                payments.isEmpty
                    ? const Text('No payments yet.', style: TextStyle(color: AppColors.muted))
                    : _boxed([
                        for (final p in payments)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  p['status'] == 'pending'
                                      ? Icons.hourglass_top_rounded
                                      : p['status'] == 'rejected'
                                          ? Icons.cancel_rounded
                                          : Icons.check_circle_rounded,
                                  size: 18,
                                  color: paymentStatusColor(p['status'] as String?),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${'${p['kind'] ?? ''}'.isEmpty ? 'Payment' : '${p['kind']}'[0].toUpperCase() + '${p['kind']}'.substring(1)} · ${paymentStatusLabel(p['status'] as String?)}',
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                      ),
                                      if ('${p['reject_reason'] ?? ''}'.isNotEmpty)
                                        Text('Reason: ${p['reject_reason']}',
                                            style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                Text(peso(asDouble(p['amount'])), style: const TextStyle(fontWeight: FontWeight.w800)),
                              ],
                            ),
                          ),
                      ]),
              ),
              const SizedBox(height: 16),
              if (unpaid > 0 && !inactive && status != 'completed')
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton.icon(
                    style: fullWidth,
                    onPressed: () => _payBalance(
                      booking,
                      hasVerifiedDown || pending > 0 ? unpaid : (total * 0.5).roundToDouble().clamp(0, unpaid).toDouble(),
                      kind: hasVerifiedDown || pending > 0 ? 'balance' : 'downpayment',
                    ),
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: Text(
                      hasVerifiedDown || pending > 0 ? 'Pay Balance (${peso(unpaid)})' : 'Send Downpayment Proof',
                    ),
                  ),
                ),
              // QR para sa check-in / check-out (gumagana kahit offline)
              if (canShowCheckinQr(booking))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton.icon(
                    style: fullWidth.copyWith(backgroundColor: const WidgetStatePropertyAll(AppColors.ink)),
                    onPressed: () => showCheckinQr(context, booking),
                    icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                    label: Text(booking['checked_in_at'] != null ? 'Show Check-Out QR' : 'Show Check-In QR'),
                  ),
                ),
              // Naka-out na: survey para matapos ang stay
              if (needsCheckoutSurvey(booking))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton.icon(
                    style: fullWidth,
                    onPressed: () async {
                      if (await showGuestSurvey(context, booking) && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Thank you! Your stay is now complete.')),
                        );
                        await _fetchData();
                      }
                    },
                    icon: const Icon(Icons.rate_review_outlined, size: 18),
                    label: const Text('Answer Check-Out Survey'),
                  ),
                ),
              OutlinedButton.icon(
                style: fullWidth,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MyReceiptPage(bookingId: '${booking['id']}'),
                  ),
                ),
                icon: const Icon(Icons.receipt_long_rounded, size: 18),
                label: const Text('View Receipt'),
              ),
              // Hindi nakapag-check in sa araw ng booking
              if (status == 'no_show') _noShowInfo(),
              // Refund (kapag na-cancel)
              if (booking['_refund'] is Map) _refundInfo(Map<String, dynamic>.from(booking['_refund'] as Map)),
              // Pag-cancel ayon sa refund policy
              if (canCancelBooking(booking) && _offlineSavedAt == null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                    onPressed: () async {
                      if (await showCancelBookingSheet(context, booking) && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Booking cancelled. If you asked for a refund, the resort will review your reason.')),
                        );
                        await _fetchData();
                      }
                    },
                    icon: const Icon(Icons.event_busy_outlined, size: 18),
                    label: const Text('Cancel Booking'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
