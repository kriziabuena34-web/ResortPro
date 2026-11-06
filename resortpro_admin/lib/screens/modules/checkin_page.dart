import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../services/checkin_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_widgets.dart';

/// Check-in / Check-out sa pamamagitan ng QR (o pag-type ng code),
/// at listahan ng mga guest ngayong araw.
class CheckinPage extends StatefulWidget {
  const CheckinPage({super.key, required this.data, required this.onChanged, required this.onOpenBookings});

  final AdminData data;
  final Future<void> Function() onChanged;
  final VoidCallback onOpenBookings;

  @override
  State<CheckinPage> createState() => _CheckinPageState();
}

class _CheckinPageState extends State<CheckinPage> {
  final _code = TextEditingController();
  MobileScannerController? _camera;
  bool _busy = false;
  String? _lastScanned;
  DateTime _lastScanAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _code.dispose();
    _camera?.dispose();
    super.dispose();
  }

  void _toggleCamera() {
    setState(() {
      if (_camera == null) {
        _camera = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
      } else {
        _camera!.dispose();
        _camera = null;
      }
    });
  }

  void _onDetect(BarcodeCapture capture) {
    final value = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (value == null || value.isEmpty || _busy) return;
    // Iwas sa paulit-ulit na pagbasa ng parehong QR.
    final now = DateTime.now();
    if (value == _lastScanned && now.difference(_lastScanAt) < const Duration(seconds: 5)) return;
    _lastScanned = value;
    _lastScanAt = now;
    _scan(code: value);
  }

  Map<String, dynamic>? _bookingById(dynamic id) {
    for (final b in widget.data.bookings) {
      if ('${b['id']}' == '$id') return b;
    }
    return null;
  }

  Future<void> _scan({String? code, Map<String, dynamic>? booking}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await CheckinService.scan(code: code, bookingId: booking == null ? null : '${booking['id']}');
      await widget.onChanged();
      if (!mounted) return;
      final b = _bookingById(result['booking_id']) ?? booking;
      _code.clear();
      await showScanResult(
        context,
        result: result,
        booking: b,
        onSurvey: b == null ? null : () => _survey(b),
      );
    } catch (e) {
      if (!mounted) return;
      final message = CheckinService.friendly(e);
      final balanceDue = '$e'.contains('BALANCE_DUE');
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(balanceDue ? Icons.payments_outlined : Icons.error_outline,
              color: balanceDue ? AppColors.warning : AppColors.danger, size: 40),
          title: Text(balanceDue ? tr('ciBalanceTitle') : tr('ciErrTitle')),
          content: Text(message, textAlign: TextAlign.center),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('rcClose'))),
            if (balanceDue)
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  widget.onOpenBookings();
                },
                icon: const Icon(Icons.event_note),
                label: Text(tr('ciGoBookings')),
              ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _survey(Map<String, dynamic> booking) async {
    final done = await showSurveyDialog(context, booking);
    if (!done || !mounted) return;
    showToast(context, tr('svDone'));
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));

    // Ngayong araw (kasama ang overnight kahapon na hindi pa naka-out).
    final relevant = widget.data.bookings.where((b) {
      final d = bookingDateOf(b);
      final stage = stageOf(b);
      if (d == today) return stage != StayStage.other;
      if (d == yesterday) return stage == StayStage.inResort || stage == StayStage.awaitingSurvey;
      return stage == StayStage.awaitingSurvey || stage == StayStage.inResort;
    }).toList();

    List<Map<String, dynamic>> of(StayStage s) => relevant.where((b) => stageOf(b) == s).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        SectionCard(
          title: tr('ciScanTitle'),
          subtitle: tr('ciScanHelp'),
          trailing: IconButton(
            tooltip: tr('lfTitle'),
            icon: const Icon(Icons.tune),
            onPressed: () async {
              if (await showLateFeeSettings(context) && context.mounted) showToast(context, tr('lfSaved'));
            },
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_camera != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: 280,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          MobileScanner(controller: _camera!, onDetect: _onDetect),
                          // Gabay kung saan itututok ang QR
                          Center(
                            child: Container(
                              width: 190,
                              height: 190,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white, width: 3),
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                          if (_busy) const ColoredBox(color: Colors.black38, child: Center(child: CircularProgressIndicator())),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _toggleCamera,
                  icon: Icon(_camera == null ? Icons.qr_code_scanner : Icons.videocam_off_outlined),
                  label: Text(_camera == null ? tr('ciOpenCamera') : tr('ciCloseCamera')),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _code,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: tr('ciTypeCode'),
                          hintText: 'e.g. 7K3QM-4XPA2',
                          prefixIcon: const Icon(Icons.keyboard_outlined),
                          isDense: true,
                        ),
                        onSubmitted: (v) => v.trim().isEmpty ? null : _scan(code: v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () {
                              if (_code.text.trim().isNotEmpty) _scan(code: _code.text);
                            },
                      child: Text(tr('ciCheck')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _group(theme, tr('ciArriving'), Icons.login_rounded, AppColors.info, of(StayStage.arriving)),
        _group(theme, tr('ciInResort'), Icons.pool, AppColors.success, of(StayStage.inResort)),
        _group(theme, tr('ciAwaitingSurvey'), Icons.rate_review_outlined, AppColors.warning, of(StayStage.awaitingSurvey)),
        _group(theme, tr('ciCompleted'), Icons.task_alt, AppColors.muted,
            of(StayStage.completed).where((b) => bookingDateOf(b) == today).toList()),
      ],
    );
  }

  Widget _group(ThemeData theme, String title, IconData icon, Color color, List<Map<String, dynamic>> list) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SectionCard(
        title: '$title (${list.length})',
        trailing: Icon(icon, color: color),
        child: list.isEmpty
            ? Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
                child: Text(tr('ciNone'), style: const TextStyle(color: AppColors.muted)),
              )
            : Column(
                children: [
                  for (final b in list) _tile(b),
                  const SizedBox(height: 8),
                ],
              ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> b) {
    final stage = stageOf(b);
    final balance = remainingOf(b);
    final fee = asDouble(b['late_fee']);
    final pkg = widget.data.packageById(b['package_id']);
    final time = pkg == null ? '' : '${_hm(pkg['start_time'])} – ${_hm(pkg['end_time'])}';

    final Widget? action = switch (stage) {
      StayStage.arriving => FilledButton.tonalIcon(
          onPressed: _busy ? null : () => _scan(booking: b),
          icon: const Icon(Icons.login_rounded, size: 18),
          label: Text(tr('ciIn')),
        ),
      StayStage.inResort => FilledButton.tonalIcon(
          onPressed: _busy ? null : () => _scan(booking: b),
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: Text(tr('ciOut')),
        ),
      StayStage.awaitingSurvey => balance > 0.01
          ? OutlinedButton(onPressed: widget.onOpenBookings, child: Text(tr('ciCollect', {'amount': peso(balance)})))
          : FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _survey(b),
              icon: const Icon(Icons.rate_review_outlined, size: 18),
              label: Text(tr('ciAnswerSurvey')),
            ),
      _ => null,
    };

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 2),
      title: Text(clientNameOf(b), style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text([
        packageNameOf(b),
        if (time.isNotEmpty) time,
        if (stage == StayStage.arriving && balance > 0.01) tr('ciBalanceShort', {'amount': peso(balance)}),
        if (fee > 0) tr('ciLateShort', {'fee': peso(fee)}),
      ].join(' · ')),
      trailing: action,
    );
  }

  static String _hm(dynamic t) {
    final parts = '${t ?? ''}'.split(':');
    if (parts.length < 2) return '';
    var h = int.tryParse(parts[0]) ?? 0;
    final m = parts[1];
    final pm = h >= 12;
    h = h % 12 == 0 ? 12 : h % 12;
    return '$h:$m ${pm ? 'PM' : 'AM'}';
  }
}
