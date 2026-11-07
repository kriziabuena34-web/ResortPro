import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../services/booking_workflow.dart';
import '../../services/reference_format.dart';
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
    this.initialTab,
    this.focusBookingId,
  });

  /// Kapag galing sa Bookings: ipakita lang ang mga bayad ng booking na ito.
  final String? focusBookingId;

  /// 'pending', 'refunds', o 'all' (galing sa notification).
  final String? initialTab;

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
  late String _tab = widget.initialTab ??
      (widget.showPendingFirst || widget.data.pendingPayments.isNotEmpty
          ? 'pending'
          : widget.data.pendingRefunds.isNotEmpty
              ? 'refunds'
              : 'pending');
  late String? _focusId = widget.focusBookingId;
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
    final refundCount = widget.data.pendingRefunds.length;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pageGutter(context), pageGutter(context) - 4, pageGutter(context), 0),
          child: PillTabs<String>(
            value: _tab,
            onChanged: (v) => setState(() => _tab = v),
            items: [
              (
                value: 'pending',
                icon: Icons.fact_check_outlined,
                label: pendingCount > 0 ? '${tr('payPendingTab')}  ·  $pendingCount' : tr('payPendingTab'),
              ),
              (
                value: 'refunds',
                icon: Icons.currency_exchange,
                label: refundCount > 0 ? '${tr('payRefundsTab')}  ·  $refundCount' : tr('payRefundsTab'),
              ),
              (value: 'all', icon: Icons.receipt_long_outlined, label: tr('payAllTab')),
            ],
          ),
        ),
        Expanded(
          child: switch (_tab) {
            'refunds' => _buildRefunds(),
            'all' => _buildAll(),
            _ => _buildPending(),
          },
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Refunds (policy #6–#8: kalahati ng reservation fee kapag 5+ araw bago)
  // -------------------------------------------------------------------------

  Widget _buildRefunds() {
    final refunds = widget.data.refunds;
    if (refunds.isEmpty) {
      return EmptyState(icon: Icons.currency_exchange, message: tr('rfNone'));
    }
    final pending = refunds.where((r) => r['status'] == 'pending').toList();
    final done = refunds.where((r) => r['status'] != 'pending').toList();
    return RefreshIndicator(
      onRefresh: widget.onChanged,
      child: ListView(
        padding: pageInsets(context),
        children: [
          Text(tr('rfHint'), style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          for (final r in pending) _refundCard(r),
          if (done.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(tr('rfHistory'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final r in done) _refundCard(r),
          ],
        ],
      ),
    );
  }

  Widget _refundCard(Map<String, dynamic> r) {
    final booking = widget.data.bookingById(r['booking_id']);
    final status = '${r['status']}';
    final busy = _busy.contains('refund-${r['id']}');
    final method = '${r['payout_method'] ?? ''}';
    final color = switch (status) {
      'refunded' => AppColors.success,
      'rejected' => AppColors.danger,
      _ => AppColors.warning,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      booking == null ? tr('unknownClient') : clientNameOf(booking),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(tr('rfStatus_$status'),
                        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ],
              ),
              if (booking != null)
                Text('${packageNameOf(booking)} · ${formatDate(bookingDateOf(booking))}',
                    style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 10),
              Text(peso(asDouble(r['amount'])),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary)),
              Text(tr('rfBreakdown', {
                'days': asInt(r['days_before']),
                'paid': peso(asDouble(r['paid'])),
                'fee': peso(asDouble(r['reservation_fee'])),
              }), style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
              const Divider(height: 20),
              InfoRow(tr('rfSendTo'), '${methodLabel(method)} · ${r['payout_number'] ?? ''}'),
              InfoRow(tr('rfAccountName'), '${r['payout_name'] ?? ''}'),
              if ('${r['reason'] ?? ''}'.isNotEmpty) InfoRow(tr('rfReason'), '${r['reason']}'),
              if ('${r['refund_reference'] ?? ''}'.isNotEmpty) InfoRow(tr('rcReference'), '${r['refund_reference']}'),
              if ('${r['admin_note'] ?? ''}'.isNotEmpty) InfoRow(tr('adminNotes'), '${r['admin_note']}'),
              if (status == 'pending') ...[
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: busy ? null : () => _completeRefund(r),
                      icon: const Icon(Icons.send, size: 18),
                      label: Text(tr('rfApprove')),
                    ),
                    OutlinedButton(
                      onPressed: busy ? null : () => _rejectRefund(r),
                      child: Text(tr('rfRejectInvalid')),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runRefund(Map<String, dynamic> r, {String? reference, bool reject = false, String? note}) async {
    final key = 'refund-${r['id']}';
    setState(() => _busy.add(key));
    try {
      await supabase.rpc('complete_refund', params: {
        'p_request_id': r['id'],
        'p_reference': reference,
        'p_reject': reject,
        'p_note': note,
      });
      if (!mounted) return;
      showToast(context, reject ? tr('rfRejected') : tr('rfSent'));
      await widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      showToast(context, tr('failed', {'e': e}));
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _completeRefund(Map<String, dynamic> r) async {
    final method = '${r['payout_method'] ?? 'gcash'}';
    final f = RefFormat.of(method);
    final controller = TextEditingController();
    final ref = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(tr('rfMarkSent')),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('rfSendInstr', {
                  'amount': peso(asDouble(r['amount'])),
                  'method': methodLabel(method),
                  'number': '${r['payout_number'] ?? ''}',
                  'name': '${r['payout_name'] ?? ''}',
                })),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  inputFormatters: [f.formatter],
                  keyboardType: f.digitsOnly ? TextInputType.number : TextInputType.visiblePassword,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: tr('peReference', {'method': methodLabel(method)}),
                    hintText: 'e.g. ${f.example}',
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('cancel'))),
            FilledButton(
              onPressed: f.isComplete(controller.text) ? () => Navigator.pop(dialogContext, controller.text) : null,
              child: Text(tr('rfConfirmSent')),
            ),
          ],
        ),
      ),
    );
    if (ref == null) return;
    await _runRefund(r, reference: ref);
  }

  Future<void> _rejectRefund(Map<String, dynamic> r) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('rfRejectQ')),
        content: TextField(
          controller: controller,
          maxLines: 2,
          decoration: InputDecoration(labelText: tr('rfRejectReason')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: Text(tr('reject'))),
        ],
      ),
    );
    if (note == null) return;
    await _runRefund(r, reject: true, note: note);
  }

  Widget _buildPending() {
    final focus = _focusId == null ? null : widget.data.bookingById(_focusId);
    final pending = widget.data.pendingPayments
        .where((e) => _focusId == null || '${e.booking['id']}' == _focusId)
        .toList();
    final focusBar = focus == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  avatar: const Icon(Icons.person_outline, size: 18),
                  label: Text(tr('payFocusShowing', {'client': clientNameOf(focus)})),
                ),
                TextButton(onPressed: () => setState(() => _focusId = null), child: Text(tr('payFocusShowAll'))),
              ],
            ),
          );
    if (pending.isEmpty) {
      if (focusBar != null) {
        return ListView(
          padding: pageInsets(context),
          children: [focusBar, EmptyState(icon: Icons.task_alt, message: tr('payNoPending'))],
        );
      }
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
              ?focusBar,
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
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
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
            const SizedBox(height: 20),
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
