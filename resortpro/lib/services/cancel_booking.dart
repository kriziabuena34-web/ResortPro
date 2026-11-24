import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'offline_cache.dart';

/// Pwede bang i-cancel ng guest ang booking (hindi pa nakakapasok at hindi pa lumilipas)?
bool canCancelBooking(Map<String, dynamic> b) {
  final status = '${b['status']}';
  final date = parseDate(b['booking_date']);
  final today = DateUtils.dateOnly(DateTime.now());
  return (status == 'reserved' || status == 'confirmed' || status == 'fully_paid') &&
      b['checked_in_at'] == null &&
      date != null &&
      !date.isBefore(today);
}

/// I-cancel ang booking ayon sa policy #6–#8 ng resort. Ibinabalik ang true kapag na-cancel.
Future<bool> showCancelBookingSheet(BuildContext context, Map<String, dynamic> booking) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CancelSheet(booking: booking),
  );
  return ok ?? false;
}

class _CancelSheet extends StatefulWidget {
  const _CancelSheet({required this.booking});
  final Map<String, dynamic> booking;

  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

/// Mga karaniwang dahilan ng pagkansela. Ang "Other" ay may sariling text box.
const cancelReasons = <String>[
  'Death in the family',
  'Illness or hospitalization',
  'Typhoon or severe weather',
  'Family or personal emergency',
  'Change of plans',
  'Other',
];

class _CancelSheetState extends State<_CancelSheet> {
  String? _preset;
  Map<String, dynamic>? _quote;
  String? _loadError;
  String _method = 'gcash';
  final _number = TextEditingController();
  final _name = TextEditingController();
  final _reason = TextEditingController();
  bool _agree = false;
  bool _wantRefund = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadQuote();
  }

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _loadQuote() async {
    try {
      final r = await Supabase.instance.client
          .rpc('refund_quote', params: {'p_booking_id': '${widget.booking['id']}'});
      if (!mounted) return;
      setState(() => _quote = Map<String, dynamic>.from(r as Map));
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = '$e'.contains('refund_quote')
          ? 'Cancellation is not available yet. Please contact the resort.'
          : friendlyError(e, action: 'check your refund'));
    }
  }

  double get _refund => asDouble(_quote?['refund']);

  /// Ang ipapadalang dahilan: ang napiling preset, o "Other: (tinype)".
  String get _fullReason {
    final typed = _reason.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return _preset == 'Other' ? 'Other: $typed' : (_preset ?? typed);
  }

  Future<void> _submit() async {
    final needsPayout = _refund > 0 && _wantRefund;
    if (_preset == null) {
      setState(() => _error = 'Please choose your reason for cancelling.');
      return;
    }
    if (_preset == 'Other' && _reason.text.trim().length < 5) {
      setState(() => _error = 'Please type your reason (at least 5 characters).');
      return;
    }
    final digits = _number.text.replaceAll(RegExp(r'\D'), '');
    if (needsPayout && (digits.length != 11 || !digits.startsWith('09'))) {
      setState(() => _error = 'Enter your 11-digit ${_method == 'gcash' ? 'GCash' : 'Maya'} number (starts with 09).');
      return;
    }
    if (needsPayout && _name.text.trim().length < 2) {
      setState(() => _error = 'Enter the account name for the refund.');
      return;
    }
    if (!await hasInternet()) {
      if (mounted) setState(() => _error = 'No internet connection. Please connect and try again.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc('request_cancellation', params: {
        'p_booking_id': '${widget.booking['id']}',
        'p_method': needsPayout ? _method : null,
        'p_number': needsPayout ? digits : null,
        'p_name': needsPayout ? _name.text.trim() : null,
        'p_reason': _fullReason,
        'p_request_refund': needsPayout,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e'.contains('CANNOT_CANCEL')
            ? 'This booking can no longer be cancelled in the app. Please contact the resort.'
            : '$e'.contains('REASON_REQUIRED')
                ? 'Please tell us your reason. A refund is only given for a valid reason.'
                : friendlyError(e, action: 'cancel the booking');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pkg = widget.booking['packages'] as Map<String, dynamic>?;
    final q = _quote;
    final days = q == null ? 0 : (q['days_before'] as num).toInt();
    final half = q?['eligible_half'] == true;
    final wantsRefund = _refund > 0 && _wantRefund;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Header ----
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.event_busy_rounded, color: AppColors.danger),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Cancel Booking',
                          style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.ink)),
                      Text(
                        '${pkg?['name'] ?? ''} · ${formatDate(parseDate(widget.booking['booking_date']))}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (q == null && _loadError == null)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_loadError != null)
              Text(_loadError!, style: const TextStyle(color: AppColors.danger))
            else ...[
              // ---- Buod ng refund ----
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 3))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Text('Refund summary',
                            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 14.5)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: (days == 0 ? AppColors.warning : AppColors.info).withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            days == 0 ? 'Booking is today' : '$days day${days == 1 ? '' : 's'} away',
                            style: TextStyle(
                              color: days == 0 ? AppColors.warning : AppColors.info,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _row('Verified payments', peso(asDouble(q?['paid']))),
                    _row('Reservation fee (50%)', peso(asDouble(q?['reservation_fee']))),
                    const Divider(height: 18, color: AppColors.border),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Refund if approved',
                              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                        ),
                        Text(
                          peso(_refund),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            color: _refund > 0 ? AppColors.primaryDark : AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _infoNote(
                half
                    ? 'Bookings are non-refundable unless your reason is accepted. If it is, you get back half '
                        'of the 50% reservation fee because you are cancelling before your booking date.'
                    : 'Bookings are non-refundable unless your reason is accepted. Cancelling on the booking '
                        'date itself gets no refund, even with a valid reason.',
              ),
              const SizedBox(height: 20),

              // ---- Dahilan ----
              _sectionTitle('Why are you cancelling?'),
              const SizedBox(height: 10),
              for (final r in cancelReasons) _reasonTile(r),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                child: _preset == 'Other'
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: TextField(
                          controller: _reason,
                          maxLines: 3,
                          minLines: 2,
                          maxLength: 300,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: _fieldDecoration('Type your reason', 'Tell the resort why you are cancelling'),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),

              // ---- Refund ----
              if (_refund > 0) ...[
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: _wantRefund ? AppColors.primary.withValues(alpha: 0.06) : AppColors.subtle,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: _wantRefund ? AppColors.primary.withValues(alpha: 0.35) : AppColors.border),
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _wantRefund,
                    onChanged: _busy ? null : (v) => setState(() => _wantRefund = v),
                    title: Text('Request a ${peso(_refund)} refund',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                    subtitle: const Text('The resort will review your reason first.', style: TextStyle(fontSize: 12)),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  child: wantsRefund
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 16),
                            _sectionTitle('Where should we send your refund?'),
                            const SizedBox(height: 10),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'gcash', label: Text('GCash')),
                                ButtonSegment(value: 'maya', label: Text('Maya')),
                              ],
                              selected: {_method},
                              onSelectionChanged: _busy ? null : (s) => setState(() => _method = s.first),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _number,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(11),
                              ],
                              decoration: _fieldDecoration(
                                  '${_method == 'gcash' ? 'GCash' : 'Maya'} number', '09XX XXX XXXX',
                                  icon: Icons.phone_iphone_rounded),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _name,
                              maxLength: 60,
                              textCapitalization: TextCapitalization.words,
                              decoration: _fieldDecoration('Account name', 'Name on the account',
                                      icon: Icons.person_outline_rounded)
                                  .copyWith(counterText: ''),
                            ),
                          ],
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
              const SizedBox(height: 14),

              // ---- Pagsang-ayon ----
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _busy ? null : () => setState(() => _agree = !_agree),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
                  decoration: BoxDecoration(
                    color: AppColors.subtle,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _agree,
                        onChanged: _busy ? null : (v) => setState(() => _agree = v ?? false),
                      ),
                      const Expanded(
                        child: Text(
                          'I understand that cancelling cannot be undone and follows the resort\'s refund policy.',
                          style: TextStyle(fontSize: 13, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.danger),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_error!,
                          style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => Navigator.pop(context, false),
                        child: const Text('Keep booking'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 50,
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                        onPressed: _busy || !_agree ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : FittedBox(child: Text(wantsRefund ? 'Cancel & request refund' : 'Cancel booking')),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static const _reasonIcons = <String, IconData>{
    'Death in the family': Icons.local_florist_outlined,
    'Illness or hospitalization': Icons.local_hospital_outlined,
    'Typhoon or severe weather': Icons.thunderstorm_outlined,
    'Family or personal emergency': Icons.emergency_outlined,
    'Change of plans': Icons.event_repeat_outlined,
    'Other': Icons.edit_note_rounded,
  };

  Widget _reasonTile(String r) {
    final selected = _preset == r;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.primary.withValues(alpha: 0.07) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _busy
              ? null
              : () => setState(() {
                    _preset = r;
                    _error = null;
                  }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(_reasonIcons[r] ?? Icons.help_outline, size: 20,
                    color: selected ? AppColors.primaryDark : AppColors.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(r,
                      style: TextStyle(
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: AppColors.ink,
                        fontSize: 14,
                      )),
                ),
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  size: 20,
                  color: selected ? AppColors.primary : AppColors.border,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(text,
      style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink));

  Widget _infoNote(String text) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, size: 17, color: AppColors.warning),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.text))),
          ],
        ),
      );

  InputDecoration _fieldDecoration(String label, String hint, {IconData? icon}) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon),
        filled: true,
        fillColor: AppColors.subtle,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      );

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted))),
            Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: bold ? 16 : 14)),
          ],
        ),
      );
}
