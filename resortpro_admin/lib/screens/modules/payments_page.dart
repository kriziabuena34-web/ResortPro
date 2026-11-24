import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
                maxLength: 300,
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

  /// Ilagay o palitan ng admin ang account na papadalhan ng refund (hal. walk-in
  /// na walang app, o ibinigay ng guest sa chat/tawag).
  Future<void> _enterRefundAccount(Map<String, dynamic> r) async {
    var method = '${r['payout_method'] ?? 'gcash'}';
    if (!['gcash', 'maya', 'cash'].contains(method)) method = 'gcash';
    final number = TextEditingController(text: '${r['payout_number'] ?? ''}');
    final name = TextEditingController(text: '${r['payout_name'] ?? ''}');
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Text(tr('rfAccountTitle')),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('rfAccountHelp'), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 14),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'gcash', label: Text(methodLabel('gcash'))),
                    ButtonSegment(value: 'maya', label: Text(methodLabel('maya'))),
                    ButtonSegment(value: 'cash', label: Text(methodLabel('cash'))),
                  ],
                  selected: {method},
                  onSelectionChanged: (v) => setLocal(() => method = v.first),
                ),
                const SizedBox(height: 12),
                if (method != 'cash') ...[
                  TextField(
                    controller: number,
                    keyboardType: TextInputType.phone,
                    maxLength: 11,
                    buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(labelText: tr('rfAccountNumber'), hintText: '09XX XXX XXXX'),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: name,
                  maxLength: 60,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: tr('rfAccountName')),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr('cancel'))),
            FilledButton(
              onPressed: () {
                final n = number.text.trim();
                if (method != 'cash' && !RegExp(r'^09\d{9}$').hasMatch(n)) {
                  setLocal(() => error = tr('rfAccountNumberInvalid'));
                  return;
                }
                if (name.text.trim().length < 2) {
                  setLocal(() => error = tr('rfAccountNameRequired'));
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: Text(tr('save')),
            ),
          ],
        ),
      ),
    );
    final n = number.text.trim();
    final nm = name.text.trim();
    number.dispose();
    name.dispose();
    if (ok != true || !mounted) return;
    final key = 'refund-${r['id']}';
    setState(() => _busy.add(key));
    try {
      await supabase.from('refund_requests').update({
        'payout_method': method,
        'payout_number': method == 'cash' ? null : n,
        'payout_name': nm,
      }).eq('id', r['id']);
      if (!mounted) return;
      showToast(context, tr('rfAccountSaved'));
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
                  maxLength: 60,
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
          maxLength: 300,
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

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  static const _caps = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.muted);

  List<_PaymentEntry> get _allEntries => [
        for (final b in widget.data.bookings)
          for (final p in paymentsOf(b)) _PaymentEntry(p, b),
      ];

  @override
  Widget build(BuildContext context) {
    final pendingCount = widget.data.pendingPayments.length;
    final refundCount = widget.data.pendingRefunds.length;
    final entries = _allEntries;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        final body = switch (_tab) {
          'refunds' => _refundsSection(),
          'all' => _allSection(entries, constraints.maxWidth),
          _ => _pendingSection(constraints.maxWidth),
        };
        return RefreshIndicator(
          onRefresh: widget.onChanged,
          child: ListView(
            padding: pageInsets(context),
            children: [
              Text(tr('pySubtitle'), style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 14),
              _overviewCard(entries, wide: wide),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: CountTabs<String>(
                  value: _tab,
                  onChanged: (v) => setState(() => _tab = v),
                  items: [
                    (value: 'pending', label: tr('payPendingTab'), count: pendingCount),
                    (value: 'refunds', label: tr('payRefundsTab'), count: refundCount),
                    (value: 'all', label: tr('payAllTab'), count: entries.length),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              ...body,
            ],
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // Buod
  // -------------------------------------------------------------------------

  Widget _overviewCard(List<_PaymentEntry> entries, {required bool wide}) {
    final now = DateTime.now();
    final verified = entries.where((e) => e.status == 'verified');
    double sumWhere(bool Function(DateTime d) test) => verified.fold<double>(0, (s, e) {
          final d = e.date?.toLocal();
          return d != null && test(d) ? s + e.amount : s;
        });
    final today = sumWhere((d) => DateUtils.isSameDay(d, now));
    final month = sumWhere((d) => d.year == now.year && d.month == now.month);
    final pending = widget.data.pendingPayments;
    final pendingAmt = pending.fold<double>(0, (s, e) => s + asDouble(e.payment['amount']));
    final refunds = widget.data.pendingRefunds;
    final refundAmt = refunds.fold<double>(0, (s, r) => s + asDouble(r['amount']));

    final tiles = [
      _tile(tr('pyKPending'), tr('pyKPendingSub', {'n': pending.length}), peso(pendingAmt), const Color(0xFFFACC15),
          Icons.fact_check_outlined, () => setState(() => _tab = 'pending')),
      _tile(tr('pyKRefunds'), tr('pyKRefundsSub', {'n': refunds.length}), peso(refundAmt), const Color(0xFFF87171),
          Icons.currency_exchange, () => setState(() => _tab = 'refunds')),
      _tile(tr('pyKToday'), tr('pyKTodaySub'), peso(today), const Color(0xFF4ADE80), Icons.today_outlined,
          () => setState(() => _tab = 'all')),
      _tile(tr('pyKMonth'), tr('pyKMonthSub'), peso(month), Colors.white, Icons.calendar_month_outlined,
          () => setState(() => _tab = 'all')),
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 12))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.payments_rounded, color: AppColors.inkText, size: 20),
              const SizedBox(width: 8),
              Text(tr('pyOverview'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.8, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 14),
          if (wide)
            Row(
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: tiles[i]),
                ],
              ],
            )
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.45,
              children: tiles,
            ),
        ],
      ),
    );
  }

  Widget _tile(String label, String sub, String value, Color valueColor, IconData icon, VoidCallback onTap) {
    return Material(
      color: AppColors.inkRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.inkLine),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(label,
                        style: const TextStyle(
                            color: AppColors.inkText, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                  ),
                  Icon(icon, size: 16, color: const Color(0xFF7F93A6)),
                ],
              ),
              const SizedBox(height: 2),
              Text(sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF7F93A6), fontSize: 10.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: TextStyle(color: valueColor, fontSize: 24, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Mga pirasong ginagamit ng mga card
  // -------------------------------------------------------------------------

  Widget _hintBox(IconData icon, String text) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.20)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.4))),
          ],
        ),
      );

  Widget _infoRow(IconData icon, String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: AppColors.muted),
            const SizedBox(width: 9),
            SizedBox(width: 104, child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
            const SizedBox(width: 6),
            Expanded(
              child: Text(value.isEmpty ? tr('notSet') : value,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: value.isEmpty ? AppColors.muted : (color ?? AppColors.text),
                  )),
            ),
          ],
        ),
      );

  Widget _boxed(List<Widget> rows) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              rows[i],
            ],
          ],
        ),
      );

  Widget _pill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      );

  Widget _statusPill(String status) => _pill(paymentStatusLabel(status), paymentStatusColor(status));

  IconData _methodIcon(String method) => method == 'cash' ? Icons.payments_outlined : Icons.phone_android_rounded;

  Widget _methodBadge(String method, {double size = 44}) {
    final color = methodColor(method);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(_methodIcon(method), color: color, size: size * 0.48),
    );
  }

  /// Kahon ng card na may header, katawan, at mga button sa ibaba.
  Widget _cardShell({required Widget header, required Widget body, Widget? actions, bool highlight = false}) {
    final line = highlight ? const Color(0xFFF5C451) : AppColors.border;
    return Container(
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFFFFBEB) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: line, width: highlight ? 1.5 : 1),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(padding: const EdgeInsets.fromLTRB(18, 16, 16, 14), child: header),
              Divider(height: 1, color: line),
              Padding(padding: const EdgeInsets.all(16), child: body),
            ],
          ),
          if (actions != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: line))),
              child: actions,
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Hinihintay i-verify
  // -------------------------------------------------------------------------

  List<Widget> _pendingSection(double width) {
    final focus = _focusId == null ? null : widget.data.bookingById(_focusId);
    final pending = widget.data.pendingPayments
        .where((e) => _focusId == null || '${e.booking['id']}' == _focusId)
        .toList();
    return [
      if (focus != null) ...[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterPill(
              icon: Icons.person_outline,
              label: tr('payFocusShowing', {'client': clientNameOf(focus)}),
              active: true,
              onClear: () => setState(() => _focusId = null),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
      _hintBox(Icons.info_outline_rounded, tr('payPendingHint')),
      const SizedBox(height: 14),
      if (pending.isEmpty)
        _emptyCard(Icons.task_alt, tr('payNoPending'))
      else
        CardGrid(
          columns: width >= 1100 ? 2 : 1,
          children: [for (final item in pending) _pendingCard(item.payment, item.booking)],
        ),
    ];
  }

  Widget _emptyCard(IconData icon, String message) => AppCard(
        margin: EdgeInsets.zero,
        child: Padding(padding: const EdgeInsets.all(24), child: EmptyState(icon: icon, message: message)),
      );

  Widget _proofImage(Map<String, dynamic> payment, {required double height}) {
    Widget frame(Widget child) => Container(
          height: height,
          decoration: BoxDecoration(
            color: AppColors.subtle,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        );
    return FutureBuilder<String?>(
      future: _proofUrl(payment['proof_path'] as String?),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return frame(const Center(child: CircularProgressIndicator()));
        }
        final url = snapshot.data;
        if (url == null) {
          return frame(
            Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.image_not_supported_outlined, color: AppColors.danger),
                    const SizedBox(height: 6),
                    Text(tr('payNoProof'),
                        textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
                  ],
                ),
              ),
            ),
          );
        }
        return frame(
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => showDialog(
                context: context,
                builder: (_) => Dialog(clipBehavior: Clip.antiAlias, child: InteractiveViewer(child: Image.network(url))),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stack) =>
                        Center(child: Text(tr('idLoadFail'), style: const TextStyle(color: AppColors.muted))),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xB3000000), borderRadius: BorderRadius.circular(20)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.zoom_in_rounded, size: 15, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(tr('vfZoom'),
                              style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pendingCard(Map<String, dynamic> payment, Map<String, dynamic> booking) {
    final busy = _busy.contains('${payment['id']}');
    final method = '${payment['method'] ?? ''}';
    final reference = '${payment['reference_no'] ?? ''}'.trim();
    final balance = remainingOf(booking);

    final info = _boxed([
      _infoRow(Icons.person_outline, tr('fieldClient'), clientNameOf(booking)),
      _infoRow(Icons.inventory_2_outlined, tr('navPackages'), packageNameOf(booking)),
      _infoRow(Icons.event_outlined, tr('fieldDate'), formatDate(bookingDateOf(booking))),
      _infoRow(Icons.tag_rounded, tr('payReference'), reference),
      _infoRow(Icons.schedule_rounded, tr('paySubmitted'), formatDateTime(parseDate(payment['created_at']))),
      _infoRow(Icons.account_balance_wallet_outlined, tr('fieldBalance'),
          '${peso(balance)} (${tr('payBeforeThis')})', color: balance > 0 ? AppColors.warning : null),
    ]);

    return _cardShell(
      highlight: true,
      header: Row(
        children: [
          _methodBadge(method),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(peso(asDouble(payment['amount'])),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                Text('${kindLabel(payment['kind'] as String?)} · ${methodLabel(method)}',
                    style: TextStyle(color: methodColor(method), fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
          ),
          _statusPill('pending'),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth >= 520) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 210,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('pyProof').toUpperCase(), style: _caps),
                      const SizedBox(height: 8),
                      _proofImage(payment, height: 250),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(tr('pyDetails').toUpperCase(), style: _caps),
                      const SizedBox(height: 8),
                      info,
                    ],
                  ),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('pyDetails').toUpperCase(), style: _caps),
              const SizedBox(height: 8),
              info,
              const SizedBox(height: 16),
              Text(tr('pyProof').toUpperCase(), style: _caps),
              const SizedBox(height: 8),
              _proofImage(payment, height: 260),
            ],
          );
        },
      ),
      actions: Row(
        children: [
          if (busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: busy ? null : () => _reject(payment, booking),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: BorderSide(color: AppColors.danger.withValues(alpha: 0.5)),
            ),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: Text(tr('reject')),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: busy ? null : () => _verify(payment, booking),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E9E5B)),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(tr('payVerifyBtn')),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Refunds (policy #6–#8: kalahati ng reservation fee kapag 5+ araw bago)
  // -------------------------------------------------------------------------

  List<Widget> _refundsSection() {
    final refunds = widget.data.refunds;
    final pending = refunds.where((r) => r['status'] == 'pending').toList();
    final done = refunds.where((r) => r['status'] != 'pending').toList();
    return [
      _hintBox(Icons.info_outline_rounded, tr('rfHint')),
      const SizedBox(height: 14),
      if (refunds.isEmpty)
        _emptyCard(Icons.currency_exchange, tr('rfNone'))
      else ...[
        if (pending.isNotEmpty) ...[
          Text('${tr('pyRefundsToDo')} (${pending.length})'.toUpperCase(), style: _caps),
          const SizedBox(height: 10),
          for (final r in pending) Padding(padding: const EdgeInsets.only(bottom: 12), child: _refundCard(r)),
        ],
        if (done.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('${tr('rfHistory')} (${done.length})'.toUpperCase(), style: _caps),
          const SizedBox(height: 10),
          for (final r in done) Padding(padding: const EdgeInsets.only(bottom: 12), child: _refundCard(r)),
        ],
      ],
    ];
  }

  Widget _refundCard(Map<String, dynamic> r) {
    final booking = widget.data.bookingById(r['booking_id']);
    final status = '${r['status']}';
    final busy = _busy.contains('refund-${r['id']}');
    final method = '${r['payout_method'] ?? ''}';
    // Resort ang nag-cancel: hinihintay pa ang GCash/Maya ng guest.
    final missing = status == 'pending' &&
        (method.isEmpty || (method != 'cash' && '${r['payout_number'] ?? ''}'.trim().isEmpty));
    final byResort = '${r['reason'] ?? ''}'.startsWith('Declined by resort');
    final noAppAccount = booking != null && booking['client_id'] == null;
    final color = switch (status) {
      'refunded' => AppColors.success,
      'rejected' => AppColors.danger,
      _ => AppColors.warning,
    };
    final rows = [
      if (booking != null) _infoRow(Icons.inventory_2_outlined, tr('navPackages'), packageNameOf(booking)),
      if (booking != null) _infoRow(Icons.event_outlined, tr('fieldDate'), formatDate(bookingDateOf(booking))),
      if (missing)
        _infoRow(Icons.hourglass_top_rounded, tr('rfSendTo'),
            noAppAccount ? tr('rfWaitingNoApp') : tr('rfWaitingGuest'))
      else ...[
        _infoRow(Icons.send_to_mobile_outlined, tr('rfSendTo'),
            method == 'cash' ? methodLabel(method) : '${methodLabel(method)} · ${r['payout_number'] ?? ''}'),
        _infoRow(Icons.badge_outlined, tr('rfAccountName'), '${r['payout_name'] ?? ''}'),
      ],
      if ('${r['reason'] ?? ''}'.isNotEmpty) _infoRow(Icons.chat_bubble_outline_rounded, tr('rfReason'), '${r['reason']}'),
      if ('${r['refund_reference'] ?? ''}'.isNotEmpty) _infoRow(Icons.tag_rounded, tr('rcReference'), '${r['refund_reference']}'),
      if ('${r['admin_note'] ?? ''}'.isNotEmpty) _infoRow(Icons.sticky_note_2_outlined, tr('adminNotes'), '${r['admin_note']}'),
    ];
    return _cardShell(
      highlight: status == 'pending',
      header: Row(
        children: [
          _methodBadge(method),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(booking == null ? tr('unknownClient') : clientNameOf(booking),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                Text(
                  byResort
                      ? tr('rfBreakdownResort', {'paid': peso(asDouble(r['paid']))})
                      : tr('rfBreakdown', {
                          'days': asInt(r['days_before']),
                          'paid': peso(asDouble(r['paid'])),
                          'fee': peso(asDouble(r['reservation_fee'])),
                        }),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(peso(asDouble(r['amount'])),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary)),
              const SizedBox(height: 4),
              _pill(missing ? tr('rfStatus_waiting') : tr('rfStatus_$status'), color),
            ],
          ),
        ],
      ),
      body: _boxed(rows),
      actions: status != 'pending'
          ? null
          : Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                if (busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                TextButton.icon(
                  onPressed: busy ? null : () => _enterRefundAccount(r),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(missing ? tr('rfEnterAccount') : tr('rfEditAccount')),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _rejectRefund(r),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: BorderSide(color: AppColors.danger.withValues(alpha: 0.5)),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: Text(tr('rfRejectInvalid')),
                ),
                FilledButton.icon(
                  onPressed: busy || missing ? null : () => _completeRefund(r),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: Text(tr('rfApprove')),
                ),
              ],
            ),
    );
  }

  // -------------------------------------------------------------------------
  // Lahat ng bayad
  // -------------------------------------------------------------------------

  static const _flex = (date: 3, client: 6, type: 3, method: 3, ref: 5, amount: 3, status: 3);
  static const _rowPadding = EdgeInsets.fromLTRB(20, 12, 20, 12);

  Widget _cell(int flex, Widget child, {bool end = false, double gap = 20}) => Expanded(
        flex: flex,
        child: Padding(
          padding: EdgeInsets.only(right: end ? 0 : gap),
          child: child,
        ),
      );

  bool get _anyFilter =>
      _status != 'verified' ||
      _method != 'all' || _kind != 'all' || _range != null || _sort != _PaySort.newest || _query.trim().isNotEmpty;

  List<Widget> _allSection(List<_PaymentEntry> entries, double width) {
    final methods = entries.map((e) => e.method).toSet().toList()..sort();
    final q = _query.trim().toLowerCase();
    bool matchesExceptStatus(_PaymentEntry e) {
      if (_method != 'all' && e.method != _method) return false;
      if (_kind != 'all' && e.kind != _kind) return false;
      if (!inRange(e.date, _range)) return false;
      if (q.isEmpty) return true;
      return clientNameOf(e.booking).toLowerCase().contains(q) ||
          packageNameOf(e.booking).toLowerCase().contains(q) ||
          '${e.payment['reference_no'] ?? ''}'.toLowerCase().contains(q) ||
          e.amount.toStringAsFixed(0).contains(q);
    }

    final base = entries.where(matchesExceptStatus).toList();
    int count(String s) => s == 'all' ? base.length : base.where((e) => e.status == s).length;
    final filtered = base.where((e) => _status == 'all' || e.status == _status).toList();

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

    final verified = base.where((e) => e.status == 'verified').toList();
    final total = verified.fold<double>(0, (s, e) => s + e.amount);
    final down = verified.where((e) => e.kind == 'downpayment').fold<double>(0, (s, e) => s + e.amount);
    final bal = verified.where((e) => e.kind == 'balance').fold<double>(0, (s, e) => s + e.amount);

    final sortOptions = {
      _PaySort.newest: tr('sortDateNewest'),
      _PaySort.oldest: tr('sortDateOldest'),
      _PaySort.amountHigh: tr('sortAmountHigh'),
      _PaySort.amountLow: tr('sortAmountLow'),
    };
    final table = width >= 900;

    Widget mini(String label, String value, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: AppColors.subtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.muted, letterSpacing: 0.5)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
                ),
              ],
            ),
          ),
        );

    return [
      AppCard(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SearchBox(
                controller: _searchController,
                hint: tr('searchPaymentsHint'),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(right: 2),
                    child: Icon(Icons.tune_rounded, size: 18, color: AppColors.muted),
                  ),
                  PopupMenuButton<String>(
                    tooltip: tr('pyColStatus'),
                    position: PopupMenuPosition.under,
                    onSelected: (v) => setState(() => _status = v),
                    itemBuilder: (context) => [
                      for (final st in const ['verified', 'pending', 'rejected', 'all'])
                        CheckedPopupMenuItem(
                          value: st,
                          checked: _status == st,
                          child: Text('${st == 'all' ? tr('pyAllStatuses') : paymentStatusLabel(st)}  (${count(st)})'),
                        ),
                    ],
                    child: FilterPill(
                      icon: _status == 'rejected'
                          ? Icons.block_rounded
                          : _status == 'pending'
                              ? Icons.hourglass_top_rounded
                              : Icons.verified_outlined,
                      label: _status == 'all' ? tr('pyAllStatuses') : tr('bkStatusChip', {'s': paymentStatusLabel(_status)}),
                      active: _status != 'verified',
                      dropdown: true,
                    ),
                  ),
                  PopupMenuButton<_PaySort>(
                    position: PopupMenuPosition.under,
                    tooltip: tr('sortBy'),
                    initialValue: _sort,
                    onSelected: (v) => setState(() => _sort = v),
                    itemBuilder: (context) => [
                      for (final e in sortOptions.entries)
                        CheckedPopupMenuItem<_PaySort>(value: e.key, checked: e.key == _sort, child: Text(e.value)),
                    ],
                    child: FilterPill(
                      icon: Icons.swap_vert_rounded,
                      label: sortOptions[_sort] ?? '',
                      active: _sort != _PaySort.newest,
                      dropdown: true,
                    ),
                  ),
                  DateRangeFilter(range: _range, onChanged: (v) => setState(() => _range = v)),
                  PopupMenuButton<String>(
                    tooltip: tr('allTypes'),
                    position: PopupMenuPosition.under,
                    onSelected: (v) => setState(() => _kind = v),
                    itemBuilder: (context) => [
                      for (final k in const ['all', 'downpayment', 'balance'])
                        CheckedPopupMenuItem(
                          value: k,
                          checked: _kind == k,
                          child: Text(k == 'all' ? tr('allTypes') : kindLabel(k)),
                        ),
                    ],
                    child: FilterPill(
                      icon: Icons.category_outlined,
                      label: _kind == 'all' ? tr('allTypes') : kindLabel(_kind),
                      active: _kind != 'all',
                      dropdown: true,
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: tr('allMethods'),
                    position: PopupMenuPosition.under,
                    onSelected: (v) => setState(() => _method = v),
                    itemBuilder: (context) => [
                      CheckedPopupMenuItem(value: 'all', checked: _method == 'all', child: Text(tr('allMethods'))),
                      for (final m in methods)
                        CheckedPopupMenuItem(value: m, checked: _method == m, child: Text(methodLabel(m))),
                    ],
                    child: FilterPill(
                      icon: _method == 'all' ? Icons.account_balance_wallet_outlined : _methodIcon(_method),
                      label: _method == 'all' ? tr('allMethods') : methodLabel(_method),
                      active: _method != 'all',
                      dropdown: true,
                    ),
                  ),
                  if (_anyFilter)
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _status = 'verified';
                        _method = 'all';
                        _kind = 'all';
                        _range = null;
                        _sort = _PaySort.newest;
                        _query = '';
                        _searchController.clear();
                      }),
                      icon: const Icon(Icons.restart_alt_rounded, size: 18),
                      label: Text(tr('bkResetFilters')),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  mini(tr('totalReceived'), peso(total), AppColors.success),
                  const SizedBox(width: 10),
                  mini(tr('downpayments'), peso(down), AppColors.primary),
                  const SizedBox(width: 10),
                  mini(tr('balancePayments'), peso(bal), AppColors.info),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 18),
      if (filtered.isEmpty)
        _emptyCard(Icons.receipt_long, tr('noPaymentYet'))
      else
        AppCard(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (table) _tableHeader(),
              for (var i = 0; i < filtered.length; i++) ...[
                if (i > 0 || table) const Divider(height: 1),
                table ? _tableRow(filtered[i]) : _listRow(filtered[i]),
              ],
            ],
          ),
        ),
    ];
  }

  Widget _tableHeader() {
    Widget h(String t, int flex, {bool end = false, TextAlign align = TextAlign.left}) => _cell(
          flex,
          Text(t, textAlign: align, style: _caps),
          end: end,
        );
    return Container(
      color: AppColors.subtle,
      padding: _rowPadding,
      child: Row(
        children: [
          h(tr('pyColDate'), _flex.date),
          h(tr('pyColClient'), _flex.client),
          h(tr('pyColType'), _flex.type),
          h(tr('pyColMethod'), _flex.method),
          h(tr('pyColRef'), _flex.ref),
          _cell(_flex.amount, Text(tr('pyColAmount'), textAlign: TextAlign.right, style: _caps), gap: 36),
          h(tr('pyColStatus'), _flex.status, end: true),
        ],
      ),
    );
  }

  /// "Verified by John Sairon" / "Received by John Sairon"
  String? _byLine(_PaymentEntry e) {
    final reviewer = staffNameOf(e.payment['reviewed_by']);
    if (reviewer != null && e.status != 'pending') return tr('payVerifiedBy', {'name': reviewer});
    final receiver = staffNameOf(e.payment['received_by']);
    if (receiver != null) return tr('payReceivedBy', {'name': receiver});
    return null;
  }

  Widget _tableRow(_PaymentEntry e) {
    final reference = '${e.payment['reference_no'] ?? ''}'.trim();
    final reason = '${e.payment['reject_reason'] ?? ''}'.trim();
    final by = _byLine(e);
    const muted = TextStyle(color: AppColors.muted, fontSize: 12.5);
    return Padding(
      padding: _rowPadding,
      child: Row(
        children: [
          _cell(_flex.date, Text(formatDate(e.date), style: const TextStyle(fontWeight: FontWeight.w600))),
          _cell(
            _flex.client,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(clientNameOf(e.booking),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(packageNameOf(e.booking), maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                if (e.status == 'rejected' && reason.isNotEmpty)
                  Text(tr('payRejectedReason', {'reason': reason}),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.danger, fontSize: 12)),
              ],
            ),
          ),
          _cell(_flex.type, Text(kindLabel(e.kind))),
          _cell(
            _flex.method,
            Row(
              children: [
                Icon(_methodIcon(e.method), size: 16, color: methodColor(e.method)),
                const SizedBox(width: 6),
                Flexible(child: Text(methodLabel(e.method), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          _cell(
            _flex.ref,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reference.isEmpty ? '—' : reference,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: reference.isEmpty ? AppColors.muted : AppColors.text)),
                if (by != null) Text(by, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
              ],
            ),
          ),
          _cell(
            _flex.amount,
            Text(
              peso(e.amount),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                decoration: e.status == 'rejected' ? TextDecoration.lineThrough : null,
                color: e.status == 'rejected' ? AppColors.muted : AppColors.text,
              ),
            ),
            gap: 36,
          ),
          _cell(_flex.status, Align(alignment: Alignment.centerLeft, child: _statusPill(e.status)), end: true),
        ],
      ),
    );
  }

  Widget _listRow(_PaymentEntry e) {
    final reference = '${e.payment['reference_no'] ?? ''}'.trim();
    final reason = '${e.payment['reject_reason'] ?? ''}'.trim();
    final by = _byLine(e);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _methodBadge(e.method, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(clientNameOf(e.booking),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  [
                    packageNameOf(e.booking),
                    kindLabel(e.kind),
                    methodLabel(e.method),
                    formatDate(e.date),
                    if (reference.isNotEmpty) 'Ref $reference',
                    ?by,
                  ].join(' · '),
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                ),
                if (e.status == 'rejected' && reason.isNotEmpty)
                  Text(tr('payRejectedReason', {'reason': reason}),
                      style: const TextStyle(color: AppColors.danger, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                peso(e.amount),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  decoration: e.status == 'rejected' ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(height: 4),
              _statusPill(e.status),
            ],
          ),
        ],
      ),
    );
  }
}
