import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import 'admin_data.dart';

/// Yugto ng booking sa araw ng stay.
enum StayStage { arriving, inResort, awaitingSurvey, completed, other }

StayStage stageOf(Map<String, dynamic> b) {
  final status = '${b['status']}';
  if (status == 'completed') return StayStage.completed;
  if (b['checked_out_at'] != null) return StayStage.awaitingSurvey;
  if (b['checked_in_at'] != null || status == 'checked_in') return StayStage.inResort;
  if (status == 'confirmed' || status == 'fully_paid') return StayStage.arriving;
  return StayStage.other;
}

/// QR check-in / check-out (tingnan ang PART 8 ng supabase/admin_setup.sql).
class CheckinService {
  CheckinService._();

  static SupabaseClient get _db => Supabase.instance.client;

  /// I-scan ang code (o ang booking id). Ibinabalik ang resulta mula sa server.
  static Future<Map<String, dynamic>> scan({String? code, String? bookingId}) async {
    final r = await _db.rpc('booking_scan', params: {
      'p_code': code ?? '',
      'p_booking_id': bookingId,
    });
    return Map<String, dynamic>.from(r as Map);
  }

  static Future<void> submitSurvey(
    String bookingId, {
    required int overall,
    int? cleanliness,
    int? staff,
    int? facilities,
    String? comments,
  }) async {
    await _db.rpc('submit_booking_survey', params: {
      'p_booking_id': bookingId,
      'p_overall': overall,
      'p_cleanliness': cleanliness,
      'p_staff': staff,
      'p_facilities': facilities,
      'p_comments': comments,
    });
  }

  static Future<Map<String, dynamic>> settings() async {
    final r = await _db.from('resort_settings').select().eq('id', 1).maybeSingle();
    return r ?? {'late_fee_per_hour': 500, 'late_grace_minutes': 15};
  }

  static Future<void> saveSettings({required double perHour, required int graceMinutes}) async {
    final updated = await _db
        .from('resort_settings')
        .update({
          'late_fee_per_hour': perHour,
          'late_grace_minutes': graceMinutes,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', 1)
        .select('id');
    if ((updated as List).isEmpty) throw Exception('NOT_SAVED');
  }

  /// Malinaw na mensahe para sa staff.
  static String friendly(Object e) {
    final t = '$e';
    final due = RegExp(r'BALANCE_DUE:([0-9.]+)').firstMatch(t);
    if (due != null) return tr('ciErrBalance', {'amount': peso(double.tryParse(due.group(1)!) ?? 0)});
    final early = RegExp(r'TOO_EARLY:([0-9-]+)').firstMatch(t);
    if (early != null) return tr('ciErrEarly', {'date': formatDate(DateTime.tryParse(early.group(1)!))});
    if (t.contains('CODE_NOT_FOUND')) return tr('ciErrNotFound');
    if (t.contains('NOT_CONFIRMED')) return tr('ciErrNotConfirmed');
    if (t.contains('BOOKING_INACTIVE')) return tr('ciErrInactive');
    if (t.contains('BOOKING_ENDED')) return tr('ciErrEnded');
    if (t.contains('NOT_CHECKED_OUT')) return tr('ciErrNotOut');
    if (t.contains('ALREADY_ANSWERED')) return tr('ciErrAnswered');
    if (t.contains('NOT_ADMIN')) return tr('notAdmin');
    if (t.contains('booking_scan') || t.contains('submit_booking_survey') || t.contains('resort_settings')) {
      return tr('ciErrSetup');
    }
    return tr('failed', {'e': e});
  }
}

/// Resulta ng scan: IN, OUT (may multa?), o naghihintay ng survey.
Future<void> showScanResult(
  BuildContext context, {
  required Map<String, dynamic> result,
  Map<String, dynamic>? booking,
  VoidCallback? onSurvey,
}) {
  final action = '${result['action']}';
  final lateMin = asInt(result['late_minutes']);
  final fee = asDouble(result['late_fee']);
  final balance = asDouble(result['balance']);

  final (IconData icon, Color color, String title) = switch (action) {
    'checked_in' => (Icons.login_rounded, AppColors.success, tr('ciResultIn')),
    'checked_out' => (Icons.logout_rounded, fee > 0 ? AppColors.warning : AppColors.success, tr('ciResultOut')),
    'completed' => (Icons.task_alt, AppColors.success, tr('ciResultDone')),
    _ => (Icons.rate_review_outlined, AppColors.info, tr('ciResultSurvey')),
  };

  return showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(icon, color: color, size: 40),
      title: Text(title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (booking != null) ...[
              Text(clientNameOf(booking),
                  textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text('${packageNameOf(booking)} · ${formatDate(bookingDateOf(booking))}',
                  textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 12),
            ],
            if (action == 'checked_out' || action == 'awaiting_survey') ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (fee > 0 ? AppColors.warning : AppColors.success).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  fee > 0 ? tr('ciLate', {'min': lateMin, 'fee': peso(fee)}) : tr('ciOnTime'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700, color: fee > 0 ? AppColors.warning : AppColors.success),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                balance > 0.01 ? tr('ciPayFirst', {'amount': peso(balance)}) : tr('ciSurveyNext'),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('rcClose'))),
        if (onSurvey != null && (action == 'checked_out' || action == 'awaiting_survey') && balance <= 0.01)
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              onSurvey();
            },
            icon: const Icon(Icons.rate_review_outlined),
            label: Text(tr('ciAnswerSurvey')),
          ),
      ],
    ),
  );
}

/// Survey bago ang huling check-out (sinasagutan ng staff kasama ang guest).
Future<bool> showSurveyDialog(BuildContext context, Map<String, dynamic> booking) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SurveyDialog(booking: booking),
  );
  return ok ?? false;
}

class _SurveyDialog extends StatefulWidget {
  const _SurveyDialog({required this.booking});
  final Map<String, dynamic> booking;

  @override
  State<_SurveyDialog> createState() => _SurveyDialogState();
}

class _SurveyDialogState extends State<_SurveyDialog> {
  final _ratings = <String, int>{'overall': 0, 'cleanliness': 0, 'staff': 0, 'facilities': 0};
  final _comments = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _comments.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_ratings['overall'] == 0) {
      setState(() => _error = tr('svErrOverall'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    int? v(String k) => _ratings[k] == 0 ? null : _ratings[k];
    try {
      await CheckinService.submitSurvey(
        '${widget.booking['id']}',
        overall: _ratings['overall']!,
        cleanliness: v('cleanliness'),
        staff: v('staff'),
        facilities: v('facilities'),
        comments: _comments.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = CheckinService.friendly(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('svTitle')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${clientNameOf(widget.booking)} · ${packageNameOf(widget.booking)}',
                  style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 12),
              for (final k in _ratings.keys) ...[
                Text(tr('sv_$k') + (k == 'overall' ? ' *' : ''), style: const TextStyle(fontWeight: FontWeight.w600)),
                Row(
                  children: [
                    for (var i = 1; i <= 5; i++)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: _saving ? null : () => setState(() => _ratings[k] = i),
                        icon: Icon(
                          i <= _ratings[k]! ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: AppColors.accent,
                          size: 30,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
              TextField(
                controller: _comments,
                maxLines: 3,
                decoration: InputDecoration(labelText: '${tr('sv_comments')} (${tr('optional')})'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: Text(tr('cancel'))),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(tr('svSubmit')),
        ),
      ],
    );
  }
}

/// Patakaran sa multa sa late na check-out.
Future<bool> showLateFeeSettings(BuildContext context) async {
  final ok = await showDialog<bool>(context: context, builder: (_) => const _LateFeeDialog());
  return ok ?? false;
}

class _LateFeeDialog extends StatefulWidget {
  const _LateFeeDialog();

  @override
  State<_LateFeeDialog> createState() => _LateFeeDialogState();
}

class _LateFeeDialogState extends State<_LateFeeDialog> {
  final _perHour = TextEditingController();
  final _grace = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    CheckinService.settings().then((s) {
      if (!mounted) return;
      setState(() {
        _perHour.text = asDouble(s['late_fee_per_hour']).toStringAsFixed(0);
        _grace.text = '${asInt(s['late_grace_minutes'])}';
        _loading = false;
      });
    }).catchError((Object e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = CheckinService.friendly(e);
      });
    });
  }

  @override
  void dispose() {
    _perHour.dispose();
    _grace.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final perHour = double.tryParse(_perHour.text.trim());
    final grace = int.tryParse(_grace.text.trim());
    if (perHour == null || perHour < 0 || grace == null || grace < 0) {
      setState(() => _error = tr('invalidPrice'));
      return;
    }
    setState(() => _saving = true);
    try {
      await CheckinService.saveSettings(perHour: perHour, graceMinutes: grace);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = CheckinService.friendly(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('lfTitle')),
      content: SizedBox(
        width: 380,
        child: _loading
            ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(tr('lfHelp'), style: const TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _perHour,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: tr('lfPerHour'), prefixText: '₱ '),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _grace,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: tr('lfGrace'), suffixText: 'min'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.danger)),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: Text(tr('cancel'))),
        FilledButton(onPressed: _saving || _loading ? null : _save, child: Text(tr('save'))),
      ],
    );
  }
}
