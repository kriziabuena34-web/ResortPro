import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../services/notification_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/charts.dart';

/// Dashboard: KPI cards + graphs para sa business analytics ng resort.
class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key, required this.data, required this.onOpen});

  final AdminData data;

  /// Para makapunta sa ibang module kapag pinindot ang isang card.
  final void Function(int module, [String? bookingFilter]) onOpen;

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  int _year = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final active = data.activeBookings;
    final today = DateUtils.dateOnly(DateTime.now());

    // ---- KPIs ----
    final collected = data.bookings.fold<double>(0, (s, b) => s + paidOf(b));
    final outstanding = active.fold<double>(0, (s, b) => s + remainingOf(b));
    final upcoming = active.where((b) {
      final d = bookingDateOf(b);
      return d != null && !d.isBefore(today) && d.isBefore(today.add(const Duration(days: 14)));
    }).toList()
      ..sort((a, b) => bookingDateOf(a)!.compareTo(bookingDateOf(b)!));
    final pending = data.pendingAccounts.length;
    final reminders = remindersFor(data);
    final verifiedClients =
        data.clients.where((c) => c['verification_status'] == 'verified').length;

    // ---- Monthly revenue para sa napiling taon ----
    final booked = List<double>.filled(12, 0);
    final collectedByMonth = List<double>.filled(12, 0);
    final bookingsByMonth = List<double>.filled(12, 0);
    final years = <int>{DateTime.now().year};
    for (final b in active) {
      final d = bookingDateOf(b);
      if (d == null) continue;
      years.add(d.year);
      if (d.year != _year) continue;
      booked[d.month - 1] += totalOf(b);
      collectedByMonth[d.month - 1] += paidOf(b);
      bookingsByMonth[d.month - 1] += 1;
    }
    final minYear = years.reduce((a, b) => a < b ? a : b);
    final maxYear = years.reduce((a, b) => a > b ? a : b);
    final yearTotal = booked.fold<double>(0, (s, v) => s + v);
    final yearBookings = bookingsByMonth.fold<double>(0, (s, v) => s + v).round();

    // ---- Status breakdown ----
    final statusCounts = <String, int>{};
    for (final b in data.bookings) {
      final s = '${b['status'] ?? 'unknown'}';
      statusCounts[s] = (statusCounts[s] ?? 0) + 1;
    }
    const statusOrder = bookingStatuses;
    final statusKeys = [
      ...statusOrder.where(statusCounts.containsKey),
      ...statusCounts.keys.where((k) => !statusOrder.contains(k)),
    ];

    // ---- Top packages ----
    final pkgCount = <String, int>{};
    final pkgRevenue = <String, double>{};
    for (final b in active) {
      final name = packageNameOf(b);
      pkgCount[name] = (pkgCount[name] ?? 0) + 1;
      pkgRevenue[name] = (pkgRevenue[name] ?? 0) + totalOf(b);
    }
    final topPackages = pkgCount.keys.toList()
      ..sort((a, b) => pkgCount[b]!.compareTo(pkgCount[a]!));

    // ---- Payment methods ----
    final methodTotals = <String, double>{};
    for (final b in data.bookings) {
      for (final p in paymentsOf(b)) {
        final m = '${p['method'] ?? 'other'}';
        methodTotals[m] = (methodTotals[m] ?? 0) + asDouble(p['amount']);
      }
    }
    final methods = methodTotals.keys.toList()
      ..sort((a, b) => methodTotals[b]!.compareTo(methodTotals[a]!));

    // ---- Guest mix (age groups) ----
    final guestGroups = [
      ('infants', tr('guestInfants')),
      ('children', tr('guestChildren')),
      ('teens', tr('guestTeens')),
      ('adults', tr('guestAdults')),
      ('elderly', tr('guestElderly')),
    ];
    final guestTotals = {
      for (final g in guestGroups)
        g.$1: active.fold<int>(0, (s, b) => s + asInt(b[g.$1])),
    };
    final totalGuests = guestTotals.values.fold<int>(0, (s, v) => s + v);

    final todays = active.where((b) => bookingDateOf(b) == today).toList();
    final todaysGuests = todays.fold<int>(0, (s, b) => s + guestsOf(b));
    final staffName = staffNameOf(Supabase.instance.client.auth.currentUser?.id) ?? 'Admin';

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final twoColumns = width >= 1000;

        Widget pair(Widget a, Widget b) {
          if (!twoColumns) {
            return Column(children: [a, const SizedBox(height: 18), b]);
          }
          return EqualHeightRow(spacing: 18, children: [a, b]);
        }

        final tiles = [
          _tile(tr('kpiCollected').toUpperCase(), tr('ovCollectedSub'), peso(collected), const Color(0xFF4ADE80),
              Icons.payments_outlined, () => widget.onOpen(5)),
          _tile(tr('kpiOutstanding').toUpperCase(), tr('ovOutstandingSub'), peso(outstanding), const Color(0xFFFBBF24),
              Icons.account_balance_wallet_outlined, () => widget.onOpen(1, 'balance')),
          _tile(tr('kpiActive').toUpperCase(), tr('kpiInactiveCount', {'n': data.bookings.length - active.length}),
              '${active.length}', Colors.white, Icons.event_available_outlined, () => widget.onOpen(1)),
          _tile(tr('kpiNext14').toUpperCase(), tr('kpiUpcomingCaption'), '${upcoming.length}', const Color(0xFF60A5FA),
              Icons.upcoming_outlined, () => widget.onOpen(2)),
          _tile(tr('kpiPending').toUpperCase(), tr('kpiVerifiedCaption', {'n': verifiedClients}), '$pending',
              pending > 0 ? const Color(0xFFF87171) : Colors.white, Icons.verified_user_outlined, () => widget.onOpen(4)),
        ];

        return ListView(
          padding: pageInsets(context),
          children: [
            // ---- Hero: bati + mga KPI ----
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 12))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('greeting', {'name': staffName}),
                                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text(
                              [?currentStaffTitle(), tr('summaryToday', {'date': formatDate(today)})].join('  ·  '),
                              style: const TextStyle(color: AppColors.inkText, fontSize: 13.5),
                            ),
                          ],
                        ),
                      ),
                      if (width >= 700)
                        Material(
                          color: const Color(0xFF1E3A55),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(color: Color(0xFF34597A)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => widget.onOpen(11),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 10, 18, 10),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2B4C6B),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.groups_rounded, color: Color(0xFFBFDBFE), size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(titleCase(tr('ovTodaysGuests')),
                                          style: const TextStyle(color: Color(0xFFBFDBFE), fontSize: 11.5, fontWeight: FontWeight.w700)),
                                      Text(
                                        tr('ovTodaysGuestsValue', {'n': todaysGuests, 'b': todays.length}),
                                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (width >= 1100)
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
                      crossAxisCount: width >= 700 ? 3 : 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: width >= 700 ? 2.0 : 1.4,
                      children: tiles,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ---- Needs attention ----
            if (reminders.isNotEmpty) ...[
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFF5C451), width: 1.5),
                ),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.notification_important_outlined, size: 20, color: Color(0xFF92400E)),
                        const SizedBox(width: 8),
                        Text(titleCase(tr('needsAttention')),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFFFACC15), borderRadius: BorderRadius.circular(10)),
                          child: Text('${reminders.length}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.ink)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(tr('needsAttentionSub'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final r in reminders)
                          Material(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: Color(0xFFF5D08A)),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => widget.onOpen(r.module, r.bookingStatus),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: r.color.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Icon(r.icon, color: r.color, size: 17),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.muted),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],

            // ---- Monthly revenue ----
            _section(
              icon: Icons.bar_chart_rounded,
              title: tr('monthlyRevenue'),
              subtitle: tr('monthlySubtitle', {'n': yearBookings, 'amount': peso(yearTotal), 'year': _year}),
              trailing: Container(
                decoration: BoxDecoration(
                  color: AppColors.subtle,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: tr('prevYear'),
                      onPressed: _year > minYear ? () => setState(() => _year--) : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Text('$_year', style: const TextStyle(fontWeight: FontWeight.w800)),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: tr('nextYear'),
                      onPressed: _year < maxYear ? () => setState(() => _year++) : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
              child: GroupedBarChart(
                labels: monthShort,
                series: [
                  ChartSeries(titleCase(tr('seriesBooked')), AppColors.primary, booked),
                  ChartSeries(titleCase(tr('seriesCollected')), const Color(0xFF4ADE80), collectedByMonth),
                ],
                axisFormat: pesoCompact,
                valueFormat: peso,
              ),
            ),
            const SizedBox(height: 18),

            pair(
              _section(
                icon: Icons.donut_large_rounded,
                title: tr('byStatus'),
                subtitle: tr('byStatusSub'),
                child: DonutChart(
                  centerLabel: tr('bookingsWord'),
                  slices: [
                    for (final k in statusKeys) DonutSlice(statusLabel(k), statusCounts[k]!.toDouble(), statusColor(k)),
                  ],
                ),
              ),
              _section(
                icon: Icons.inventory_2_outlined,
                title: tr('topPackages'),
                subtitle: tr('topPackagesSub'),
                child: HorizontalBarList(
                  color: AppColors.primary,
                  items: [
                    for (final name in topPackages.take(6))
                      BarItem(
                        name,
                        pkgCount[name]!.toDouble(),
                        trailing: tr('pkgBookingsValue', {'n': pkgCount[name], 'amount': pesoCompact(pkgRevenue[name]!)}),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            pair(
              _section(
                icon: Icons.account_balance_wallet_outlined,
                title: tr('byMethod'),
                subtitle: tr('byMethodSub'),
                child: methods.isEmpty
                    ? const HorizontalBarList(items: [])
                    : DonutChart(
                        centerLabel: tr('collectedWord'),
                        valueFormat: pesoCompact,
                        slices: [for (final m in methods) DonutSlice(methodLabel(m), methodTotals[m]!, methodColor(m))],
                      ),
              ),
              _section(
                icon: Icons.groups_outlined,
                title: tr('guestDemo'),
                subtitle: tr('guestDemoSub', {'n': totalGuests}),
                child: HorizontalBarList(
                  color: const Color(0xFF6366F1),
                  items: totalGuests == 0
                      ? []
                      : [
                          for (final g in guestGroups)
                            BarItem(
                              g.$2,
                              guestTotals[g.$1]!.toDouble(),
                              trailing:
                                  '${guestTotals[g.$1]}  (${(guestTotals[g.$1]! / totalGuests * 100).toStringAsFixed(0)}%)',
                            ),
                        ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // ---- Upcoming ----
            _section(
              icon: Icons.upcoming_outlined,
              title: tr('upcomingTitle'),
              subtitle: tr('upcomingSub'),
              padBody: false,
              trailing: OutlinedButton.icon(
                onPressed: () => widget.onOpen(2),
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: Text(tr('openCalendar')),
              ),
              child: upcoming.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: EmptyState(icon: Icons.event_available, message: tr('noUpcoming')),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < upcoming.take(8).length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          _upcomingRow(upcoming[i], today),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Widget _tile(String label, String sub, String value, Color valueColor, IconData icon, VoidCallback onTap) {
    return Material(
      color: AppColors.inkRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.inkLine),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.inkText, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                  ),
                  Icon(icon, size: 16, color: const Color(0xFF7F93A6)),
                ],
              ),
              const SizedBox(height: 2),
              Text(titleCase(sub),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF7F93A6), fontSize: 10.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: TextStyle(color: valueColor, fontSize: 22, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    required Widget child,
    bool padBody = true,
  }) {
    return AppCard(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 18, 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titleCase(title), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                      if (subtitle != null) Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing],
              ],
            ),
          ),
          const Divider(height: 1),
          if (padBody) Padding(padding: const EdgeInsets.all(20), child: child) else child,
        ],
      ),
    );
  }

  Widget _upcomingRow(Map<String, dynamic> b, DateTime today) {
    final d = bookingDateOf(b)!;
    final days = d.difference(today).inDays;
    final when = days == 0
        ? tr('ovToday')
        : days == 1
            ? tr('ovTomorrow')
            : tr('ovInDays', {'n': days});
    final balance = remainingOf(b);
    return InkWell(
      onTap: () => widget.onOpen(1),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          children: [
            _DateBadge(date: d, today: days == 0),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(packageNameOf(b), style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('${clientNameOf(b)}  ·  ${tr('paxCount', {'n': guestsOf(b)})}  ·  $when',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (balance > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFF5C451)),
                ),
                child: Text(tr('balanceAmount', {'amount': peso(balance)}),
                    style: const TextStyle(color: Color(0xFF92400E), fontWeight: FontWeight.w700, fontSize: 12)),
              )
            else
              const StatusChip(status: 'fully_paid'),
          ],
        ),
      ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.date, this.today = false});
  final DateTime date;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final fg = today ? Colors.white : AppColors.primary;
    return Container(
      width: 50,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: today ? AppColors.primary : AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: today ? 1 : 0.25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(monthShort[date.month - 1].toUpperCase(),
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: fg)),
          Text('${date.day}',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, height: 1.1, color: fg)),
        ],
      ),
    );
  }
}
