import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../services/booking_workflow.dart';
import '../../services/receipt.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/list_controls.dart';
import '../../widgets/payment_entry.dart';
import 'new_booking_dialog.dart';

/// Booking management: search, filters, sort, workflow (confirm →
/// check in → check out), payments, admin notes, at activity history.
class BookingsPage extends StatefulWidget {
  const BookingsPage({
    super.key,
    required this.data,
    required this.onChanged,
    this.initialFilter,
    this.onOpenPayments,
    this.onOpenCheckin,
  });

  final AdminData data;
  final Future<void> Function() onChanged;

  /// Buksan ang Payments (Pending) para sa booking na ito.
  final void Function(String bookingId)? onOpenPayments;

  /// Buksan ang Check-in / out para sa booking na ito (QR o code ang kailangan).
  final void Function(String bookingId)? onOpenCheckin;

  /// Pwedeng status (hal. 'reserved') o quick filter:
  /// 'today', 'balance', 'overdue'. Galing sa dashboard reminders.
  final String? initialFilter;

  @override
  State<BookingsPage> createState() => _BookingsPageState();
}

enum _Sort { dateNewest, dateOldest, upcoming, amountHigh, balanceHigh }

class _BookingsPageState extends State<BookingsPage> {
  final supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  String _query = '';
  String _status = 'all';
  // Tab ng status: active, completed, closed (cancelled/no-show), all
  String _group = 'active';
  String? _packageId;
  DateTimeRange? _range;
  bool _unpaidOnly = false;
  bool _overdueOnly = false;
  String _source = 'all';
  _Sort _sort = _Sort.dateNewest;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _applyInitialFilter(widget.initialFilter);
  }

  void _applyInitialFilter(String? f) {
    if (f == null) return;
    final today = DateUtils.dateOnly(DateTime.now());
    if (bookingStatuses.contains(f)) {
      _status = f;
      _group = 'all';
    } else if (f == 'today') {
      _range = DateTimeRange(start: today, end: today);
    } else if (f == 'balance') {
      _unpaidOnly = true;
      _sort = _Sort.upcoming;
    } else if (f == 'overdue') {
      _overdueOnly = true;
    }
    if (f == 'today' || f == 'balance' || f == 'overdue') _group = 'all';
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _status = 'all';
      _group = 'active';
      _packageId = null;
      _range = null;
      _unpaidOnly = false;
      _overdueOnly = false;
      _source = 'all';
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static const _activeStatuses = ['reserved', 'confirmed', 'fully_paid', 'checked_in'];

  static bool _inGroup(Map<String, dynamic> b, String group) => switch (group) {
        'active' => _activeStatuses.contains(b['status']),
        'completed' => b['status'] == 'completed',
        'closed' => isInactive(b),
        _ => true,
      };

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    final today = DateUtils.dateOnly(DateTime.now());

    final list = widget.data.bookings.where((b) {
      if (_status != 'all' && b['status'] != _status) return false;
      if (!_inGroup(b, _group)) return false;
      if (_packageId != null && '${b['package_id']}' != _packageId) return false;
      if (_source != 'all' && bookingSourceOf(b) != _source) return false;
      if (!inRange(bookingDateOf(b), _range)) return false;
      if (_unpaidOnly && (isInactive(b) || remainingOf(b) <= 0)) return false;
      if (_overdueOnly) {
        final d = bookingDateOf(b);
        final pendingStatus = const ['reserved', 'confirmed', 'fully_paid'].contains(b['status']);
        if (d == null || !d.isBefore(today) || !pendingStatus) return false;
      }
      if (q.isEmpty) return true;
      return clientNameOf(b).toLowerCase().contains(q) ||
          packageNameOf(b).toLowerCase().contains(q) ||
          '${b['event_type'] ?? ''}'.toLowerCase().contains(q) ||
          (clientPhoneOf(b) ?? '').contains(q) ||
          '${b['id']}'.toLowerCase().startsWith(q);
    }).toList();

    int byDate(Map<String, dynamic> a, Map<String, dynamic> b) {
      final da = bookingDateOf(a), db = bookingDateOf(b);
      if (da == null || db == null) return 0;
      return da.compareTo(db);
    }

    switch (_sort) {
      case _Sort.dateNewest:
        list.sort((a, b) => byDate(b, a));
      case _Sort.dateOldest:
        list.sort(byDate);
      case _Sort.upcoming:
        // Una ang mga paparating (pinakamalapit), sunod ang mga lumipas na.
        list.sort((a, b) {
          final da = bookingDateOf(a), db = bookingDateOf(b);
          if (da == null || db == null) return 0;
          final pa = da.isBefore(today), pb = db.isBefore(today);
          if (pa != pb) return pa ? 1 : -1;
          return pa ? db.compareTo(da) : da.compareTo(db);
        });
      case _Sort.amountHigh:
        list.sort((a, b) => totalOf(b).compareTo(totalOf(a)));
      case _Sort.balanceHigh:
        list.sort((a, b) => remainingOf(b).compareTo(remainingOf(a)));
    }
    return list;
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  Future<void> _runBusy(Map<String, dynamic> booking, Future<void> Function() task) async {
    final id = '${booking['id']}';
    setState(() => _busy.add(id));
    try {
      await task();
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _recordPayment(Map<String, dynamic> booking, double amount, PaymentDetails details) {
    final method = details.method;
    return _runBusy(booking, () async {
      try {
        final payment = await supabase
            .from('payments')
            .insert({
              'booking_id': booking['id'],
              'amount': amount,
              'method': method,
              'kind': paidOf(booking) <= 0 ? 'downpayment' : 'balance',
              'received_by': supabase.auth.currentUser!.id,
              if (!details.isCash) 'reference_no': details.reference,
            })
            .select()
            .single();
        final paidBefore = paidOf(booking);
        final fullyPaid = await BookingWorkflow.afterPayment(booking, amount, method);
        if (details.isCash && details.cashReceived != null) {
          await BookingWorkflow.log(
            booking['id'],
            'note',
            note: '${tr('peCashReceived')} ${peso(details.cashReceived!)}, '
                '${tr('rcChange')} ${peso(details.changeFor(amount))}',
          );
        }

        if (!mounted) return;
        showToast(
          context,
          fullyPaid
              ? tr('recordedFull')
              : tr('recordedPartial', {'amount': peso(remainingOf(booking) - amount)}),
        );
        await showPaymentReceipt(
          context,
          PaymentReceipt(
            paymentId: payment['id'],
            date: DateTime.now(),
            guest: receiptNameOf(booking),
            packageName: packageNameOf(booking),
            bookingDate: bookingDateOf(booking),
            source: bookingSourceOf(booking),
            amount: amount,
            method: method,
            reference: details.isCash ? '' : details.reference,
            cashReceived: details.isCash ? details.cashReceived : null,
            totalAmount: totalOf(booking),
            paidSoFar: paidBefore + amount,
            staff: currentStaffName().toUpperCase(),
            claimCode: booking['client_id'] == null ? booking['claim_code'] as String? : null,
            checkinCode: booking['checkin_code'] as String?,
          ),
        );
        if (!mounted) return;
        await widget.onChanged();
      } catch (e) {
        if (!mounted) return;
        showToast(context, tr('recordFailed', {'e': e}));
      }
    });
  }

  Future<void> _runAction(Map<String, dynamic> booking, WorkflowAction action) async {
    String? note;

    // Policy ng resort: kailangan ng VERIFIED na 50% downpayment bago ma-confirm (ma-reserve).
    if (action.toStatus == 'confirmed' && booking['status'] == 'reserved') {
      final needed = (totalOf(booking) * 0.5).roundToDouble();
      if (paidOf(booking) + 0.01 < needed) {
        final pending = paymentsOf(booking).any((p) => p['status'] == 'pending');
        await showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.payments_outlined, color: AppColors.warning, size: 40),
            title: Text(tr('confirmNeedsDownTitle')),
            content: Text(
              pending
                  ? tr('confirmNeedsDownPending', {'amount': peso(needed)})
                  : tr('confirmNeedsDownNone', {'amount': peso(needed)}),
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('rcClose'))),
              if (widget.onOpenPayments != null)
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    widget.onOpenPayments!('${booking['id']}');
                  },
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: Text(tr('goToPayments')),
                ),
            ],
          ),
        );
        return;
      }
    }

    // Check in / Check out: laging sa Check-in / out page (kailangan ang QR o code ng guest).
    if (action.toStatus == 'checked_in' || action.toStatus == 'completed') {
      if (action.toStatus == 'checked_in' && remainingOf(booking) > 0.01) {
        showToast(context, tr('ciBalanceNeeded', {'amount': peso(remainingOf(booking))}));
        return;
      }
      widget.onOpenCheckin?.call('${booking['id']}');
      return;
    }

    final hasPendingProof = paymentsOf(booking).any((p) => p['status'] == 'pending');
    final needsConfirmWarning = action.toStatus == 'confirmed' && hasPendingProof;

    if (action.destructive ||
        action.toStatus == 'reserved' ||
        needsConfirmWarning) {
      final warning = needsConfirmWarning
              ? (hasPendingProof ? tr('confirmPendingProofWarning') : tr('confirmNoPaymentWarning'))
              : null;

      final result = await _confirmWithNote(
        title: tr('${action.key}Q'),
        message: tr('actionMsg', {
          'action': tr(action.key),
          'package': packageNameOf(booking),
          'client': clientNameOf(booking),
          'date': formatDate(bookingDateOf(booking)),
        }),
        warning: warning,
        confirmText: tr(action.key),
        destructive: action.destructive,
        askNote: action.destructive,
      );
      if (result == null) return;
      note = result;
    }

    await _runBusy(booking, () async {
      try {
        await BookingWorkflow.changeStatus(booking, action.toStatus, note: note);
        if (!mounted) return;
        showToast(context, tr('statusChanged', {'status': statusLabel(action.toStatus)}));
        await widget.onChanged();
      } catch (e) {
        if (!mounted) return;
        showToast(
          context,
          '$e'.contains('DOWNPAYMENT_REQUIRED')
              ? tr('confirmNeedsDownNone', {'amount': peso((totalOf(booking) * 0.5).roundToDouble())})
              : tr('statusChangeFailed', {'e': e}),
        );
      }
    });
  }

  /// Confirm dialog na may optional na reason/note. Ibinabalik ang note
  /// (pwedeng empty string), o null kapag kinansela.
  Future<String?> _confirmWithNote({
    required String title,
    required String message,
    required String confirmText,
    String? warning,
    bool destructive = false,
    bool askNote = false,
  }) {
    final noteController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                if (warning != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE08A00).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Color(0xFFE08A00)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(warning)),
                      ],
                    ),
                  ),
                ],
                if (askNote) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: InputDecoration(labelText: tr('reasonOptional')),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr('back')),
            ),
            FilledButton(
              style: destructive ? FilledButton.styleFrom(backgroundColor: scheme.error) : null,
              onPressed: () => Navigator.pop(dialogContext, noteController.text.trim()),
              child: Text(confirmText),
            ),
          ],
        );
      },
    );
  }

  void _showRecordPaymentDialog(Map<String, dynamic> booking) {
    final remaining = remainingOf(booking);
    final amountController = TextEditingController(text: remaining.toStringAsFixed(0));
    PaymentDetails details = const PaymentDetails(method: 'cash');
    String? error;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(tr('recordBalanceTitle')),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${packageNameOf(booking)} · ${clientNameOf(booking)}'),
                const SizedBox(height: 4),
                Text(
                  tr('remainingBalance', {'amount': peso(remaining)}),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: tr('amountReceived'),
                    prefixText: '₱ ',
                    errorText: error,
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 16),
                Text(tr('paymentMethod'), style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                PaymentEntry(
                  amount: double.tryParse(amountController.text.replaceAll(',', '')) ?? 0,
                  onChanged: (d) => details = d,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr('cancel')),
            ),
            FilledButton(
              onPressed: () {
                final amount = double.tryParse(amountController.text.replaceAll(',', ''));
                if (amount == null || amount <= 0) {
                  setDialogState(() => error = tr('invalidAmount'));
                  return;
                }
                if (amount > remaining + 0.01) {
                  setDialogState(() => error = tr('overBalance', {'amount': peso(remaining)}));
                  return;
                }
                final payError = details.validate(amount);
                if (payError != null) {
                  setDialogState(() => error = tr(payError));
                  return;
                }
                Navigator.pop(dialogContext);
                _recordPayment(booking, amount, details);
              },
              child: Text(tr('record')),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetails(Map<String, dynamic> booking) {
    showDialog(
      context: context,
      builder: (dialogContext) => _BookingDetailsDialog(
        booking: booking,
        onNotesSaved: widget.onChanged,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bookings = widget.data.bookings;
    final filtered = _filtered;

    final sortOptions = {
      _Sort.dateNewest: tr('sortDateNewest'),
      _Sort.dateOldest: tr('sortDateOldest'),
      _Sort.upcoming: tr('sortUpcoming'),
      _Sort.amountHigh: tr('sortAmountHigh'),
      _Sort.balanceHigh: tr('sortBalanceHigh'),
    };

    return ModuleBody(
      fab: AppFab(
        icon: Icons.add,
        label: tr('nbButton'),
        onPressed: () => openNewBooking(context, widget.data, widget.onChanged),
      ),
      child: RefreshIndicator(
        onRefresh: widget.onChanged,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: pageInsets(context, fab: true),
              children: [
                Text(tr('bkSubtitle'), style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 14),
                _overviewCard(bookings, wide: wide),
                const SizedBox(height: 18),
                AppCard(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Search + mga tab ng status
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                              width: wide ? 380 : double.infinity,
                              child: SearchBox(
                                controller: _searchController,
                                hint: tr('searchHint'),
                                onChanged: (v) => setState(() => _query = v),
                              ),
                            ),
                            _groupTabs(bookings),
                          ],
                        ),
                      ),
                      // Iba pang filter (iisang itsura: pill na may icon; kulay teal kapag naka-on)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                        child: _filterBar(sortOptions),
                      ),
                      ResultCount(shown: filtered.length, total: bookings.length, onClear: _clearFilters),
                      if (filtered.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: EmptyState(icon: Icons.event_busy, message: tr('noBookingsMatch')),
                        )
                      else ...[
                        if (wide) _tableHeader(),
                        for (var i = 0; i < filtered.length; i++) ...[
                          if (i > 0 || !wide) const Divider(height: 1),
                          _buildBookingRow(filtered[i], wide: wide),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  bool get _anyFilter =>
      _status != 'all' ||
      _packageId != null ||
      _range != null ||
      _unpaidOnly ||
      _overdueOnly ||
      _source != 'all' ||
      _sort != _Sort.dateNewest;

  Widget _filterBar(Map<_Sort, String> sortOptions) {
    final r = _range;
    final rangeLabel = r == null
        ? tr('anyDate')
        : DateUtils.isSameDay(r.start, r.end)
            ? formatDate(r.start)
            : '${formatDate(r.start)} – ${formatDate(r.end)}';
    String packageLabel = tr('allPackages');
    for (final p in widget.data.packages) {
      if ('${p['id']}' == _packageId) packageLabel = '${p['name']}';
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 2),
          child: Icon(Icons.tune_rounded, size: 18, color: AppColors.muted),
        ),
        if (_status != 'all')
          _FilterPill(
            icon: Icons.flag_outlined,
            label: tr('bkStatusChip', {'s': statusLabel(_status)}),
            active: true,
            onClear: () => setState(() => _status = 'all'),
          ),
        // Sort
        PopupMenuButton<_Sort>(
          tooltip: tr('sortBy'),
          initialValue: _sort,
          onSelected: (v) => setState(() => _sort = v),
          itemBuilder: (context) => [
            for (final e in sortOptions.entries)
              CheckedPopupMenuItem<_Sort>(value: e.key, checked: e.key == _sort, child: Text(e.value)),
          ],
          child: _FilterPill(
            icon: Icons.swap_vert_rounded,
            label: sortOptions[_sort] ?? '',
            active: _sort != _Sort.dateNewest,
            dropdown: true,
          ),
        ),
        // Petsa
        _FilterPill(
          icon: Icons.calendar_month_outlined,
          label: rangeLabel,
          active: r != null,
          dropdown: r == null,
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(now.year - 3),
              lastDate: DateTime(now.year + 3, 12, 31),
              initialDateRange: r,
            );
            if (picked != null) setState(() => _range = picked);
          },
          onClear: () => setState(() => _range = null),
        ),
        // Package
        PopupMenuButton<String>(
          tooltip: tr('filterPackage'),
          onSelected: (v) => setState(() => _packageId = v == '__all' ? null : v),
          itemBuilder: (context) => [
            CheckedPopupMenuItem(value: '__all', checked: _packageId == null, child: Text(tr('allPackages'))),
            for (final p in widget.data.packages)
              CheckedPopupMenuItem(
                value: '${p['id']}',
                checked: '${p['id']}' == _packageId,
                child: Text('${p['name']}'),
              ),
          ],
          child: _FilterPill(
            icon: Icons.inventory_2_outlined,
            label: packageLabel,
            active: _packageId != null,
            dropdown: true,
          ),
        ),
        // Source
        PopupMenuButton<String>(
          tooltip: tr('filterSource'),
          onSelected: (v) => setState(() => _source = v),
          itemBuilder: (context) => [
            for (final s in const ['all', 'online', 'walk_in', 'phone'])
              CheckedPopupMenuItem(
                value: s,
                checked: _source == s,
                child: Text(s == 'all' ? tr('allSources') : sourceLabel(s)),
              ),
          ],
          child: _FilterPill(
            icon: _source == 'all' ? Icons.hub_outlined : sourceIcon(_source),
            label: _source == 'all' ? tr('allSources') : sourceLabel(_source),
            active: _source != 'all',
            dropdown: true,
          ),
        ),
        // Mga toggle
        _FilterPill(
          icon: Icons.account_balance_wallet_outlined,
          label: tr('filterWithBalance'),
          active: _unpaidOnly,
          toggle: true,
          onTap: () => setState(() => _unpaidOnly = !_unpaidOnly),
        ),
        _FilterPill(
          icon: Icons.event_busy_outlined,
          label: tr('filterOverdue'),
          active: _overdueOnly,
          toggle: true,
          onTap: () => setState(() => _overdueOnly = !_overdueOnly),
        ),
        if (_anyFilter)
          TextButton.icon(
            onPressed: () => setState(() {
              _status = 'all';
              _packageId = null;
              _range = null;
              _unpaidOnly = false;
              _overdueOnly = false;
              _source = 'all';
              _sort = _Sort.dateNewest;
            }),
            icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
            label: Text(tr('bkResetFilters')),
          ),
      ],
    );
  }

  /// Madilim na buod sa itaas: halaga, natanggap, balanse, at fully paid.
  Widget _overviewCard(List<Map<String, dynamic>> bookings, {required bool wide}) {
    final active = bookings.where((b) => !isInactive(b)).toList();
    final value = active.fold<double>(0, (s, b) => s + totalOf(b));
    final received = active.fold<double>(0, (s, b) => s + paidOf(b));
    final outstanding = active.fold<double>(0, (s, b) => s + remainingOf(b));
    final fullyPaid = active.where((b) => remainingOf(b) <= 0.01).length;
    final awaitingDown = active
        .where((b) => b['status'] == 'reserved' && paidOf(b) + 0.01 < (totalOf(b) * 0.5).roundToDouble())
        .length;
    String pct(double part) => value <= 0 ? '0' : (part / value * 100).round().toString();

    final tiles = [
      _overviewTile(tr('bkTotalValue'), tr('bkTotalValueSub', {'n': active.length}), peso(value), Colors.white),
      _overviewTile(tr('bkReceived'), tr('bkReceivedSub', {'p': pct(received)}), peso(received), const Color(0xFF4ADE80)),
      _overviewTile(tr('bkOutstanding'), tr('bkOutstandingSub', {'p': pct(outstanding)}), peso(outstanding),
          const Color(0xFFFBBF24)),
      _overviewTile(tr('bkFullyPaid'), tr('bkFullyPaidSub', {'n': awaitingDown}), '$fullyPaid',
          Colors.white, suffix: ' ${tr('bkOf', {'n': active.length})}'),
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
              const Icon(Icons.bar_chart_rounded, color: AppColors.inkText, size: 20),
              const SizedBox(width: 8),
              Text(
                tr('bkOverview'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.8, fontSize: 13),
              ),
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
              childAspectRatio: 1.55,
              children: tiles,
            ),
        ],
      ),
    );
  }

  Widget _overviewTile(String label, String sub, String value, Color valueColor, {String? suffix}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.inkRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.inkLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(color: AppColors.inkText, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
          const SizedBox(height: 2),
          Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF7F93A6), fontSize: 10.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: value, style: TextStyle(color: valueColor, fontSize: 20, fontWeight: FontWeight.w800)),
                if (suffix != null)
                  TextSpan(text: suffix, style: const TextStyle(color: AppColors.inkText, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// Mga tab: Active · Completed · Cancelled/No-show · All, may bilang.
  Widget _groupTabs(List<Map<String, dynamic>> bookings) {
    int count(String g) => bookings.where((b) => _inGroup(b, g)).length;
    final groups = {
      'active': tr('bkGroupActive'),
      'completed': tr('bkGroupCompleted'),
      'closed': tr('bkGroupClosed'),
      'all': tr('filterAll'),
    };
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.subtle,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in groups.entries)
              _groupTab(e.value, count(e.key), _group == e.key, () => setState(() => _group = e.key),
                  highlight: e.key == 'active'),
          ],
        ),
      ),
    );
  }

  Widget _groupTab(String label, int n, bool selected, VoidCallback onTap, {bool highlight = false}) {
    return Material(
      color: selected ? AppColors.ink : Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.text,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  )),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: selected && highlight
                      ? AppColors.accent
                      : selected
                          ? Colors.white24
                          : const Color(0xFFE6EBF0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$n',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: selected && highlight ? AppColors.ink : (selected ? Colors.white : AppColors.muted),
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Kailangang asikasuhin? (may proof na ive-verify, o dumating na ang araw pero may balanse)
  String? _attentionOf(Map<String, dynamic> b) {
    if (isInactive(b) || b['status'] == 'completed') return null;
    if (pendingPaidOf(b) > 0) return tr('bkNeedsVerify');
    final d = bookingDateOf(b);
    final today = DateUtils.dateOnly(DateTime.now());
    if (d != null && !d.isAfter(today) && remainingOf(b) > 0.01) return tr('bkNeedsBalance');
    return null;
  }

  // Lapad ng bawat column (malapad na screen).
  static const _flex = (booking: 6, source: 3, date: 3, total: 3, received: 3, balance: 3, status: 3);

  Widget _tableHeader() {
    Widget h(String t, int flex, {TextAlign align = TextAlign.left}) => Expanded(
          flex: flex,
          child: Text(
            t,
            textAlign: align,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.muted),
          ),
        );
    return Container(
      color: AppColors.subtle,
      padding: const EdgeInsets.fromLTRB(24, 12, 20, 12),
      child: Row(
        children: [
          h(tr('bkColBooking'), _flex.booking),
          h(tr('bkColSource'), _flex.source),
          h(tr('bkColDate'), _flex.date),
          h(tr('bkColTotal'), _flex.total),
          h(tr('bkColReceived'), _flex.received),
          h(tr('bkColBalance'), _flex.balance),
          h(tr('bkColStatus'), _flex.status),
          SizedBox(width: 96, child: Text(tr('bkColAction'), textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.muted))),
        ],
      ),
    );
  }

  /// Isang hanay ng booking (parang table). Mata = Details; ⋮ = lahat ng aksyon.
  Widget _buildBookingRow(Map<String, dynamic> booking, {required bool wide}) {
    final theme = Theme.of(context);
    final total = totalOf(booking);
    final paid = paidOf(booking);
    final remaining = isInactive(booking) ? 0.0 : remainingOf(booking);
    final busy = _busy.contains('${booking['id']}');
    final status = booking['status'] as String?;
    final name = clientNameOf(booking);
    final source = bookingSourceOf(booking);
    final attention = _attentionOf(booking);

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          packageNameOf(booking).toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.muted),
        ),
        const SizedBox(height: 2),
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        if (attention != null) ...[
          const SizedBox(height: 5),
          _badge(attention),
        ],
      ],
    );

    final sourcePill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(sourceIcon(source), size: 14, color: AppColors.muted),
          const SizedBox(width: 5),
          Flexible(child: Text(sourceLabel(source), overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
        ],
      ),
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy)
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        IconButton.outlined(
          tooltip: tr('details'),
          onPressed: () => _showDetails(booking),
          icon: const Icon(Icons.visibility_outlined, size: 18),
        ),
        _actionsMenu(booking, busy: busy),
      ],
    );

    const money = TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5);
    final decoration = attention == null
        ? null
        : BoxDecoration(
            color: const Color(0xFFFFFBEB),
            border: Border.all(color: const Color(0xFFF5C451), width: 1.5),
          );

    if (wide) {
      return Container(
        decoration: decoration,
        child: InkWell(
          onTap: () => _showDetails(booking),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 20, 14),
            child: Row(
              children: [
                Expanded(flex: _flex.booking, child: title),
                Expanded(flex: _flex.source, child: Align(alignment: Alignment.centerLeft, child: sourcePill)),
                Expanded(
                  flex: _flex.date,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(formatDate(bookingDateOf(booking)), style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(tr('paxCount', {'n': guestsOf(booking)}), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Expanded(flex: _flex.total, child: Text(peso(total), style: money)),
                Expanded(flex: _flex.received, child: Text(peso(paid), style: money)),
                Expanded(
                  flex: _flex.balance,
                  child: Text(peso(remaining),
                      style: money.copyWith(color: remaining > 0.01 ? AppColors.warning : AppColors.text)),
                ),
                Expanded(flex: _flex.status, child: Align(alignment: Alignment.centerLeft, child: StatusChip(status: status))),
                SizedBox(width: 96, child: Align(alignment: Alignment.centerRight, child: actions)),
              ],
            ),
          ),
        ),
      );
    }

    // Phone: siksik na hanay.
    Widget amount(String label, double v, {Color? color}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.muted, letterSpacing: 0.5)),
            Text(peso(v), style: money.copyWith(fontSize: 13.5, color: color)),
          ],
        );
    return Container(
      decoration: decoration,
      child: InkWell(
        onTap: () => _showDetails(booking),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: title),
                  StatusChip(status: status),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  sourcePill,
                  Text('${formatDate(bookingDateOf(booking))} · ${tr('paxCount', {'n': guestsOf(booking)})}',
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: amount(tr('bkColTotal'), total)),
                  Expanded(child: amount(tr('bkColReceived'), paid)),
                  Expanded(
                    child: amount(tr('bkColBalance'), remaining,
                        color: remaining > 0.01 ? AppColors.warning : null),
                  ),
                  actions,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: const Color(0xFFFACC15), borderRadius: BorderRadius.circular(6)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.circle, size: 6, color: AppColors.ink),
            const SizedBox(width: 5),
            Text(text, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.ink, letterSpacing: 0.4)),
          ],
        ),
      );

  /// ⋮ sa gilid: lahat ng puwedeng gawin sa booking (Confirm, Check in, Record balance, No-show…).
  Widget _actionsMenu(Map<String, dynamic> booking, {required bool busy}) {
    final theme = Theme.of(context);
    final actions = BookingWorkflow.actionsFor(booking);
    final remaining = remainingOf(booking);
    final downVerified = paidOf(booking) + 0.01 >= (totalOf(booking) * 0.5).roundToDouble();
    final canRecord = !isInactive(booking) && remaining > 0;

    Widget item(IconData icon, String label, {bool danger = false, bool enabled = true, String? hint}) {
      final color = !enabled ? AppColors.muted : (danger ? theme.colorScheme.error : null);
      return Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(color: color)),
                if (hint != null) Text(hint, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      );
    }

    return PopupMenuButton<String>(
      enabled: !busy,
      tooltip: tr('moreActions'),
      icon: const Icon(Icons.more_vert),
      onSelected: (v) {
        if (v == 'record') {
          _showRecordPaymentDialog(booking);
          return;
        }
        final i = int.tryParse(v);
        if (i != null) _runAction(booking, actions[i]);
      },
      itemBuilder: (context) => [
        // Pangunahing aksyon muna (hal. Confirm, Check in)
        for (var i = 0; i < actions.length; i++)
          if (actions[i].primary)
            PopupMenuItem(value: '$i', child: item(actions[i].icon, tr(actions[i].key))),
        if (canRecord)
          PopupMenuItem(
            value: 'record',
            enabled: downVerified,
            child: item(
              Icons.add_card,
              tr('recordBalance', {'amount': peso(remaining)}),
              enabled: downVerified,
              hint: downVerified ? null : tr('recordBalanceLocked'),
            ),
          ),
        if (actions.any((a) => !a.primary)) const PopupMenuDivider(),
        for (var i = 0; i < actions.length; i++)
          if (!actions[i].primary)
            PopupMenuItem(
              value: '$i',
              child: item(actions[i].icon, tr(actions[i].key), danger: actions[i].destructive),
            ),
      ],
    );
  }

}

/// Iisang itsura ng filter button: pill na may icon at label.
/// Teal ang kulay kapag naka-on; may ⌄ kapag dropdown, may ✓ kapag toggle, may ✕ para alisin.
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.icon,
    required this.label,
    this.active = false,
    this.dropdown = false,
    this.toggle = false,
    this.onTap,
    this.onClear,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool dropdown;
  final bool toggle;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppColors.primaryDark : AppColors.text;
    final pill = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 38,
      padding: EdgeInsets.only(left: 12, right: active && onClear != null ? 4 : 12),
      decoration: BoxDecoration(
        color: active ? AppColors.primary.withValues(alpha: 0.10) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? AppColors.primary.withValues(alpha: 0.55) : AppColors.border),
        boxShadow: active ? null : const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(toggle && active ? Icons.check_circle_rounded : icon, size: 17, color: active ? AppColors.primary : AppColors.muted),
          const SizedBox(width: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontWeight: active ? FontWeight.w700 : FontWeight.w600, fontSize: 13.5),
            ),
          ),
          if (dropdown) ...[
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 18, color: active ? AppColors.primary : AppColors.muted),
          ],
          if (active && onClear != null)
            InkWell(
              onTap: onClear,
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(5),
                child: Icon(Icons.close_rounded, size: 16, color: AppColors.primaryDark),
              ),
            ),
        ],
      ),
    );
    if (onTap == null) return pill;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(20), child: pill),
    );
  }
}

// ---------------------------------------------------------------------------
// Booking details: info, payments, admin notes, activity history
// ---------------------------------------------------------------------------

class _BookingDetailsDialog extends StatefulWidget {
  const _BookingDetailsDialog({required this.booking, required this.onNotesSaved});

  final Map<String, dynamic> booking;
  final Future<void> Function() onNotesSaved;

  @override
  State<_BookingDetailsDialog> createState() => _BookingDetailsDialogState();
}

class _BookingDetailsDialogState extends State<_BookingDetailsDialog> {
  late final TextEditingController _notes =
      TextEditingController(text: '${widget.booking['admin_notes'] ?? ''}');
  late Future<List<Map<String, dynamic>>> _logs = BookingWorkflow.logsFor(widget.booking['id']);
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _saveNotes() async {
    setState(() => _saving = true);
    try {
      await BookingWorkflow.saveNotes(widget.booking, _notes.text.trim());
      widget.booking['admin_notes'] = _notes.text.trim();
      if (!mounted) return;
      showToast(context, tr('notesSaved'));
      setState(() => _logs = BookingWorkflow.logsFor(widget.booking['id']));
      widget.onNotesSaved();
    } catch (e) {
      if (!mounted) return;
      showToast(context, tr('notesFailed', {'e': e}));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _logText(Map<String, dynamic> log) {
    switch (log['action']) {
      case 'status_change':
        return tr('logStatus', {
          'from': statusLabel(log['from_status'] as String?),
          'to': statusLabel(log['to_status'] as String?),
        });
      case 'payment':
        return tr('logPayment', {'detail': log['note'] ?? ''});
      case 'note':
        return tr('logNote');
      case 'payment_verified':
        return tr('logPaymentVerified', {'detail': log['note'] ?? ''});
      case 'payment_rejected':
        return tr('logPaymentRejected', {'detail': log['note'] ?? ''});
      case 'created':
        return tr('logCreated', {'detail': log['note'] ?? ''});
      case 'survey_skipped':
        return tr('logSurveySkipped');
      default:
        return '${log['action']}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    final theme = Theme.of(context);
    final payments = paymentsOf(booking);
    final guestRows = [
      (tr('guestInfants'), booking['infants']),
      (tr('guestChildren'), booking['children']),
      (tr('guestTeens'), booking['teens']),
      (tr('guestAdults'), booking['adults']),
      (tr('guestElderly'), booking['elderly']),
    ].where((g) => asInt(g.$2) > 0).map((g) => '${g.$1}: ${asInt(g.$2)}').join(', ');

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(packageNameOf(booking))),
          StatusChip(status: booking['status'] as String?),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoRow(tr('fieldClient'), clientNameOf(booking)),
              InfoRow(tr('fieldPhone'), clientPhoneOf(booking) ?? tr('notSet')),
              InfoRow(tr('filterSource'), sourceLabel(bookingSourceOf(booking))),
              InfoRow(tr('fieldDate'), formatDate(bookingDateOf(booking))),
              if (booking['event_type'] != null)
                InfoRow(tr('fieldEventType'), '${booking['event_type']}'),
              InfoRow(tr('fieldGuests'), tr('paxCount', {'n': guestsOf(booking)})),
              if (guestRows.isNotEmpty) InfoRow(tr('fieldBreakdown'), guestRows),
              InfoRow(tr('bookingRef'), '#${'${booking['id']}'.split('-').first.toUpperCase()}'),
              if (booking['client_id'] == null && '${booking['claim_code'] ?? ''}'.length == 8)
                InfoRow(
                  tr('rcClaimCode'),
                  '${'${booking['claim_code']}'.substring(0, 4)}-${'${booking['claim_code']}'.substring(4)}',
                ),
              const Divider(height: 24),
              InfoRow(tr('fieldTotal'), peso(totalOf(booking))),
              InfoRow(tr('fieldPaid'), peso(paidOf(booking))),
              InfoRow(tr('fieldBalance'), peso(remainingOf(booking))),
              const SizedBox(height: 12),
              Text(tr('paymentsHeading'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              if (payments.isEmpty) Text(tr('noPaymentYet')),
              for (final p in payments)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long, size: 20, color: methodColor('${p['method']}')),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${kindLabel(p['kind'] as String?)} · ${methodLabel(p['method'] as String?)}'
                          '${p['created_at'] != null ? ' · ${formatDate(parseDate(p['created_at']))}' : ''}'
                          '${p['reference_no'] != null ? ' · Ref ${p['reference_no']}' : ''}'
                          ' · ${paymentStatusLabel(p['status'] as String?)}',
                        ),
                      ),
                      Text(
                        peso(asDouble(p['amount'])),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 24),
              Text(tr('adminNotes'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(hintText: tr('adminNotesHint')),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: _saving ? null : _saveNotes,
                  child: Text(tr('saveNotes')),
                ),
              ),
              const Divider(height: 24),
              Text(tr('activityHistory'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _logs,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final logs = snapshot.data ?? [];
                  if (logs.isEmpty) {
                    return Text(
                      tr('noActivity'),
                      style: theme.textTheme.bodySmall,
                    );
                  }
                  return Column(
                    children: [
                      for (final log in logs)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                log['action'] == 'payment'
                                    ? Icons.payments_outlined
                                    : log['action'] == 'note'
                                        ? Icons.sticky_note_2_outlined
                                        : Icons.swap_horiz,
                                size: 18,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_logText(log)),
                                    if (staffNameOf(log['actor_id']) != null)
                                      Text(
                                        tr('logBy', {'name': staffNameOf(log['actor_id'])!}),
                                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                                      ),
                                    if (log['action'] != 'payment' &&
                                        '${log['note'] ?? ''}'.trim().isNotEmpty)
                                      Text(
                                        '“${log['note']}”',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Text(
                                formatDateTime(parseDate(log['created_at'])),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('close')),
        ),
      ],
    );
  }
}
