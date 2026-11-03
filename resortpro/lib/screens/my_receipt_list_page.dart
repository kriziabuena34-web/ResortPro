import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/format.dart';
import 'my_receipt_page.dart';

class MyReceiptListPage extends StatefulWidget {
  const MyReceiptListPage({super.key});

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

      setState(() {
        _receipts = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load receipts: $e';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Receipt')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(child: Text(_errorMessage!))
          : _receipts.isEmpty
          ? const Center(child: Text('No receipts yet.'))
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SearchField(
              controller: _search,
              hint: 'Search package or date',
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          FilterChipsRow(
            children: [
              for (final e in const {
                'all': 'All',
                'balance': 'With balance',
                'paid': 'Fully paid',
              }.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _filter == e.key,
                  onSelected: (_) => setState(() => _filter = e.key),
                ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
        onRefresh: _fetchReceipts,
        child: _filtered.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 80),
                  Center(child: Text('No receipts match your filter.')),
                ],
              )
            : ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _filtered.length,
          itemBuilder: (context, index) {
            final booking = _filtered[index];
            final packageName =
                booking['packages']?['name'] ?? 'Unknown Package';
            final totalAmount =
                (booking['total_amount'] as num?)?.toDouble() ?? 0.0;
            final paid = _totalPaid(booking);
            final remaining = totalAmount - paid;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const Icon(Icons.receipt_long),
                title: Text(
                  packageName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text('Date: ${formatDate(parseDate(booking['booking_date']))}'),
                    Text('Paid: ${_formatPeso(paid)}'),
                    Text(
                      remaining > 0
                          ? 'Balance: ${_formatPeso(remaining)}'
                          : 'Fully Paid',
                      style: TextStyle(
                        color: remaining > 0 ? Colors.red : Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          MyReceiptPage(bookingId: '${booking['id']}'),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
          ),
        ],
      ),
    );
  }
}