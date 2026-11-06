import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'offline_cache.dart';

/// Hal. 7K3QM-4XPA2
String checkinCodeLabel(String code) =>
    code.length == 10 ? '${code.substring(0, 5)}-${code.substring(5)}' : code;

/// Pwede bang ipakita ang QR (confirmed, bayad na, o nasa resort pa)?
bool canShowCheckinQr(Map<String, dynamic> b) {
  final code = '${b['checkin_code'] ?? ''}';
  final status = '${b['status']}';
  return code.isNotEmpty &&
      b['checked_out_at'] == null &&
      (status == 'confirmed' || status == 'fully_paid' || status == 'checked_in');
}

/// Naka-out na pero hindi pa nasasagutan ang survey.
bool needsCheckoutSurvey(Map<String, dynamic> b) =>
    b['checked_out_at'] != null && '${b['status']}' != 'completed';

/// QR na ipapakita sa staff pagdating at pag-alis. Gumagana kahit offline.
Future<void> showCheckinQr(BuildContext context, Map<String, dynamic> booking) {
  final code = '${booking['checkin_code']}';
  final inside = booking['checked_in_at'] != null;
  final pkg = booking['packages'] as Map<String, dynamic>?;
  return showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(inside ? 'Check-out QR' : 'Check-in QR', textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${pkg?['name'] ?? ''} · ${formatDate(parseDate(booking['booking_date']))}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: QrImageView(data: code, version: QrVersions.auto, size: 220, backgroundColor: Colors.white),
          ),
          const SizedBox(height: 12),
          SelectableText(
            checkinCodeLabel(code),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 2),
          ),
          const SizedBox(height: 8),
          Text(
            inside
                ? 'Show this to the staff when you leave. Checking out more than 10 minutes after your package '
                    'time is charged ₱500 per hour.'
                : 'Show this to the staff when you arrive. Your balance must be paid before check-in.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        ],
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Done')),
      ],
    ),
  );
}

/// Check-out survey ng guest. Ibinabalik ang true kapag naisumite.
Future<bool> showGuestSurvey(BuildContext context, Map<String, dynamic> booking) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SurveySheet(booking: booking),
  );
  return ok ?? false;
}

class _SurveySheet extends StatefulWidget {
  const _SurveySheet({required this.booking});
  final Map<String, dynamic> booking;

  @override
  State<_SurveySheet> createState() => _SurveySheetState();
}

class _SurveySheetState extends State<_SurveySheet> {
  static const _questions = {
    'overall': 'Overall experience *',
    'cleanliness': 'Cleanliness',
    'staff': 'Staff service',
    'facilities': 'Facilities',
  };
  final _ratings = <String, int>{'overall': 0, 'cleanliness': 0, 'staff': 0, 'facilities': 0};
  final _comments = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _comments.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_ratings['overall'] == 0) {
      setState(() => _error = 'Please rate your overall experience.');
      return;
    }
    if (!await hasInternet()) {
      if (mounted) setState(() => _error = 'No internet connection. Please connect and try again.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    int? v(String k) => _ratings[k] == 0 ? null : _ratings[k];
    try {
      await Supabase.instance.client.rpc('submit_booking_survey', params: {
        'p_booking_id': '${widget.booking['id']}',
        'p_overall': _ratings['overall'],
        'p_cleanliness': v('cleanliness'),
        'p_staff': v('staff'),
        'p_facilities': v('facilities'),
        'p_comments': _comments.text,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final t = '$e';
      final due = RegExp(r'BALANCE_DUE:([0-9.]+)').firstMatch(t);
      setState(() {
        _saving = false;
        _error = due != null
            ? 'Please settle your remaining balance of ${peso(double.tryParse(due.group(1)!) ?? 0)} '
                '(including any late fee) at the counter first.'
            : t.contains('ALREADY_ANSWERED')
                ? 'You already answered this survey. Thank you!'
                : t.contains('NOT_CHECKED_OUT')
                    ? 'Please check out with the staff first.'
                    : friendlyError(e, action: 'send the survey');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fee = asDouble(widget.booking['late_fee']);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Check-out survey', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
              'Thank you for staying with us! Answer this short survey to finish your check-out.',
              style: TextStyle(color: AppColors.muted),
            ),
            if (fee > 0) ...[
              const SizedBox(height: 10),
              Text(
                'Late check-out fee: ${peso(fee)} (pay at the counter if not yet paid).',
                style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 12),
            for (final e in _questions.entries) ...[
              Text(e.value, style: const TextStyle(fontWeight: FontWeight.w600)),
              Row(
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      onPressed: _saving ? null : () => setState(() => _ratings[e.key] = i),
                      icon: Icon(
                        i <= _ratings[e.key]! ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: AppColors.accent,
                        size: 32,
                      ),
                    ),
                ],
              ),
            ],
            TextField(
              controller: _comments,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Comments or suggestions (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Submit and check out'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
