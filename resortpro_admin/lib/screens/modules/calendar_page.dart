import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../widgets/admin_widgets.dart';

/// Calendar view ng bookings: makikita kung aling araw ang may booking.
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.data});

  final AdminData data;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _month;
  late DateTime _selectedDay;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateUtils.dateOnly(DateTime.now());

    // Group active bookings by date
    final byDay = <DateTime, List<Map<String, dynamic>>>{};
    for (final b in widget.data.activeBookings) {
      final d = bookingDateOf(b);
      if (d == null) continue;
      byDay.putIfAbsent(d, () => []).add(b);
    }

    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    final offset = DateTime(_month.year, _month.month, 1).weekday % 7; // Sunday = 0
    final cellCount = ((offset + daysInMonth) / 7).ceil() * 7;

    final monthBookings = byDay.entries
        .where((e) => e.key.year == _month.year && e.key.month == _month.month)
        .fold<int>(0, (s, e) => s + e.value.length);

    final selectedBookings = byDay[_selectedDay] ?? [];

    final monthCard = SectionCard(
              title: '${monthNames[_month.month - 1]} ${_month.year}',
              subtitle: tr('calMonthCount', {'n': monthBookings}),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: tr('prevMonth'),
                    onPressed: () => _changeMonth(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _month = DateTime(today.year, today.month);
                      _selectedDay = today;
                    }),
                    child: Text(tr('today')),
                  ),
                  IconButton(
                    tooltip: tr('nextMonth'),
                    onPressed: () => _changeMonth(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      for (final w in weekdaysTr)
                        Expanded(
                          child: Center(
                            child: Text(
                              w,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 7,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    childAspectRatio: 1.0,
                    children: [
                      for (var i = 0; i < cellCount; i++)
                        _buildDayCell(i - offset + 1, daysInMonth, byDay, today),
                    ],
                  ),
                ],
              ),
            );
    final dayCard = SectionCard(
              title: formatDate(_selectedDay),
              subtitle: tr('bookingsCount', {'n': selectedBookings.length}),
              child: selectedBookings.isEmpty && widget.data.blocksOn(_selectedDay).isNotEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final b in widget.data.blocksOn(_selectedDay))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.block, color: Theme.of(context).colorScheme.error),
                            title: Text(tr('calBlocked')),
                            subtitle: Text(
                              '${b['package_id'] == null ? tr('avAllPackages') : '${widget.data.packageById(b['package_id'])?['name'] ?? ''}'}'
                              '${'${b['reason'] ?? ''}'.isEmpty ? '' : ' · ${b['reason']}'}',
                            ),
                          ),
                      ],
                    )
                  : selectedBookings.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(tr('noBookingDay')),
                    )
                  : Column(
                      children: [
                        for (final b in selectedBookings)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: statusColor(b['status'] as String?).withValues(alpha: 0.15),
                              child: Icon(Icons.event, color: statusColor(b['status'] as String?)),
                            ),
                            title: Text(packageNameOf(b)),
                            subtitle: Text(
                              '${clientNameOf(b)} · ${tr('paxCount', {'n': guestsOf(b)})}'
                              '${b['event_type'] != null ? ' · ${b['event_type']}' : ''}',
                            ),
                            trailing: StatusChip(status: b['status'] as String?),
                          ),
                      ],
                    ),
            );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;
        return ListView(
          padding: pageInsets(context),
          children: [
            if (wide)
              EqualHeightRow(flex: const [3, 2], children: [monthCard, dayCard])
            else ...[
              monthCard,
              const SizedBox(height: 16),
              dayCard,
            ],
          ],
        );
      },
    );
  }

  Widget _buildDayCell(
    int day,
    int daysInMonth,
    Map<DateTime, List<Map<String, dynamic>>> byDay,
    DateTime today,
  ) {
    if (day < 1 || day > daysInMonth) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final date = DateTime(_month.year, _month.month, day);
    final count = byDay[date]?.length ?? 0;
    final isSelected = date == _selectedDay;
    final isToday = date == today;
    final blocks = widget.data.blocksOn(date);
    final wholeResortBlocked = blocks.any((b) => b['package_id'] == null);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _selectedDay = date),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary
              : wholeResortBlocked
                  ? theme.colorScheme.errorContainer
                  : count > 0
                      ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
                      : null,
          borderRadius: BorderRadius.circular(10),
          border: isToday && !isSelected
              ? Border.all(color: theme.colorScheme.primary, width: 1.5)
              : blocks.isNotEmpty && !wholeResortBlocked
                  ? Border.all(color: theme.colorScheme.error, width: 1.2)
                  : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                fontWeight: count > 0 || isToday ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? theme.colorScheme.onPrimary : null,
              ),
            ),
            if (blocks.isNotEmpty && count == 0)
              Icon(
                Icons.block,
                size: 12,
                color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.error,
              ),
            if (count > 0)
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
