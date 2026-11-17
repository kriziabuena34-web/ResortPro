import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/offline_cache.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'my_receipt_page.dart';

class MyReceiptListPage extends StatefulWidget {
  const MyReceiptListPage({super.key, this.embedded = false});

  /// True kapag tab sa ibaba (walang sariling AppBar).
  final bool embedded;

  @override
  State<MyReceiptListPage> createState() => _MyReceiptListPageState();
}

class _MyReceiptListPageState extends State<MyReceiptListPage> {
  final supabase = Supabase.instance.client;
  final _search = TextEditingController();
  String _query = '';
  String _filter = 'all'; // all, balance, paid
  List<Map<String, dynamic>> _receipts = [];
  bool _isLoading = true;
  String? _errorMessage;
  DateTime? _offlineSavedAt;

  @override
  void initState() {
    super.initState();
    _fetchReceipts();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  double _remaining(Map<String, dynamic> b) =>
      ((b['total_amount'] as num?)?.toDouble() ?? 0.0) - _totalPaid(b);

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    return _receipts.where((b) {
      final remaining = _remaining(b);
      if (_filter == 'balance' && remaining <= 0) return false;
      if (_filter == 'paid' && remaining > 0) return false;
      if (q.isEmpty) return true;
      return '${b['packages']?['name'] ?? ''}'.toLowerCase().contains(q) ||
          '${b['booking_date']}'.contains(q) ||
          formatDate(parseDate(b['booking_date'])).toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _fetchReceipts() async {
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

      // bookings + package name + all related payments
      final data = await supabase
          .from('bookings')
          .select('*, packages(name), payments(amount, status)')
          .eq('client_id', userId)
          .order('booking_date', ascending: false);

      OfflineCache.save('my_receipts', data);
      if (!mounted) return;
      setState(() {
        _receipts = List<Map<String, dynamic>>.from(data);
        _offlineSavedAt = null;
        _isLoading = false;
      });
    } catch (e) {
      final cached = isOfflineError(e) ? await OfflineCache.load('my_receipts') : null;
      if (!mounted) return;
      setState(() {
        if (cached != null) {
          _receipts = [for (final r in cached.data as List) Map<String, dynamic>.from(r as Map)];
          _offlineSavedAt = cached.savedAt;
        } else {
          _errorMessage = friendlyError(e, action: 'load your receipts');
        }
        _isLoading = false;
      });
    }
  }

  // Verified na bayad lang ang binibilang.
  double _totalPaid(Map<String, dynamic> booking) => verifiedPaid(booking['payments'] as List?);

  String _formatPeso(double amount) {
    return '₱${amount.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
    )}';
  }

  Widget _pill(String label, bool selected, VoidCallback onTap, int count) {
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
              Text(label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? Colors.white : AppColors.text,
                  )),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(String title, String message) => Container(
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
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.10), shape: BoxShape.circle),
              child: const Icon(Icons.receipt_long_outlined, size: 30, color: AppColors.primary),
            ),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          ],
        ),
      );

  Widget _receiptCard(Map<String, dynamic> booking) {
    final packageName = booking['packages']?['name'] ?? 'Unknown Package';
    final totalAmount = (booking['total_amount'] as num?)?.toDouble() ?? 0.0;
    final paid = _totalPaid(booking);
    final remaining = (totalAmount - paid).clamp(0, double.infinity).toDouble();
    final fullyPaid = remaining <= 0;
    final date = parseDate(booking['booking_date']);
    final ref = '#${'${booking['id']}'.split('-').first.toUpperCase()}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => MyReceiptPage(bookingId: '${booking['id']}')),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: (fullyPaid ? AppColors.success : AppColors.primary).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    fullyPaid ? Icons.task_alt_rounded : Icons.receipt_long_rounded,
                    color: fullyPaid ? AppColors.success : AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$packageName',
                          style: const TextStyle(
                              fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink)),
                      const SizedBox(height: 2),
                      Text('${formatDate(date)}  ·  $ref',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text('Paid ${_formatPeso(paid)}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: (fullyPaid ? AppColors.success : AppColors.danger).withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              fullyPaid ? 'Fully Paid' : 'Balance ${_formatPeso(remaining)}',
                              style: TextStyle(
                                color: fullyPaid ? AppColors.success : AppColors.danger,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    int count(String f) => _receipts.where((b) {
          final r = _remaining(b);
          if (f == 'balance') return r > 0;
          if (f == 'paid') return r <= 0;
          return true;
        }).length;

    final Widget body;
    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_errorMessage != null) {
      body = OfflineEmpty(message: _errorMessage!, onRetry: _fetchReceipts);
    } else {
      body = Column(
        children: [
          if (_offlineSavedAt != null) OfflineNotice(savedAt: _offlineSavedAt!, onRetry: _fetchReceipts),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: SearchField(
              controller: _search,
              hint: 'Search package or date',
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final e in const {'all': 'All', 'balance': 'With Balance', 'paid': 'Fully Paid'}.entries) ...[
                  _pill(e.value, _filter == e.key, () => setState(() => _filter = e.key), count(e.key)),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchReceipts,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  if (_receipts.isEmpty)
                    _empty('No Receipts Yet', 'Your e-receipts will show up here after you book.')
                  else if (filtered.isEmpty)
                    _empty('Nothing Here', 'No receipts match your filter.')
                  else
                    for (final b in filtered) _receiptCard(b),
                ],
              ),
            ),
          ),
        ],
      );
    }
    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text('My Receipts')), body: body);
  }
}
