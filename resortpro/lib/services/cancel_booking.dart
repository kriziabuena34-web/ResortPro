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

class _CancelSheetState extends State<_CancelSheet> {
  Map<String, dynamic>? _quote;
  String? _loadError;
  String _method = 'gcash';
  final _number = TextEditingController();
  final _name = TextEditingController();
  final _reason = TextEditingController();
  bool _agree = false;
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

  Future<void> _submit() async {
    final needsPayout = _refund > 0;
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
        'p_reason': _reason.text.trim(),
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e'.contains('CANNOT_CANCEL')
            ? 'This booking can no longer be cancelled in the app. Please contact the resort.'
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

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Cancel booking', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text(
              '${pkg?['name'] ?? ''} · ${formatDate(parseDate(widget.booking['booking_date']))}',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            if (q == null && _loadError == null)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_loadError != null)
              Text(_loadError!, style: const TextStyle(color: AppColors.danger))
            else ...[
              // Buod ng refund ayon sa policy
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: (half ? AppColors.info : AppColors.warning).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: (half ? AppColors.info : AppColors.warning).withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      days == 0 ? 'Your booking is today.' : 'Your booking is $days day${days == 1 ? '' : 's'} away.',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      half
                          ? 'Because you are cancelling at least 5 days before your date, you get back half of '
                              'the 50% reservation fee.'
                          : 'Cancellations less than 5 days before the date do not get the 50% reservation fee back.',
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                    const Divider(height: 20),
                    _row('Verified payments', peso(asDouble(q?['paid']))),
                    _row('Reservation fee (50%)', peso(asDouble(q?['reservation_fee']))),
                    _row('Refund to you', peso(_refund), bold: true),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_refund > 0) ...[
                const Text('Where should we send your refund?', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'gcash', label: Text('GCash')),
                    ButtonSegment(value: 'maya', label: Text('Maya')),
                  ],
                  selected: {_method},
                  onSelectionChanged: _busy ? null : (s) => setState(() => _method = s.first),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _number,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
                  decoration: InputDecoration(
                    labelText: '${_method == 'gcash' ? 'GCash' : 'Maya'} number',
                    hintText: '09XX XXX XXXX',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Account name'),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: _reason,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Reason (optional)'),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _agree,
                onChanged: _busy ? null : (v) => setState(() => _agree = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'I understand that cancelling cannot be undone and follows the resort\'s refund policy.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                  onPressed: _busy || !_agree ? null : _submit,
                  child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_refund > 0 ? 'Cancel and request ${peso(_refund)} refund' : 'Cancel booking'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

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
