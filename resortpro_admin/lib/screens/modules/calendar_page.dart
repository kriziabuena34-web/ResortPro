import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_widgets.dart';

/// Calendar view ng bookings: buod ng buwan, kalendaryo na may kulay ayon sa
/// oras ng package (Day / Night / Overnight), at listahan ng napiling araw.
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.data});

  final AdminData data;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

/// Uri ng oras ng package (para sa kulay sa kalendaryo).
enum _Slot { day, night, overnight }

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _month;
  late DateTime _selectedDay;

  static const _slotColors = {
    _Slot.day: Color(0xFFF59E0B),
    _Slot.night: Color(0xFF6366F1),
    _Slot.overnight: Color(0xFF0F766E),
  };

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selectedDay = DateUtils.dateOnly(now);
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  static int? _minutes(dynamic v) {
    final p = '${v ?? ''}'.split(':');
    if (p.length < 2) return null;
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }

  /// Day = may araw lang; Night = gabi; Overnight = umaga hanggang kinabukasan.
  _Slot _slotOf(Map<String, dynamic> b) {
    final pkg = widget.data.packageById(b['package_id']);
    final st = _minutes(pkg?['start_time']), en = _minutes(pkg?['end_time']);
    if (st == null || en == null) return _Slot.day;
    if (st >= 17 * 60) return _Slot.night;
    if (en <= st) return _Slot.overnight;
    return _Slot.day;
  }

  String _timeOf(Map<String, dynamic> b) {
    final pkg = widget.data.packageById(b['package_id']);
    String hm(dynamic t) {
      final m = _minutes(t);
      if (m == null) return '';
      var h = m ~/ 60;
      final pm = h >= 12;
      h = h % 12 == 0 ? 12 : h % 12;
      return '$h:${(m % 60).toString().padLeft(2, '0')} ${pm ? 'PM' : 'AM'}';
    }

    if (pkg == null) return '';
    return '${hm(pkg['start_time'])} – ${hm(pkg['end_time'])}';
  }

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());

    // Mga aktibong booking ayon sa petsa
    final byDay = <DateTime, List<Map<String, dynamic>>>{};
    for (final b in widget.data.activeBookings) {
      final d = bookingDateOf(b);
      if (d == null) continue;
      byDay.putIfAbsent(d, () => []).add(b);
    }
    for (final list in byDay.values) {
      list.sort((a, b) => (_minutes(widget.data.packageById(a['package_id'])?['start_time']) ?? 0)
          .compareTo(_minutes(widget.data.packageById(b['package_id'])?['start_time']) ?? 0));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;
        final calendar = _calendarCard(byDay, today, roomy: constraints.maxWidth >= 700);
        final day = _dayCard(byDay[_selectedDay] ?? const [], today);
        return ListView(
          padding: pageInsets(context),
          children: [
            Text(tr('calSubtitle'), style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 14),
            _overviewCard(byDay, today, wide: constraints.maxWidth >= 700),
            const SizedBox(height: 18),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: calendar),
                  const SizedBox(width: 18),
                  Expanded(flex: 2, child: day),
                ],
              )
            else ...[
              calendar,
              const SizedBox(height: 18),
              day,
            ],
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Buod ng buwan
  // ---------------------------------------------------------------------------

  Widget _overviewCard(Map<DateTime, List<Map<String, dynamic>>> byDay, DateTime today, {required bool wide}) {
    final inMonth = byDay.entries.where((e) => e.key.year == _month.year && e.key.month == _month.month).toList();
    final bookings = inMonth.fold<int>(0, (s, e) => s + e.value.length);
    final guests = inMonth.fold<int>(0, (s, e) => s + e.value.fold<int>(0, (g, b) => g + guestsOf(b)));
    final value = inMonth.fold<double>(0, (s, e) => s + e.value.fold<double>(0, (v, b) => v + totalOf(b)));
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    var openDays = 0;
    for (var d = 1; d <= days; d++) {
      final blocks = widget.data.blocksOn(DateTime(_month.year, _month.month, d));
      if (!blocks.any((b) => b['package_id'] == null)) openDays++;
    }
    final bookedDays = inMonth.length;
    final pct = openDays == 0 ? 0 : (bookedDays / openDays * 100).round();

    final tiles = [
      _tile(tr('calKBookings'), tr('calKBookingsSub'), '$bookings', Colors.white, Icons.event_note_outlined),
      _tile(tr('calKDays'), tr('calKDaysSub', {'p': pct, 'n': openDays}), '$bookedDays', const Color(0xFF4ADE80),
          Icons.calendar_today_outlined),
      _tile(tr('calKGuests'), tr('calKGuestsSub'), '$guests', Colors.white, Icons.groups_outlined),
      _tile(tr('calKValue'), tr('calKValueSub'), peso(value), const Color(0xFFFBBF24), Icons.payments_outlined),
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
          // Pagpili ng buwan
          Row(
            children: [
              IconButton(
                tooltip: tr('prevMonth'),
                onPressed: () => _changeMonth(-1),
                icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
              ),
              Expanded(
                child: Text(
                  '${monthNamesTr[_month.month - 1]} ${_month.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ),
              IconButton(
                tooltip: tr('nextMonth'),
                onPressed: () => _changeMonth(1),
                icon: const Icon(Icons.chevron_right_rounded, color: Colors.white),
              ),
              const SizedBox(width: 4),
              OutlinedButton(
                onPressed: () => setState(() {
                  _month = DateTime(today.year, today.month);
                  _selectedDay = today;
                }),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: AppColors.inkLine),
                ),
                child: Text(tr('today')),
              ),
            ],
          ),
          const SizedBox(height: 12),
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

  Widget _tile(String label, String sub, String value, Color valueColor, IconData icon) {
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
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(color: valueColor, fontSize: 22, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Kalendaryo
  // ---------------------------------------------------------------------------

  Widget _calendarCard(Map<DateTime, List<Map<String, dynamic>>> byDay, DateTime today, {required bool roomy}) {
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    final offset = DateTime(_month.year, _month.month, 1).weekday % 7; // Linggo = 0
    final cellCount = ((offset + daysInMonth) / 7).ceil() * 7;

    return AppCard(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Center(
                      child: Text(
                        weekdaysTr[i].toUpperCase(),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: i == 0 || i == 6 ? AppColors.primary : AppColors.muted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: roomy ? 1.05 : 0.78,
              children: [
                for (var i = 0; i < cellCount; i++)
                  _dayCell(i - offset + 1, daysInMonth, byDay, today, roomy: roomy),
              ],
            ),
            const SizedBox(height: 14),
            // Legend
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _legend(_slotColors[_Slot.day]!, tr('calLegendDay')),
                _legend(_slotColors[_Slot.night]!, tr('calLegendNight')),
                _legend(_slotColors[_Slot.overnight]!, tr('calLegendOvernight')),
                _legend(AppColors.danger, tr('calBlocked'), icon: Icons.block),
                _legend(AppColors.primary, tr('today'), outline: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(Color color, String label, {IconData? icon, bool outline = false}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 14, color: color)
          else
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: outline ? null : color,
                border: outline ? Border.all(color: color, width: 2) : null,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.muted, fontWeight: FontWeight.w600)),
        ],
      );

  Widget _dayCell(
    int day,
    int daysInMonth,
    Map<DateTime, List<Map<String, dynamic>>> byDay,
    DateTime today, {
    required bool roomy,
  }) {
    if (day < 1 || day > daysInMonth) return const SizedBox.shrink();

    final date = DateTime(_month.year, _month.month, day);
    final list = byDay[date] ?? const [];
    final isSelected = date == _selectedDay;
    final isToday = date == today;
    final isPast = date.isBefore(today);
    final blocks = widget.data.blocksOn(date);
    final wholeBlocked = blocks.any((b) => b['package_id'] == null);

    final bg = isSelected
        ? AppColors.primary.withValues(alpha: 0.10)
        : wholeBlocked
            ? const Color(0xFFFDECEC)
            : list.isNotEmpty
                ? const Color(0xFFF4F7F9)
                : Colors.white;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _selectedDay = date),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : blocks.isNotEmpty
                      ? AppColors.danger.withValues(alpha: 0.45)
                      : AppColors.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: isToday
                        ? const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)
                        : null,
                    child: Text(
                      '$day',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isToday || list.isNotEmpty ? FontWeight.w800 : FontWeight.w600,
                        color: isToday ? Colors.white : (isPast ? AppColors.muted : AppColors.text),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (blocks.isNotEmpty) const Icon(Icons.block, size: 13, color: AppColors.danger),
                ],
              ),
              const Spacer(),
              if (list.isNotEmpty)
                roomy
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final b in list.take(2))
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: _slotColors[_slotOf(b)]!.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border(left: BorderSide(color: _slotColors[_slotOf(b)]!, width: 3)),
                              ),
                              child: Text(
                                clientNameOf(b),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                              ),
                            ),
                          if (list.length > 2)
                            Text('+${list.length - 2}',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.muted)),
                        ],
                      )
                    : Wrap(
                        spacing: 3,
                        runSpacing: 3,
                        children: [
                          for (final b in list.take(4))
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(color: _slotColors[_slotOf(b)], shape: BoxShape.circle),
                            ),
                        ],
                      ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Napiling araw
  // ---------------------------------------------------------------------------

  Widget _dayCard(List<Map<String, dynamic>> bookings, DateTime today) {
    final blocks = widget.data.blocksOn(_selectedDay);
    final weekday = weekdaysTr[_selectedDay.weekday % 7];
    final guests = bookings.fold<int>(0, (s, b) => s + guestsOf(b));

    return AppCard(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            color: AppColors.subtle,
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 56,
                  decoration: BoxDecoration(
                    color: _selectedDay == today ? AppColors.primary : AppColors.ink,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(weekday.toUpperCase(),
                          style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w800)),
                      Text('${_selectedDay.day}',
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(formatDate(_selectedDay), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(
                        '${tr('bookingsCount', {'n': bookings.length})} · ${tr('paxCount', {'n': guests})}',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final b in blocks)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFDECEC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.block, color: AppColors.danger, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('calBlocked'), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.danger)),
                        Text(
                          '${b['package_id'] == null ? tr('avAllPackages') : '${widget.data.packageById(b['package_id'])?['name'] ?? ''}'}'
                          '${'${b['reason'] ?? ''}'.isEmpty ? '' : ' · ${b['reason']}'}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (bookings.isEmpty && blocks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: EmptyState(icon: Icons.event_available_outlined, message: tr('noBookingDay')),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                children: [
                  for (final b in bookings) ...[
                    _bookingTile(b),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _bookingTile(Map<String, dynamic> b) {
    final color = _slotColors[_slotOf(b)]!;
    final time = _timeOf(b);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            packageNameOf(b).toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.muted),
                          ),
                        ),
                        StatusChip(status: b['status'] as String?),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(clientNameOf(b), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        if (time.isNotEmpty) _meta(Icons.schedule_rounded, time),
                        _meta(Icons.groups_outlined, tr('paxCount', {'n': guestsOf(b)})),
                        if (b['event_type'] != null) _meta(Icons.celebration_outlined, '${b['event_type']}'),
                        if (remainingOf(b) > 0.01)
                          _meta(Icons.account_balance_wallet_outlined, tr('balanceAmount', {'amount': peso(remainingOf(b))}),
                              color: AppColors.warning),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text, {Color? color}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color ?? AppColors.muted),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12.5, color: color ?? AppColors.muted, fontWeight: FontWeight.w600)),
        ],
      );
}
