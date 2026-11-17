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

  /// Aling tab ang bukas: arriving, inResort, awaitingSurvey, completed
  StayStage _tab = StayStage.arriving;
  bool _tabTouched = false;

  /// Oras ng pagtatapos ng package para sa booking (overnight = kinabukasan).
  DateTime? _endOf(Map<String, dynamic> b) {
    final d = bookingDateOf(b);
    final pkg = widget.data.packageById(b['package_id']);
    if (d == null || pkg == null) return null;
    TimeOfDay? t(dynamic v) {
      final p = '${v ?? ''}'.split(':');
      if (p.length < 2) return null;
      return TimeOfDay(hour: int.tryParse(p[0]) ?? 0, minute: int.tryParse(p[1]) ?? 0);
    }

    final st = t(pkg['start_time']), en = t(pkg['end_time']);
    if (en == null) return null;
    final overnight = st != null && (en.hour * 60 + en.minute) <= (st.hour * 60 + st.minute);
    final day = overnight ? d.add(const Duration(days: 1)) : d;
    return DateTime(day.year, day.month, day.day, en.hour, en.minute);
  }

  bool _overstaying(Map<String, dynamic> b) {
    if (stageOf(b) != StayStage.inResort) return false;
    final end = _endOf(b);
    return end != null && DateTime.now().isAfter(end);
  }

  @override
  Widget build(BuildContext context) {
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

    List<Map<String, dynamic>> of(StayStage s) => relevant
        .where((b) => stageOf(b) == s && (s != StayStage.completed || bookingDateOf(b) == today))
        .toList();
    final lists = {
      StayStage.arriving: of(StayStage.arriving),
      StayStage.inResort: of(StayStage.inResort),
      StayStage.awaitingSurvey: of(StayStage.awaitingSurvey),
      StayStage.completed: of(StayStage.completed),
    };

    // Unang bukas: ang tab ng napiling guest, o ang unang may laman.
    final focus = _focus;
    if (focus != null && lists.containsKey(stageOf(focus))) {
      _tab = stageOf(focus);
    } else if (!_tabTouched && lists[_tab]!.isEmpty) {
      _tab = lists.entries.firstWhere((e) => e.value.isNotEmpty, orElse: () => lists.entries.first).key;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        final scanner = _scannerCard(focus);
        final guests = _guestsCard(lists, wide: constraints.maxWidth >= 700);
        return ListView(
          controller: _list,
          padding: pageInsets(context),
          children: [
            Text(tr('ciSubtitle'), style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 14),
            _overviewCard(lists, wide: constraints.maxWidth >= 700),
            const SizedBox(height: 18),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 400, child: scanner),
                  const SizedBox(width: 18),
                  Expanded(child: guests),
                ],
              )
            else ...[
              scanner,
              const SizedBox(height: 18),
              guests,
            ],
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Overview
  // ---------------------------------------------------------------------------

  Widget _overviewCard(Map<StayStage, List<Map<String, dynamic>>> lists, {required bool wide}) {
    final arriving = lists[StayStage.arriving]!;
    final inResort = lists[StayStage.inResort]!;
    final done = lists[StayStage.completed]!;
    final withBalance = arriving.where((b) => remainingOf(b) > 0.01).length;
    final over = inResort.where(_overstaying).length;
    final fees = [...done, ...lists[StayStage.awaitingSurvey]!, ...inResort]
        .fold<double>(0, (s, b) => s + asDouble(b['late_fee']));

    final tiles = [
      _tile4(tr('ciKArriving'), tr('ciKArrivingSub', {'n': withBalance}), '${arriving.length}', Colors.white, Icons.login_rounded),
      _tile4(tr('ciKInResort'), tr('ciKInResortSub', {'n': over}), '${inResort.length}', const Color(0xFF4ADE80), Icons.pool),
      _tile4(tr('ciKSurvey'), tr('ciKSurveySub'), '${lists[StayStage.awaitingSurvey]!.length}', const Color(0xFFFBBF24),
          Icons.rate_review_outlined),
      _tile4(tr('ciKDone'), tr('ciKDoneSub', {'amount': peso(fees)}), '${done.length}', Colors.white, Icons.task_alt),
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
              const Icon(Icons.today_rounded, color: AppColors.inkText, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${tr('ciOverview')} · ${formatDate(DateTime.now())}'.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.8, fontSize: 13),
                ),
              ),
              IconButton(
                tooltip: tr('lfTitle'),
                icon: const Icon(Icons.tune, color: AppColors.inkText),
                onPressed: () async {
                  if (await showLateFeeSettings(context) && mounted) showToast(context, tr('lfSaved'));
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
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

  Widget _tile4(String label, String sub, String value, Color valueColor, IconData icon) {
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
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(color: AppColors.inkText, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
              ),
              Icon(icon, size: 16, color: const Color(0xFF7F93A6)),
            ],
          ),
          const SizedBox(height: 2),
          Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF7F93A6), fontSize: 10.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: valueColor, fontSize: 24, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Scanner
  // ---------------------------------------------------------------------------

  Widget _scannerCard(Map<String, dynamic>? focus) {
    return AppCard(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('ciScanTitle'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      Text(tr('ciScanHelp'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
            if (focus != null) ...[
              const SizedBox(height: 14),
              _focusBanner(focus),
            ],
            const SizedBox(height: 14),

            // Camera
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 260,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_camera != null)
                      MobileScanner(controller: _camera!, onDetect: _onDetect)
                    else
                      Container(
                        color: AppColors.ink,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.qr_code_2_rounded, size: 64, color: Color(0xFF3B556D)),
                            const SizedBox(height: 10),
                            Text(tr('ciCameraOff'), style: const TextStyle(color: AppColors.inkText, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: _toggleCamera,
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: Text(tr('ciOpenCamera')),
                            ),
                          ],
                        ),
                      ),
                    if (_camera != null) ...[
                      // Gabay kung saan itututok ang QR
                      Center(child: _ScanFrame(size: 180)),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 12,
                        child: Text(tr('ciCameraHint'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600,
                                shadows: [Shadow(color: Colors.black54, blurRadius: 6)])),
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: IconButton.filledTonal(
                          tooltip: tr('ciCloseCamera'),
                          onPressed: _toggleCamera,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                    ],
                    if (_busy) const ColoredBox(color: Colors.black38, child: Center(child: CircularProgressIndicator())),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Pag-type ng code
            Text(tr('ciTypeCode').toUpperCase(),
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.muted)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: '7K3QM-4XPA2',
                      prefixIcon: const Icon(Icons.keyboard_outlined),
                      filled: true,
                      fillColor: AppColors.subtle,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                    onSubmitted: (v) => v.trim().isEmpty ? null : _scan(code: v),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _busy
                        ? null
                        : () {
                            if (_code.text.trim().isNotEmpty) _scan(code: _code.text);
                          },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(tr('ciCheck')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Listahan ng guest
  // ---------------------------------------------------------------------------

  Widget _guestsCard(Map<StayStage, List<Map<String, dynamic>>> lists, {required bool wide}) {
    final labels = {
      StayStage.arriving: tr('ciArriving'),
      StayStage.inResort: tr('ciInResort'),
      StayStage.awaitingSurvey: tr('ciAwaitingSurvey'),
      StayStage.completed: tr('ciCompleted'),
    };
    final list = lists[_tab] ?? const [];
    return AppCard(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(tr('ciGuestsToday'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Container(
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
                        for (final e in labels.entries)
                          _stageTab(e.value, lists[e.key]!.length, _tab == e.key,
                              () => setState(() {
                                    _tab = e.key;
                                    _tabTouched = true;
                                  })),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: EmptyState(icon: Icons.event_available_outlined, message: tr('ciNone')),
            )
          else
            for (var i = 0; i < list.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _guestRow(list[i], wide: wide),
            ],
        ],
      ),
    );
  }

  Widget _stageTab(String label, int n, bool selected, VoidCallback onTap) {
    return Material(
      color: selected ? AppColors.ink : Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.text,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 13,
                  )),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: selected ? AppColors.accent : const Color(0xFFE6EBF0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$n',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: selected ? AppColors.ink : AppColors.muted,
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String text, Color color, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
            ],
            Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _guestRow(Map<String, dynamic> b, {required bool wide}) {
    final stage = stageOf(b);
    final balance = remainingOf(b);
    final fee = asDouble(b['late_fee']);
    final pkg = widget.data.packageById(b['package_id']);
    final time = pkg == null ? '' : '${_hm(pkg['start_time'])} – ${_hm(pkg['end_time'])}';
    final over = _overstaying(b);
    final focused = '${b['id']}' == _focusId;
    final name = clientNameOf(b);
    final color = switch (stage) {
      StayStage.arriving => AppColors.info,
      StayStage.inResort => AppColors.success,
      StayStage.awaitingSurvey => AppColors.warning,
      _ => AppColors.muted,
    };

    final Widget action = switch (stage) {
      StayStage.arriving => FilledButton.icon(
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
          ? OutlinedButton.icon(
              onPressed: widget.onOpenBookings,
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: Text(tr('ciCollect', {'amount': peso(balance)})),
            )
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
                      child: Row(
                        children: [
                          const Icon(Icons.task_alt, size: 20),
                          const SizedBox(width: 12),
                          Text(tr('svSkip')),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
      _ => _pill(tr('statusCompleted'), AppColors.success, icon: Icons.check_rounded),
    };

    final info = Row(
      children: [
        CircleAvatar(
          radius: 19,
          backgroundColor: color.withValues(alpha: 0.12),
          child: Text(name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
              style: TextStyle(color: color, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(packageNameOf(b).toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.muted)),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (time.isNotEmpty) _pill(time, AppColors.muted, icon: Icons.schedule_rounded),
                  _pill(tr('paxCount', {'n': guestsOf(b)}), AppColors.muted, icon: Icons.groups_outlined),
                  if (stage == StayStage.arriving && balance > 0.01)
                    _pill(tr('ciBalanceShort', {'amount': peso(balance)}), AppColors.warning,
                        icon: Icons.account_balance_wallet_outlined),
                  if (over) _pill(tr('ciOverstay'), AppColors.danger, icon: Icons.timer_off_outlined),
                  if (fee > 0) _pill(tr('ciLateShort', {'fee': peso(fee)}), AppColors.danger, icon: Icons.alarm),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    return Container(
      color: focused ? AppColors.primary.withValues(alpha: 0.06) : (over ? const Color(0xFFFFF5F5) : null),
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      child: wide
          ? Row(
              children: [
                Expanded(child: info),
                const SizedBox(width: 12),
                action,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            ),
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

/// Mga sulok na gabay kung saan itututok ang QR.
class _ScanFrame extends StatelessWidget {
  const _ScanFrame({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    Widget corner(Alignment a) {
      final top = a.y < 0, left = a.x < 0;
      const side = BorderSide(color: Colors.white, width: 4);
      return Align(
        alignment: a,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            border: Border(
              top: top ? side : BorderSide.none,
              bottom: top ? BorderSide.none : side,
              left: left ? side : BorderSide.none,
              right: left ? BorderSide.none : side,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          corner(Alignment.topLeft),
          corner(Alignment.topRight),
          corner(Alignment.bottomLeft),
          corner(Alignment.bottomRight),
        ],
      ),
    );
  }
}
