import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../services/booking_workflow.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/list_controls.dart';

/// Payments: (1) pag-verify ng proof of payment ng clients,
/// (2) listahan ng lahat ng bayad na may search, filter, at sort.
class PaymentsPage extends StatefulWidget {
  const PaymentsPage({
    super.key,
    required this.data,
    required this.onChanged,
    this.showPendingFirst = false,
  });

  final AdminData data;
  final Future<void> Function() onChanged;
  final bool showPendingFirst;

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentEntry {
  _PaymentEntry(this.payment, this.booking);
  final Map<String, dynamic> payment;
  final Map<String, dynamic> booking;

  double get amount => asDouble(payment['amount']);
  String get method => '${payment['method'] ?? 'other'}';
  String get kind => '${payment['kind'] ?? ''}';
  String get status => '${payment['status'] ?? 'verified'}';
  DateTime? get date => parseDate(payment['created_at']) ?? bookingDateOf(booking);
}

enum _PaySort { newest, oldest, amountHigh, amountLow }

class _PaymentsPageState extends State<PaymentsPage> {
  final supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  late bool _pendingTab = widget.showPendingFirst || widget.data.pendingPayments.isNotEmpty;
  String _query = '';
  String _method = 'all';
  String _kind = 'all';
  String _status = 'verified';
  DateTimeRange? _range;
  _PaySort _sort = _PaySort.newest;
  final Map<String, Future<String?>> _proofUrls = {};
  final Set<String> _busy = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<String?> _proofUrl(String? path) {
    if (path == null || path.isEmpty) return Future.value(null);
    return _proofUrls.putIfAbsent(path, () async {
      try {
        return await supabase.storage.from('payment-proofs').createSignedUrl(path, 3600);
      } catch (_) {
        return null;
      }
    });
  }

  // -------------------------------------------------------------------------
  // Verify / reject
  // -------------------------------------------------------------------------

  Future<void> _verify(Map<String, dynamic> payment, Map<String, dynamic> booking) async {
    final id = '${payment['id']}';
    setState(() => _busy.add(id));
    try {
      final fullyPaid = await BookingWorkflow.verifyPayment(payment, booking);
      if (!mounted) return;
      showToast(context, fullyPaid ? tr('payVerifiedFull') : tr('payVerifiedToast'));
      await widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      showToast(context, tr('failed', {'e': e}));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _reject(Map<String, dynamic> payment, Map<String, dynamic> booking) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('payRejectQ')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('payRejectMsg', {
                'amount': peso(asDouble(payment['amount'])),
                'client': clientNameOf(booking),
              })),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final key in const ['payReasonNotFound', 'payReasonAmount', 'payReasonUnclear'])
                    ActionChip(
                      label: Text(tr(key)),
                      onPressed: () => controller.text = tr(key),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 2,
                decoration: InputDecoration(labelText: tr('reasonForClient')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('back'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(tr('reject')),
          ),
        ],
      ),
    );
    if (reason == null) return;

    final id = '${payment['id']}';
    setState(() => _busy.add(id));
    try {
      await BookingWorkflow.rejectPayment(payment, booking, reason);
      if (!mounted) return;
      showToast(context, tr('payRejectedToast'));
      await widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      showToast(context, tr('failed', {'e': e}));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final pendingCount = widget.data.pendingPayments.length;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pageGutter(context), pageGutter(context) - 4, pageGutter(context), 0),
          child: PillTabs<bool>(
            value: _pendingTab,
            onChanged: (v) => setState(() => _pendingTab = v),
            items: [
              (
                value: true,
                icon: Icons.fact_check_outlined,
                label: pendingCount > 0 ? '${tr('payPendingTab')}  ·  $pendingCount' : tr('payPendingTab'),
              ),
              (value: false, icon: Icons.receipt_long_outlined, label: tr('payAllTab')),
            ],
          ),
        ),
        Expanded(child: _pendingTab ? _buildPending() : _buildAll()),
      ],
    );
  }

  Widget _buildPending() {
    final pending = widget.data.pendingPayments;
    if (pending.isEmpty) {
      return EmptyState(icon: Icons.task_alt, message: tr('payNoPending'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100 ? 2 : 1;
        return RefreshIndicator(
          onRefresh: widget.onChanged,
          child: ListView(
            padding: pageInsets(context),
            children: [
              Text(
                tr('payPendingHint'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              CardGrid(
                columns: columns,
                children: [
                  for (final item in pending) _pendingCard(item.payment, item.booking),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pendingCard(Map<String, dynamic> payment, Map<String, dynamic> booking) {
    final theme = Theme.of(context);
    final busy = _busy.contains('${payment['id']}');
    final method = '${payment['method'] ?? ''}';
    final reference = '${payment['reference_no'] ?? ''}'.trim();

    return AppCard(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    peso(asDouble(payment['amount'])),
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                _statusPill('pending'),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${kindLabel(payment['kind'] as String?)} · ${methodLabel(method)}',
              style: theme.textTheme.bodyMedium?.copyWith(color: methodColor(method)),
            ),
            const SizedBox(height: 12),
            InfoRow(tr('fieldClient'), clientNameOf(booking)),
            InfoRow(tr('navPackages'), packageNameOf(booking)),
            InfoRow(tr('fieldDate'), formatDate(bookingDateOf(booking))),
            InfoRow(tr('payReference'), reference.isEmpty ? tr('notSet') : reference),
            InfoRow(tr('paySubmitted'), formatDateTime(parseDate(payment['created_at']))),
            InfoRow(
              tr('fieldBalance'),
              '${peso(remainingOf(booking))} (${tr('payBeforeThis')})',
            ),
            const SizedBox(height: 12),
            FutureBuilder<String?>(
              future: _proofUrl(payment['proof_path'] as String?),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
                }
                final url = snapshot.data;
                if (url == null) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(tr('payNoProof')),
                  );
                }
                return GestureDetector(
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(url))),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      url,
                      height: 220,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stack) => Text(tr('idLoadFail')),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            Text(tr('tapToZoom'), style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : () => _verify(payment, booking),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E9E5B)),
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(tr('payVerifyBtn')),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _reject(payment, booking),
                  style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                  icon: const Icon(Icons.close, size: 18),
                  label: Text(tr('reject')),
                ),
                if (busy)
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(String status) {
    final color = paymentStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        paymentStatusLabel(status),
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }

  Widget _buildAll() {
    final theme = Theme.of(context);

    final entries = <_PaymentEntry>[
      for (final b in widget.data.bookings)
        for (final p in paymentsOf(b)) _PaymentEntry(p, b),
    ];

    final methods = entries.map((e) => e.method).toSet().toList()..sort();
    final q = _query.trim().toLowerCase();
    final filtered = entries.where((e) {
      if (_status != 'all' && e.status != _status) return false;
      if (_method != 'all' && e.method != _method) return false;
      if (_kind != 'all' && e.kind != _kind) return false;
      if (!inRange(e.date, _range)) return false;
      if (q.isEmpty) return true;
      return clientNameOf(e.booking).toLowerCase().contains(q) ||
          packageNameOf(e.booking).toLowerCase().contains(q) ||
          '${e.payment['reference_no'] ?? ''}'.toLowerCase().contains(q) ||
          e.amount.toStringAsFixed(0).contains(q);
    }).toList();

    int byDate(_PaymentEntry a, _PaymentEntry b) {
      final da = a.date, db = b.date;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    }

    switch (_sort) {
      case _PaySort.newest:
        filtered.sort((a, b) => byDate(b, a));
      case _PaySort.oldest:
        filtered.sort(byDate);
      case _PaySort.amountHigh:
        filtered.sort((a, b) => b.amount.compareTo(a.amount));
      case _PaySort.amountLow:
        filtered.sort((a, b) => a.amount.compareTo(b.amount));
    }

    final verified = filtered.where((e) => e.status == 'verified').toList();
    final total = verified.fold<double>(0, (s, e) => s + e.amount);
    final down = verified.where((e) => e.kind == 'downpayment').fold<double>(0, (s, e) => s + e.amount);
    final balance = verified.where((e) => e.kind == 'balance').fold<double>(0, (s, e) => s + e.amount);

    return LayoutBuilder(
      builder: (context, constraints) {

        return ListView(
          padding: pageInsets(context),
          children: [
            StatGrid(
              children: [
                StatCard(
                  icon: Icons.payments,
                  label: tr('totalReceived'),
                  value: peso(total),
                  caption: tr('transactions', {'n': verified.length}),
                  color: AppColors.success,
                ),
                StatCard(
                  icon: Icons.bookmark_added_outlined,
                  label: tr('downpayments'),
                  value: peso(down),
                  color: theme.colorScheme.primary,
                ),
                StatCard(
                  icon: Icons.price_check,
                  label: tr('balancePayments'),
                  value: peso(balance),
                  color: AppColors.info,
                ),
              ],
            ),
            const SizedBox(height: 16),
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                    SearchBox(
                      controller: _searchController,
                      hint: tr('searchPaymentsHint'),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SortMenu<_PaySort>(
                          value: _sort,
                          options: {
                            _PaySort.newest: tr('sortDateNewest'),
                            _PaySort.oldest: tr('sortDateOldest'),
                            _PaySort.amountHigh: tr('sortAmountHigh'),
                            _PaySort.amountLow: tr('sortAmountLow'),
                          },
                          onChanged: (v) => setState(() => _sort = v),
                        ),
                        DateRangeChip(range: _range, onChanged: (r) => setState(() => _range = r)),
                        for (final s in const ['verified', 'pending', 'rejected', 'all'])
                          ChoiceChip(
                            label: Text(s == 'all' ? tr('filterAll') : paymentStatusLabel(s)),
                            selected: _status == s,
                            onSelected: (_) => setState(() => _status = s),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final k in const ['all', 'downpayment', 'balance'])
                          ChoiceChip(
                            label: Text(k == 'all' ? tr('allTypes') : kindLabel(k)),
                            selected: _kind == k,
                            onSelected: (_) => setState(() => _kind = k),
                          ),
                        ChoiceChip(
                          label: Text(tr('allMethods')),
                          selected: _method == 'all',
                          onSelected: (_) => setState(() => _method = 'all'),
                        ),
                        for (final m in methods)
                          ChoiceChip(
                            label: Text(methodLabel(m)),
                            selected: _method == m,
                            onSelected: (_) => setState(() => _method = m),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (filtered.isEmpty)
              EmptyState(icon: Icons.receipt_long, message: tr('noPaymentYet'))
            else
              AppCard(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < filtered.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _buildRow(filtered[i]),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildRow(_PaymentEntry e) {
    final color = methodColor(e.method);
    final reference = '${e.payment['reference_no'] ?? ''}'.trim();
    final reason = '${e.payment['reject_reason'] ?? ''}'.trim();
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(e.method == 'cash' ? Icons.money : Icons.phone_android, color: color),
      ),
      title: Text(
        '${packageNameOf(e.booking)} · ${clientNameOf(e.booking)}',
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${kindLabel(e.kind)} · ${methodLabel(e.method)} · ${formatDate(e.date)}'
        '${reference.isEmpty ? '' : ' · Ref $reference'}'
        '${e.status == 'rejected' && reason.isNotEmpty ? '\n${tr('payRejectedReason', {'reason': reason})}' : ''}',
      ),
      isThreeLine: e.status == 'rejected' && reason.isNotEmpty,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            peso(e.amount),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              decoration: e.status == 'rejected' ? TextDecoration.lineThrough : null,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            paymentStatusLabel(e.status),
            style: TextStyle(color: paymentStatusColor(e.status), fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
