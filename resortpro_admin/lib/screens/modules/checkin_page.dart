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
  const CheckinPage({
    super.key,
    required this.data,
    required this.onChanged,
    required this.onOpenBookings,
    this.focusBookingId,
  });

  final AdminData data;

  /// Booking na iche-check in/out (galing sa Bookings). Kailangan pa rin ng QR o code.
  final String? focusBookingId;
  final Future<void> Function() onChanged;
  final VoidCallback onOpenBookings;

  @override
  State<CheckinPage> createState() => _CheckinPageState();
}

class _CheckinPageState extends State<CheckinPage> {
  final _code = TextEditingController();
  MobileScannerController? _camera;
  bool _busy = false;
  late String? _focusId = widget.focusBookingId;
  String? _lastScanned;
  DateTime _lastScanAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _code.dispose();
    _list.dispose();
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

  static String _norm(String v) => v.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  Map<String, dynamic>? get _focus => _focusId == null ? null : _bookingById(_focusId);

  /// Piliin ang guest na iche-check in/out; kailangan pa ring i-scan ang QR o i-type ang code.
  void _setFocus(Map<String, dynamic> b) {
    setState(() => _focusId = '${b['id']}');
    _scrollToTop();
  }

  final _list = ScrollController();

  void _scrollToTop() {
    if (_list.hasClients) {
      _list.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  /// Laging gamit ang QR o code (wala nang check-in sa pindot lang).
  Future<void> _scan({required String code}) async {
    if (_busy) return;
    final focus = _focus;
    // May napiling guest pero ibang code ang na-scan: magtanong muna.
    if (focus != null) {
      final expected = _norm('${focus['checkin_code'] ?? ''}');
      if (expected.isNotEmpty && _norm(code) != expected) {
        final go = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 40),
            title: Text(tr('ciMismatchTitle')),
            content: Text(tr('ciMismatchMsg', {'client': clientNameOf(focus)}), textAlign: TextAlign.center),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr('cancel'))),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(tr('ciMismatchGo'))),
            ],
          ),
        );
        if (go != true || !mounted) return;
      }
    }
    setState(() => _busy = true);
    try {
      final result = await CheckinService.scan(code: code);
      await widget.onChanged();
      if (!mounted) return;
      final b = _bookingById(result['booking_id']);
      _code.clear();
      setState(() => _focusId = null);
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

  /// Tapusin nang walang survey (may opsyonal na dahilan; nakatala sa history).
  Future<void> _skipSurvey(Map<String, dynamic> booking) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('svSkipQ')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('svSkipMsg', {'client': clientNameOf(booking)})),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              decoration: InputDecoration(labelText: '${tr('svSkipReason')} (${tr('optional')})'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(tr('svSkip'))),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await CheckinService.completeWithoutSurvey('${booking['id']}', reason: text.isEmpty ? null : text);
      if (!mounted) return;
      showToast(context, tr('svSkipped'));
      await widget.onChanged();
    } catch (e) {
      if (mounted) showToast(context, CheckinService.friendly(e));
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

    final focus = _focus;
    return ListView(
      controller: _list,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (focus != null) ...[
          _focusBanner(focus),
          const SizedBox(height: 12),
        ],
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
          onPressed: _busy ? null : () => _setFocus(b),
          icon: const Icon(Icons.login_rounded, size: 18),
          label: Text(tr('ciIn')),
        ),
      StayStage.inResort => FilledButton.tonalIcon(
          onPressed: _busy ? null : () => _setFocus(b),
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: Text(tr('ciOut')),
        ),
      StayStage.awaitingSurvey => balance > 0.01
          ? OutlinedButton(onPressed: widget.onOpenBookings, child: Text(tr('ciCollect', {'amount': peso(balance)})))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _survey(b),
                  icon: const Icon(Icons.rate_review_outlined, size: 18),
                  label: Text(tr('ciAnswerSurvey')),
                ),
                PopupMenuButton<String>(
                  tooltip: tr('moreActions'),
                  enabled: !_busy,
                  onSelected: (_) => _skipSurvey(b),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'skip',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.task_alt),
                        title: Text(tr('svSkip')),
                      ),
                    ),
                  ],
                ),
              ],
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

  /// Banner: kung sinong guest ang iche-check in/out.
  Widget _focusBanner(Map<String, dynamic> b) {
    final out = stageOf(b) == StayStage.inResort;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(out ? Icons.logout_rounded : Icons.login_rounded, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(out ? 'ciFocusOut' : 'ciFocusIn', {'client': clientNameOf(b)}),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text('${packageNameOf(b)} · ${tr('ciFocusHelp')}', style: const TextStyle(color: AppColors.muted)),
              ],
            ),
          ),
          IconButton(
            tooltip: tr('cancel'),
            onPressed: () => setState(() => _focusId = null),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
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
