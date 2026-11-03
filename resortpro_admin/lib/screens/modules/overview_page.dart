import 'package:flutter/material.dart';

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
    final theme = Theme.of(context);
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final twoColumns = width >= 1000;

        Widget pair(Widget a, Widget b) {
          if (!twoColumns) {
            return Column(children: [a, const SizedBox(height: 16), b]);
          }
          return EqualHeightRow(children: [a, b]);
        }

        return ListView(
          padding: pageInsets(context),
          children: [
            // Welcome banner
            Container(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.ink, Color(0xFF0E4D5A), AppColors.primary],
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('greeting'),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tr('summaryToday', {'date': formatDate(today)}),
                          style: const TextStyle(color: Color(0xFFCFE3E6), fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  if (width >= 700)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${upcoming.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            tr('kpiNext14'),
                            style: const TextStyle(color: Color(0xFFCFE3E6), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // KPI cards
            StatGrid(
              children: [
                StatCard(
                  icon: Icons.payments_outlined,
                  label: tr('kpiCollected'),
                  value: peso(collected),
                  color: AppColors.success,
                  onTap: () => widget.onOpen(5),
                ),
                StatCard(
                  icon: Icons.account_balance_wallet_outlined,
                  label: tr('kpiOutstanding'),
                  value: peso(outstanding),
                  color: AppColors.accent,
                  onTap: () => widget.onOpen(1, 'balance'),
                ),
                StatCard(
                  icon: Icons.event_available_outlined,
                  label: tr('kpiActive'),
                  value: '${active.length}',
                  caption: tr('kpiInactiveCount', {'n': data.bookings.length - active.length}),
                  color: theme.colorScheme.primary,
                  onTap: () => widget.onOpen(1),
                ),
                StatCard(
                  icon: Icons.upcoming_outlined,
                  label: tr('kpiNext14'),
                  value: '${upcoming.length}',
                  caption: tr('kpiUpcomingCaption'),
                  color: AppColors.info,
                  onTap: () => widget.onOpen(2),
                ),
                StatCard(
                  icon: Icons.verified_user_outlined,
                  label: tr('kpiPending'),
                  value: '$pending',
                  caption: tr('kpiVerifiedCaption', {'n': verifiedClients}),
                  color: pending > 0 ? const Color(0xFFD64545) : const Color(0xFF7A7F87),
                  onTap: () => widget.onOpen(4),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Needs attention (reminders)
            if (reminders.isNotEmpty) ...[
              SectionCard(
                title: tr('needsAttention'),
                subtitle: tr('needsAttentionSub'),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final r in reminders)
                      ActionChip(
                        avatar: Icon(r.icon, color: r.color, size: 18),
                        label: Text(r.title),
                        side: BorderSide(color: r.color.withValues(alpha: 0.4)),
                        backgroundColor: r.color.withValues(alpha: 0.08),
                        onPressed: () => widget.onOpen(r.module, r.bookingStatus),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Monthly revenue
            SectionCard(
              title: tr('monthlyRevenue'),
              subtitle: tr('monthlySubtitle', {
                'n': yearBookings,
                'amount': peso(yearTotal),
                'year': _year,
              }),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: tr('prevYear'),
                    onPressed: _year > minYear ? () => setState(() => _year--) : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('$_year', style: theme.textTheme.titleMedium),
                  IconButton(
                    tooltip: tr('nextYear'),
                    onPressed: _year < maxYear ? () => setState(() => _year++) : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              child: GroupedBarChart(
                labels: monthShort,
                series: [
                  ChartSeries(tr('seriesBooked'), theme.colorScheme.primary, booked),
                  ChartSeries(tr('seriesCollected'), const Color(0xFF2E9E5B), collectedByMonth),
                ],
                axisFormat: pesoCompact,
                valueFormat: peso,
              ),
            ),
            const SizedBox(height: 16),

            pair(
              SectionCard(
                title: tr('byStatus'),
                subtitle: tr('byStatusSub'),
                child: DonutChart(
                  centerLabel: tr('bookingsWord'),
                  slices: [
                    for (final k in statusKeys)
                      DonutSlice(statusLabel(k), statusCounts[k]!.toDouble(), statusColor(k)),
                  ],
                ),
              ),
              SectionCard(
                title: tr('topPackages'),
                subtitle: tr('topPackagesSub'),
                child: HorizontalBarList(
                  color: theme.colorScheme.primary,
                  items: [
                    for (final name in topPackages.take(6))
                      BarItem(
                        name,
                        pkgCount[name]!.toDouble(),
                        trailing: tr('pkgBookingsValue', {
                          'n': pkgCount[name],
                          'amount': pesoCompact(pkgRevenue[name]!),
                        }),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            pair(
              SectionCard(
                title: tr('byMethod'),
                subtitle: tr('byMethodSub'),
                child: methods.isEmpty
                    ? const HorizontalBarList(items: [])
                    : DonutChart(
                        centerLabel: tr('collectedWord'),
                        valueFormat: pesoCompact,
                        slices: [
                          for (final m in methods)
                            DonutSlice(methodLabel(m), methodTotals[m]!, methodColor(m)),
                        ],
                      ),
              ),
              SectionCard(
                title: tr('guestDemo'),
                subtitle: tr('guestDemoSub', {'n': totalGuests}),
                child: HorizontalBarList(
                  color: const Color(0xFF8E5CD9),
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
            const SizedBox(height: 16),

            SectionCard(
              title: tr('upcomingTitle'),
              subtitle: tr('upcomingSub'),
              trailing: TextButton(
                onPressed: () => widget.onOpen(2),
                child: Text(tr('openCalendar')),
              ),
              child: upcoming.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: Text(tr('noUpcoming'))),
                    )
                  : Column(
                      children: [
                        for (final b in upcoming.take(8))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: _DateBadge(date: bookingDateOf(b)!),
                            title: Text(packageNameOf(b)),
                            subtitle: Text('${clientNameOf(b)} · ${tr('paxCount', {'n': guestsOf(b)})}'),
                            trailing: remainingOf(b) > 0
                                ? Text(
                                    tr('balanceAmount', {'amount': peso(remainingOf(b))}),
                                    style: const TextStyle(
                                      color: Color(0xFFE08A00),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                : const StatusChip(status: 'fully_paid'),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 48,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            monthShort[date.month - 1].toUpperCase(),
            style: TextStyle(fontSize: 10, color: theme.colorScheme.onPrimaryContainer),
          ),
          Text(
            '${date.day}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
