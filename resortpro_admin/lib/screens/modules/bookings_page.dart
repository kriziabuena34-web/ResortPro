import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../services/booking_workflow.dart';
import '../../services/checkin_service.dart';
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
  });

  final AdminData data;
  final Future<void> Function() onChanged;

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
    } else if (f == 'today') {
      _range = DateTimeRange(start: today, end: today);
    } else if (f == 'balance') {
      _unpaidOnly = true;
      _sort = _Sort.upcoming;
    } else if (f == 'overdue') {
      _overdueOnly = true;
    }
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _status = 'all';
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

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    final today = DateUtils.dateOnly(DateTime.now());

    final list = widget.data.bookings.where((b) {
      if (_status != 'all' && b['status'] != _status) return false;
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
            guest: clientNameOf(booking),
            packageName: packageNameOf(booking),
            bookingDate: bookingDateOf(booking),
            source: bookingSourceOf(booking),
            amount: amount,
            method: method,
            reference: details.isCash ? '' : details.reference,
            cashReceived: details.isCash ? details.cashReceived : null,
            totalAmount: totalOf(booking),
            paidSoFar: paidBefore + amount,
            staff: supabase.auth.currentUser?.email ?? 'Admin',
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
              FilledButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('rcClose'))),
            ],
          ),
        );
        return;
      }
    }

    final hasPendingProof = paymentsOf(booking).any((p) => p['status'] == 'pending');
    final needsConfirmWarning = action.toStatus == 'confirmed' && hasPendingProof;

    if (action.destructive ||
        action.toStatus == 'checked_in' ||
        action.toStatus == 'reserved' ||
        needsConfirmWarning) {
      final warning = action.toStatus == 'checked_in' && remainingOf(booking) > 0
          ? tr('checkInBalanceWarning', {'amount': peso(remainingOf(booking))})
          : needsConfirmWarning
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

    // Check in / Check out: dumaan sa parehong proseso ng QR scan
    // (bayad muna bago pumasok; multa kapag late; survey bago matapos).
    if (action.toStatus == 'checked_in' || action.toStatus == 'completed') {
      await _runBusy(booking, () async {
        try {
          final result = await CheckinService.scan(bookingId: '${booking['id']}');
          await widget.onChanged();
          if (!mounted) return;
          await showScanResult(
            context,
            result: result,
            booking: booking,
            onSurvey: () async {
              if (await showSurveyDialog(context, booking) && mounted) {
                showToast(context, tr('svDone'));
                await widget.onChanged();
              }
            },
          );
        } catch (e) {
          if (!mounted) return;
          showToast(context, CheckinService.friendly(e));
        }
      });
      return;
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
          title: Text(paidOf(booking) <= 0 ? tr('recordDownpayment') : tr('recordBalanceTitle')),
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

    int countOf(String status) =>
        status == 'all' ? bookings.length : bookings.where((b) => b['status'] == status).length;

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
      child: Column(
      children: [
        FloatingToolbar(
          children: [
            SearchBox(
              controller: _searchController,
              hint: tr('searchHint'),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            ChipRow(
              children: [
                for (final s in ['all', ...bookingStatuses])
                  if (s == 'all' || countOf(s) > 0 || _status == s)
                    ChoiceChip(
                      label: Text('${s == 'all' ? tr('filterAll') : statusLabel(s)} (${countOf(s)})'),
                      selected: _status == s,
                      onSelected: (_) => setState(() => _status = s),
                    ),
              ],
            ),
            const SizedBox(height: 2),
            ChipRow(
              children: [
                SortMenu<_Sort>(
                  value: _sort,
                  options: sortOptions,
                  onChanged: (v) => setState(() => _sort = v),
                ),
                DateRangeChip(range: _range, onChanged: (r) => setState(() => _range = r)),
                _PackageFilter(
                  packages: widget.data.packages,
                  value: _packageId,
                  onChanged: (v) => setState(() => _packageId = v),
                ),
                FilterChip(
                  label: Text(tr('filterWithBalance')),
                  selected: _unpaidOnly,
                  onSelected: (v) => setState(() => _unpaidOnly = v),
                ),
                FilterChip(
                  label: Text(tr('filterOverdue')),
                  selected: _overdueOnly,
                  onSelected: (v) => setState(() => _overdueOnly = v),
                ),
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
                  child: Chip(
                    avatar: Icon(_source == 'all' ? Icons.hub_outlined : sourceIcon(_source), size: 18),
                    label: Text(_source == 'all' ? tr('allSources') : sourceLabel(_source)),
                  ),
                ),
              ],
            ),
          ],
        ),
        ResultCount(shown: filtered.length, total: bookings.length, onClear: _clearFilters),
        Expanded(
          child: filtered.isEmpty
              ? EmptyState(icon: Icons.event_busy, message: tr('noBookingsMatch'))
              : RefreshIndicator(
                  onRefresh: widget.onChanged,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 1100 ? 2 : 1;
                      if (columns == 1) {
                        return ListView.builder(
                          padding: pageInsets(context, fab: true).copyWith(top: 8),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _buildBookingCard(filtered[index]),
                          ),
                        );
                      }
                      final insets = pageInsets(context, fab: true).copyWith(top: 8);
                      return SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: insets,
                        child: CardGrid(
                          columns: columns,
                          children: [
                            for (final b in filtered) _buildBookingCard(b),
                          ],
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

  Widget _buildBookingCard(Map<String, dynamic> booking) {
    final theme = Theme.of(context);
    final total = totalOf(booking);
    final paid = paidOf(booking);
    final remaining = remainingOf(booking);
    final inactive = isInactive(booking);
    final busy = _busy.contains('${booking['id']}');
    final actions = BookingWorkflow.actionsFor(booking);
    final primary = actions.where((a) => a.primary).toList();
    final secondary = actions.where((a) => !a.primary).toList();
    final status = booking['status'] as String?;

    final name = clientNameOf(booking);
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final progress = total <= 0 ? 0.0 : (paid / total).clamp(0, 1).toDouble();
    final paidColor = remaining <= 0 ? AppColors.success : AppColors.accent;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: client + status
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: statusColor(status).withValues(alpha: 0.12),
                  child: Text(
                    initial,
                    style: TextStyle(color: statusColor(status), fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        packageNameOf(booking),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, letterSpacing: -0.2),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                StatusChip(status: status),
              ],
            ),
          ),

          // Detalye
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metaPill(Icons.calendar_today_outlined, formatDate(bookingDateOf(booking))),
                _metaPill(Icons.groups_outlined, tr('paxCount', {'n': guestsOf(booking)})),
                if (bookingSourceOf(booking) != 'online')
                  _metaPill(sourceIcon(bookingSourceOf(booking)), sourceLabel(bookingSourceOf(booking))),
                if (booking['event_type'] != null)
                  _metaPill(Icons.celebration_outlined, '${booking['event_type']}'),
                if ('${booking['admin_notes'] ?? ''}'.trim().isNotEmpty)
                  _metaPill(Icons.sticky_note_2_outlined, tr('hasNotes')),
                if (pendingPaidOf(booking) > 0)
                  _metaPill(
                    Icons.hourglass_top,
                    tr('pendingProofAmount', {'amount': peso(pendingPaidOf(booking))}),
                    color: AppColors.warning,
                  ),
              ],
            ),
          ),

          // Bayad
          Container(
            margin: const EdgeInsets.fromLTRB(18, 14, 18, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.subtle,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      peso(paid),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    Text('  /  ${peso(total)}', style: theme.textTheme.bodySmall),
                    const Spacer(),
                    Text(
                      remaining > 0 ? tr('balanceAmount', {'amount': peso(remaining)}) : '${(progress * 100).round()}%',
                      style: TextStyle(color: paidColor, fontWeight: FontWeight.w700, fontSize: 12.5),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    color: paidColor,
                    backgroundColor: const Color(0xFFE6EBF0),
                  ),
                ),
              ],
            ),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final a in primary)
                        FilledButton.icon(
                          onPressed: busy ? null : () => _runAction(booking, a),
                          icon: Icon(a.icon, size: 18),
                          label: Text(tr(a.key)),
                        ),
                      if (!inactive && remaining > 0)
                        OutlinedButton.icon(
                          onPressed: busy ? null : () => _showRecordPaymentDialog(booking),
                          icon: const Icon(Icons.add_card, size: 18),
                          // Wala pang bayad: downpayment; may bayad na: ang natitirang balanse.
                          label: Text(paidOf(booking) <= 0
                              ? tr('recordDownpayment')
                              : tr('recordBalance', {'amount': peso(remaining)})),
                        ),
                      TextButton(
                        onPressed: () => _showDetails(booking),
                        child: Text(tr('details')),
                      ),
                    ],
                  ),
                ),
                if (secondary.isNotEmpty)
                  PopupMenuButton<WorkflowAction>(
                    enabled: !busy,
                    tooltip: tr('moreActions'),
                    onSelected: (a) => _runAction(booking, a),
                    itemBuilder: (context) => [
                      for (final a in secondary)
                        PopupMenuItem(
                          value: a,
                          child: Row(
                            children: [
                              Icon(
                                a.icon,
                                size: 20,
                                color: a.destructive ? theme.colorScheme.error : null,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                tr(a.key),
                                style: TextStyle(
                                  color: a.destructive ? theme.colorScheme.error : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    icon: const Icon(Icons.more_vert, color: AppColors.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaPill(IconData icon, String text, {Color? color}) {
    final c = color ?? AppColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color == null ? const Color(0xFFF1F4F7) : c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color ?? AppColors.text,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageFilter extends StatelessWidget {
  const _PackageFilter({required this.packages, required this.value, required this.onChanged});

  final List<Map<String, dynamic>> packages;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    String? selectedName;
    for (final p in packages) {
      if ('${p['id']}' == value) selectedName = '${p['name']}';
    }

    return PopupMenuButton<String>(
      tooltip: tr('filterPackage'),
      onSelected: (v) => onChanged(v == '__all' ? null : v),
      itemBuilder: (context) => [
        CheckedPopupMenuItem(value: '__all', checked: value == null, child: Text(tr('allPackages'))),
        for (final p in packages)
          CheckedPopupMenuItem(
            value: '${p['id']}',
            checked: '${p['id']}' == value,
            child: Text('${p['name']}'),
          ),
      ],
      child: Chip(
        avatar: const Icon(Icons.inventory_2_outlined, size: 18),
        label: Text(selectedName ?? tr('allPackages')),
        backgroundColor: value == null ? null : Theme.of(context).colorScheme.secondaryContainer,
      ),
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
