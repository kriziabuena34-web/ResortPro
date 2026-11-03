import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../services/analytics.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/charts.dart';

/// Business analytics: occupancy, cancellation/no-show, peak days,
/// repeat clients, at forecast (moving average + linear regression).
class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key, required this.data});

  final AdminData data;

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  bool _forecastRevenue = true;
  static const _horizon = 3;

  String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = Analytics(widget.data);
    final monthly = a.monthly;
    final labels = [for (final m in monthly) monthShort[m.month.month - 1]];

    // ---- Forecast ----
    final history = [for (final m in monthly) _forecastRevenue ? m.revenue : m.active.toDouble()];
    // Huwag isama ang kasalukuyang buwan kung kulang pa ang data (hindi pa tapos ang buwan).
    final ma = Analytics.movingAverageForecast(history, _horizon);
    final reg = Analytics.linearRegression(history);
    final regFuture = [for (var i = 0; i < _horizon; i++) reg.predict((history.length + i).toDouble()).clamp(0, double.infinity).toDouble()];
    final future = a.futureMonths(_horizon);
    final booked = a.alreadyBooked(_horizon, revenue: _forecastRevenue);
    final allLabels = [...labels, for (final m in future) monthShort[m.month - 1]];
    final fmt = _forecastRevenue ? pesoCompact : (double v) => v.toStringAsFixed(0);
    final fmtFull = _forecastRevenue ? peso : (double v) => v.toStringAsFixed(1);

    final loyalty = a.clientLoyalty;
    final weekday = a.bookingsByWeekday;
    const dayKeys = ['dowMon', 'dowTue', 'dowWed', 'dowThu', 'dowFri', 'dowSat', 'dowSun'];
    final peakIndex = weekday.isEmpty
        ? 0
        : weekday.indexOf(weekday.reduce((x, y) => x > y ? x : y));
    final sources = a.bookingsBySource;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final twoColumns = width >= 1000;

        Widget pair(Widget x, Widget y) => twoColumns
            ? EqualHeightRow(children: [x, y])
            : Column(children: [x, const SizedBox(height: 16), y]);

        return ListView(
          padding: pageInsets(context),
          children: [
            Text(tr('anIntro'), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            StatGrid(
              children: [
                StatCard(
                  icon: Icons.hotel_outlined,
                  label: tr('anOccupancy'),
                  value: _pct(a.occupancyRate),
                  caption: tr('anLast12'),
                  color: theme.colorScheme.primary,
                ),
                StatCard(
                  icon: Icons.cancel_outlined,
                  label: tr('anCancelRate'),
                  value: _pct(a.cancellationRate),
                  color: const Color(0xFFD64545),
                ),
                StatCard(
                  icon: Icons.person_off_outlined,
                  label: tr('anNoShowRate'),
                  value: _pct(a.noShowRate),
                  color: const Color(0xFF8D6E63),
                ),
                StatCard(
                  icon: Icons.repeat,
                  label: tr('anRepeatRate'),
                  value: _pct(loyalty.newClients + loyalty.repeatClients == 0
                      ? 0
                      : loyalty.repeatClients / (loyalty.newClients + loyalty.repeatClients)),
                  caption: tr('anRepeatCaption', {'n': loyalty.repeatClients}),
                  color: const Color(0xFF6B5BD2),
                ),
                StatCard(
                  icon: Icons.sell_outlined,
                  label: tr('anAvgValue'),
                  value: peso(a.averageBookingValue),
                  color: const Color(0xFF2E9E5B),
                ),
                StatCard(
                  icon: Icons.schedule,
                  label: tr('anLeadTime'),
                  value: tr('anDays', {'n': a.averageLeadTimeDays.toStringAsFixed(0)}),
                  caption: tr('anLeadCaption'),
                  color: const Color(0xFF2F6FED),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ---- Forecast ----
            SectionCard(
              title: tr('anForecastTitle'),
              subtitle: tr('anForecastSub'),
              trailing: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: Text(tr('anRevenue'))),
                  ButtonSegment(value: false, label: Text(tr('bookingsWord'))),
                ],
                selected: {_forecastRevenue},
                onSelectionChanged: (s) => setState(() => _forecastRevenue = s.first),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LineChart(
                    labels: allLabels,
                    highlightFrom: labels.length,
                    axisFormat: fmt,
                    series: [
                      LineSeries(tr('anActual'), theme.colorScheme.primary, [...history, for (var i = 0; i < _horizon; i++) null]),
                      LineSeries(
                        tr('anMovingAvg'),
                        const Color(0xFFE08A00),
                        [for (var i = 0; i < history.length - 1; i++) null, history.last, ...ma],
                        dashed: true,
                      ),
                      LineSeries(
                        tr('anRegression'),
                        const Color(0xFF6B5BD2),
                        [
                          for (var i = 0; i < history.length; i++) reg.predict(i.toDouble()).clamp(0, double.infinity).toDouble(),
                          ...regFuture,
                        ],
                        dashed: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStatePropertyAll(theme.colorScheme.primaryContainer),
                      columns: [
                        DataColumn(label: Text(tr('rpMonth'))),
                        DataColumn(numeric: true, label: Text(tr('anMovingAvg'))),
                        DataColumn(numeric: true, label: Text(tr('anRegression'))),
                        DataColumn(numeric: true, label: Text(tr('anAlreadyBooked'))),
                      ],
                      rows: [
                        for (var i = 0; i < _horizon; i++)
                          DataRow(cells: [
                            DataCell(Text('${monthNames[future[i].month - 1]} ${future[i].year}')),
                            DataCell(Text(fmtFull(ma[i]))),
                            DataCell(Text(fmtFull(regFuture[i]))),
                            DataCell(Text(fmtFull(booked[i]))),
                          ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      tr('anModelNote', {
                        'a': fmtFull(reg.intercept),
                        'b': fmtFull(reg.slope),
                        'r2': reg.r2.toStringAsFixed(2),
                        'trend': reg.slope >= 0 ? tr('anTrendUp') : tr('anTrendDown'),
                      }),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            pair(
              SectionCard(
                title: tr('anOccupancyMonthly'),
                subtitle: tr('anOccupancyDef'),
                child: GroupedBarChart(
                  labels: labels,
                  series: [
                    ChartSeries(tr('anOccupancy'), theme.colorScheme.primary,
                        [for (final m in monthly) m.occupancy * 100]),
                  ],
                  axisFormat: (v) => '${v.toStringAsFixed(0)}%',
                  valueFormat: (v) => '${v.toStringAsFixed(1)}%',
                ),
              ),
              SectionCard(
                title: tr('anCancelMonthly'),
                subtitle: tr('anCancelDef'),
                child: GroupedBarChart(
                  labels: labels,
                  series: [
                    ChartSeries(tr('anCancelRate'), const Color(0xFFD64545),
                        [for (final m in monthly) m.cancellationRate * 100]),
                    ChartSeries(tr('anNoShowRate'), const Color(0xFF8D6E63),
                        [for (final m in monthly) m.noShowRate * 100]),
                  ],
                  axisFormat: (v) => '${v.toStringAsFixed(0)}%',
                  valueFormat: (v) => '${v.toStringAsFixed(1)}%',
                ),
              ),
            ),
            const SizedBox(height: 16),

            pair(
              SectionCard(
                title: tr('anPeakDays'),
                subtitle: weekday.every((c) => c == 0)
                    ? tr('noData')
                    : tr('anPeakDaySub', {'day': tr(dayKeys[peakIndex])}),
                child: HorizontalBarList(
                  color: const Color(0xFF0E9AA7),
                  items: [
                    for (var i = 0; i < 7; i++)
                      BarItem(
                        tr(dayKeys[i]),
                        weekday[i].toDouble(),
                        color: i == peakIndex ? const Color(0xFFE08A00) : null,
                      ),
                  ],
                ),
              ),
              SectionCard(
                title: tr('anClientsTitle'),
                subtitle: tr('anClientsSub'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DonutChart(
                      centerLabel: tr('navClients').toLowerCase(),
                      slices: [
                        DonutSlice(tr('anNewClients'), loyalty.newClients.toDouble(), const Color(0xFF2F6FED)),
                        DonutSlice(tr('anRepeatClients'), loyalty.repeatClients.toDouble(), const Color(0xFF6B5BD2)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(tr('anBySource'), style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    HorizontalBarList(
                      items: [
                        for (final s in const ['online', 'walk_in', 'phone'])
                          BarItem(sourceLabel(s), (sources[s] ?? 0).toDouble()),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            SectionCard(
              title: tr('anMonthlyTable'),
              subtitle: tr('anLast12'),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStatePropertyAll(theme.colorScheme.primaryContainer),
                  columns: [
                    DataColumn(label: Text(tr('rpMonth'))),
                    DataColumn(numeric: true, label: Text(tr('bookingsWord'))),
                    DataColumn(numeric: true, label: Text(tr('anOccupancy'))),
                    DataColumn(numeric: true, label: Text(tr('anCancelRate'))),
                    DataColumn(numeric: true, label: Text(tr('anNoShowRate'))),
                    DataColumn(numeric: true, label: Text(tr('seriesBooked'))),
                    DataColumn(numeric: true, label: Text(tr('seriesCollected'))),
                  ],
                  rows: [
                    for (final m in monthly.reversed)
                      DataRow(cells: [
                        DataCell(Text('${monthShort[m.month.month - 1]} ${m.month.year}')),
                        DataCell(Text('${m.active}')),
                        DataCell(Text(_pct(m.occupancy))),
                        DataCell(Text(_pct(m.cancellationRate))),
                        DataCell(Text(_pct(m.noShowRate))),
                        DataCell(Text(peso(m.revenue))),
                        DataCell(Text(peso(m.collected))),
                      ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}
