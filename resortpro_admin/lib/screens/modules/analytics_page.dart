import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../services/analytics.dart';
import '../../theme/app_theme.dart';
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

    final repeatRate = loyalty.newClients + loyalty.repeatClients == 0
        ? 0.0
        : loyalty.repeatClients / (loyalty.newClients + loyalty.repeatClients);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final twoColumns = width >= 1000;

        Widget pair(Widget x, Widget y) => twoColumns
            ? EqualHeightRow(spacing: 18, children: [x, y])
            : Column(children: [x, const SizedBox(height: 18), y]);

        return ListView(
          padding: pageInsets(context),
          children: [
            Text(tr('anIntro'), style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 14),
            _overviewCard(width, [
              _tile(tr('anOccupancy').toUpperCase(), tr('anLast12'), _pct(a.occupancyRate), Colors.white,
                  Icons.hotel_outlined),
              _tile(tr('anCancelRate').toUpperCase(), tr('anKCancelSub'), _pct(a.cancellationRate),
                  const Color(0xFFF87171), Icons.cancel_outlined),
              _tile(tr('anNoShowRate').toUpperCase(), tr('anKNoShowSub'), _pct(a.noShowRate), const Color(0xFFFBBF24),
                  Icons.person_off_outlined),
              _tile(tr('anRepeatRate').toUpperCase(), tr('anRepeatCaption', {'n': loyalty.repeatClients}),
                  _pct(repeatRate), const Color(0xFFA78BFA), Icons.repeat_rounded),
              _tile(tr('anAvgValue').toUpperCase(), tr('anKAvgSub'), peso(a.averageBookingValue),
                  const Color(0xFF4ADE80), Icons.sell_outlined),
              _tile(tr('anLeadTime').toUpperCase(), tr('anLeadCaption'),
                  tr('anDays', {'n': a.averageLeadTimeDays.toStringAsFixed(0)}), const Color(0xFF60A5FA),
                  Icons.schedule_rounded),
            ]),
            const SizedBox(height: 18),

            // ---- Forecast ----
            _section(
              icon: Icons.insights_rounded,
              title: tr('anForecastTitle'),
              subtitle: tr('anForecastSub'),
              trailing: _toggle(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LineChart(
                    labels: allLabels,
                    highlightFrom: labels.length,
                    axisFormat: fmt,
                    series: [
                      LineSeries(tr('anActual'), AppColors.primary, [...history, for (var i = 0; i < _horizon; i++) null]),
                      LineSeries(
                        tr('anMovingAvg'),
                        const Color(0xFFF59E0B),
                        [for (var i = 0; i < history.length - 1; i++) null, history.last, ...ma],
                        dashed: true,
                      ),
                      LineSeries(
                        tr('anRegression'),
                        const Color(0xFF6366F1),
                        [
                          for (var i = 0; i < history.length; i++) reg.predict(i.toDouble()).clamp(0, double.infinity).toDouble(),
                          ...regFuture,
                        ],
                        dashed: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, c) => Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (var i = 0; i < _horizon; i++)
                        SizedBox(
                          width: c.maxWidth >= 640 ? (c.maxWidth - 24) / 3 : c.maxWidth,
                          child: _forecastCard(
                            '${monthNames[future[i].month - 1]} ${future[i].year}',
                            fmtFull(ma[i]),
                            fmtFull(regFuture[i]),
                            fmtFull(booked[i]),
                          ),
                        ),
                    ],
                  ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.20)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(reg.slope >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                            size: 18, color: AppColors.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            tr('anModelNote', {
                              'a': fmtFull(reg.intercept),
                              'b': fmtFull(reg.slope),
                              'r2': reg.r2.toStringAsFixed(2),
                              'trend': reg.slope >= 0 ? tr('anTrendUp') : tr('anTrendDown'),
                            }),
                            style: const TextStyle(fontSize: 12.5, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            pair(
              _section(
                icon: Icons.hotel_outlined,
                title: tr('anOccupancyMonthly'),
                subtitle: tr('anOccupancyDef'),
                child: GroupedBarChart(
                  labels: labels,
                  series: [
                    ChartSeries(tr('anOccupancy'), AppColors.primary, [for (final m in monthly) m.occupancy * 100]),
                  ],
                  axisFormat: (v) => '${v.toStringAsFixed(0)}%',
                  valueFormat: (v) => '${v.toStringAsFixed(1)}%',
                ),
              ),
              _section(
                icon: Icons.event_busy_outlined,
                title: tr('anCancelMonthly'),
                subtitle: tr('anCancelDef'),
                child: GroupedBarChart(
                  labels: labels,
                  series: [
                    ChartSeries(tr('anCancelRate'), const Color(0xFFEF4444), [for (final m in monthly) m.cancellationRate * 100]),
                    ChartSeries(tr('anNoShowRate'), const Color(0xFF94A3B8), [for (final m in monthly) m.noShowRate * 100]),
                  ],
                  axisFormat: (v) => '${v.toStringAsFixed(0)}%',
                  valueFormat: (v) => '${v.toStringAsFixed(1)}%',
                ),
              ),
            ),
            const SizedBox(height: 18),

            pair(
              _section(
                icon: Icons.calendar_view_week_rounded,
                title: tr('anPeakDays'),
                subtitle: weekday.every((c) => c == 0)
                    ? tr('noData')
                    : tr('anPeakDaySub', {'day': tr(dayKeys[peakIndex])}),
                child: HorizontalBarList(
                  color: const Color(0xFF94A3B8),
                  items: [
                    for (var i = 0; i < 7; i++)
                      BarItem(tr(dayKeys[i]), weekday[i].toDouble(), color: i == peakIndex ? AppColors.primary : null),
                  ],
                ),
              ),
              _section(
                icon: Icons.groups_outlined,
                title: tr('anClientsTitle'),
                subtitle: tr('anClientsSub'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DonutChart(
                      centerLabel: tr('navClients').toLowerCase(),
                      slices: [
                        DonutSlice(tr('anNewClients'), loyalty.newClients.toDouble(), const Color(0xFF60A5FA)),
                        DonutSlice(tr('anRepeatClients'), loyalty.repeatClients.toDouble(), const Color(0xFF6366F1)),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(tr('anBySource').toUpperCase(), style: _caps),
                    const SizedBox(height: 10),
                    HorizontalBarList(
                      color: AppColors.primary,
                      items: [
                        for (final s in const ['online', 'walk_in', 'phone'])
                          BarItem(sourceLabel(s), (sources[s] ?? 0).toDouble()),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            _section(
              icon: Icons.table_chart_outlined,
              title: tr('anMonthlyTable'),
              subtitle: tr('anLast12'),
              padBody: false,
              child: _monthlyTable(monthly, width),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  static const _caps = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.muted);

  Widget _overviewCard(double width, List<Widget> tiles) {
    final cols = width >= 1000 ? 3 : 2;
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
              const Icon(Icons.analytics_rounded, color: AppColors.inkText, size: 20),
              const SizedBox(width: 8),
              Text(tr('anOverview'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.8, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: cols == 3 ? 2.9 : 1.45,
            children: tiles,
          ),
        ],
      ),
    );
  }

  Widget _tile(String label, String sub, String value, Color valueColor, IconData icon) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.inkText, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
              ),
              Icon(icon, size: 16, color: const Color(0xFF7F93A6)),
            ],
          ),
          const SizedBox(height: 2),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF7F93A6), fontSize: 10.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(color: valueColor, fontSize: 24, fontWeight: FontWeight.w800)),
          ),
        ],
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
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                          if (subtitle != null)
                            Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                        ],
                      ),
                    ),
                  ],
                ),
                ?trailing,
              ],
            ),
          ),
          const Divider(height: 1),
          if (padBody) Padding(padding: const EdgeInsets.all(20), child: child) else child,
        ],
      ),
    );
  }

  /// Revenue / Bookings na toggle (kapareho ng itsura ng mga tab).
  Widget _toggle() {
    Widget seg(bool v, String label) {
      final selected = _forecastRevenue == v;
      return Material(
        color: selected ? AppColors.ink : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _forecastRevenue = v),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text(label,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.text,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 13,
                )),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.subtle,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [seg(true, tr('anRevenue')), seg(false, tr('bookingsWord'))],
      ),
    );
  }

  Widget _forecastCard(String month, String ma, String reg, String booked) {
    Widget line(Color color, String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12.5))),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.subtle,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(month.toUpperCase(), style: _caps),
          const SizedBox(height: 2),
          line(const Color(0xFFF59E0B), tr('anMovingAvg'), ma),
          line(const Color(0xFF6366F1), tr('anRegression'), reg),
          line(AppColors.primary, tr('anAlreadyBooked'), booked),
        ],
      ),
    );
  }

  Widget _monthlyTable(List<MonthStat> monthly, double width) {
    const flex = [3, 2, 2, 2, 2, 3, 3];
    final headers = [
      tr('rpcMonth'),
      tr('rpcBookings'),
      tr('anOccupancy'),
      tr('anCancelRate'),
      tr('anNoShowRate'),
      tr('rpcBooked'),
      tr('rpcCollected'),
    ];
    Widget row(List<String> cells, {bool header = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          color: header ? AppColors.subtle : null,
          child: Row(
            children: [
              for (var i = 0; i < cells.length; i++)
                Expanded(
                  flex: flex[i],
                  child: Padding(
                    padding: EdgeInsets.only(right: i == cells.length - 1 ? 0 : 16),
                    child: Text(
                      header ? cells[i].toUpperCase() : cells[i],
                      textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: header
                          ? _caps
                          : TextStyle(fontSize: 13.5, fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400),
                    ),
                  ),
                ),
            ],
          ),
        );
    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(headers, header: true),
        for (final m in monthly.reversed) ...[
          const Divider(height: 1),
          row([
            '${monthShort[m.month.month - 1]} ${m.month.year}',
            '${m.active}',
            _pct(m.occupancy),
            _pct(m.cancellationRate),
            _pct(m.noShowRate),
            peso(m.revenue),
            peso(m.collected),
          ]),
        ],
      ],
    );
    if (width >= 900) return table;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(width: 900, child: table),
    );
  }
}
