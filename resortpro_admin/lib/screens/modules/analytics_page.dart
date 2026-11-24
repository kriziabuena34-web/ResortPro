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

  static const _minor = {'a', 'an', 'the', 'and', 'or', 'of', 'by', 'per', 'to', 'in', 'on', 'for', 'vs', 'at',
      'ng', 'sa', 'ang', 'mga', 'og', 'ug'};

  /// Title Case: malaking unang letra ng bawat salita. Hindi ginagalaw ang
  /// salitang puro capital na (hal. KPI) at ang maliliit na salita sa gitna.
  static String _tc(String text) {
    var first = true;
    return text.split(' ').map((w) {
      if (w.isEmpty) return w;
      final isFirst = first;
      first = false;
      if (w == w.toUpperCase()) return w;
      final bare = w.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      if (!isFirst && _minor.contains(bare)) return w;
      final i = w.indexOf(RegExp(r'[A-Za-z]'));
      if (i < 0) return w;
      return w.substring(0, i) + w[i].toUpperCase() + w.substring(i + 1);
    }).join(' ');
  }

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
              _tile(tr('anTotalRevenue').toUpperCase(), tr('anTotalRevenueSub', {'n': a.totalActive}),
                  peso(a.totalRevenue), const Color(0xFF4ADE80), Icons.payments_outlined),
              _tile(tr('anTotalExpenses').toUpperCase(), tr('anLast12'), peso(a.totalExpenses), const Color(0xFFF87171),
                  Icons.receipt_long_outlined),
              _tile(tr('anNetProfit').toUpperCase(), tr('anMarginSub', {'p': _pct(a.profitMargin)}), peso(a.totalProfit),
                  a.totalProfit >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                  Icons.account_balance_wallet_outlined),
            ]),
            const SizedBox(height: 18),

            // ---- Forecast ----
            _section(
              icon: Icons.insights_rounded,
              title: _tc(tr('anForecastTitle')),
              subtitle: _tc(tr('anForecastSub')),
              trailing: _toggle(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LineChart(
                    labels: allLabels,
                    highlightFrom: labels.length,
                    axisFormat: fmt,
                    valueFormat: fmtFull,
                    series: [
                      LineSeries(_tc(tr('anActual')), AppColors.primary, [...history, for (var i = 0; i < _horizon; i++) null]),
                      LineSeries(
                        _tc(tr('anMovingAvg')),
                        const Color(0xFFF59E0B),
                        [for (var i = 0; i < history.length - 1; i++) null, history.last, ...ma],
                        dashed: true,
                      ),
                      LineSeries(
                        _tc(tr('anRegression')),
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
                        // Simpleng paliwanag para sa may-ari; nasa tooltip ang formula.
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                reg.slope.abs() < 1
                                    ? tr('anPlainFlat')
                                    : tr(reg.slope > 0 ? 'anPlainUp' : 'anPlainDown', {'amount': fmtFull(reg.slope.abs())}),
                                style: const TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                tr(reg.r2 >= 0.7
                                    ? 'anReliHigh'
                                    : reg.r2 >= 0.4
                                        ? 'anReliMid'
                                        : 'anReliLow'),
                                style: const TextStyle(fontSize: 12.5, height: 1.4),
                              ),
                              const SizedBox(height: 4),
                              Text(tr('anPlainHow'),
                                  style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.muted)),
                            ],
                          ),
                        ),
                        Tooltip(
                          message: tr('anModelNote', {
                            'a': fmtFull(reg.intercept),
                            'b': fmtFull(reg.slope),
                            'r2': reg.r2.toStringAsFixed(2),
                            'trend': reg.slope >= 0 ? tr('anTrendUp') : tr('anTrendDown'),
                          }),
                          child: const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(Icons.info_outline_rounded, size: 18, color: AppColors.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ---- Kita, gastos at net profit ----
            pair(
              _section(
                icon: Icons.account_balance_wallet_outlined,
                title: _tc(tr('anProfitTitle')),
                subtitle: _tc(tr('anProfitSub')),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GroupedBarChart(
                      labels: labels,
                      axisFormat: pesoCompact,
                      valueFormat: peso,
                      series: [
                        ChartSeries(_tc(tr('anRevenue')), AppColors.primary, [for (final m in monthly) m.revenue]),
                        ChartSeries(_tc(tr('navExpenses')), const Color(0xFFF87171), [for (final m in monthly) m.expenses]),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      tr('anProfitNote', {
                        'profitable': monthly.where((m) => m.profit > 0).length,
                        'months': monthly.length,
                      }),
                      style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.4),
                    ),
                  ],
                ),
              ),
              _section(
                icon: Icons.donut_large_rounded,
                title: _tc(tr('anRevenueSources')),
                subtitle: _tc(tr('anRevenueSourcesSub')),
                child: Builder(builder: (context) {
                  final r = a.revenueSources;
                  return HorizontalBarList(
                    color: AppColors.primary,
                    valueFormat: peso,
                    items: [
                      BarItem(_tc(tr('chPackage')), r.package),
                      BarItem(_tc(tr('chExtraPax')), r.extraPax),
                      BarItem(_tc(tr('chRooms')), r.rooms),
                      BarItem(_tc(tr('chExtension')), r.extension),
                      BarItem(_tc(tr('chOther')), r.other),
                    ],
                  );
                }),
              ),
            ),
            const SizedBox(height: 18),

            // ---- Mga customer: taga-saan, paano nalaman, okasyon ----
            pair(
              _section(
                icon: Icons.place_outlined,
                title: _tc(tr('anLocationTitle')),
                subtitle: _tc(tr('anLocationSub')),
                child: _countBars(_top(a.countBy('customer_location'), 8), const Color(0xFF60A5FA)),
              ),
              _section(
                icon: Icons.campaign_outlined,
                title: _tc(tr('anFoundUsTitle')),
                subtitle: _tc(tr('anFoundUsSub')),
                child: _countBars(a.countBy('referral_source'), const Color(0xFF6366F1)),
              ),
            ),
            const SizedBox(height: 18),
            _section(
              icon: Icons.cake_outlined,
              title: _tc(tr('anOccasionTitle')),
              subtitle: _tc(tr('anOccasionSub')),
              child: _countBars(a.countBy('occasion'), const Color(0xFFF59E0B)),
            ),
            const SizedBox(height: 18),

            pair(
              _section(
                icon: Icons.hotel_outlined,
                title: _tc(tr('anOccupancyMonthly')),
                subtitle: _tc(tr('anOccupancyDef')),
                child: GroupedBarChart(
                  labels: labels,
                  series: [
                    ChartSeries(_tc(tr('anOccupancy')), AppColors.primary, [for (final m in monthly) m.occupancy * 100]),
                  ],
                  axisFormat: (v) => '${v.toStringAsFixed(0)}%',
                  valueFormat: (v) => '${v.toStringAsFixed(1)}%',
                ),
              ),
              _section(
                icon: Icons.event_busy_outlined,
                title: _tc(tr('anCancelMonthly')),
                subtitle: _tc(tr('anCancelDef')),
                child: GroupedBarChart(
                  labels: labels,
                  series: [
                    ChartSeries(_tc(tr('anCancelRate')), const Color(0xFFEF4444), [for (final m in monthly) m.cancellationRate * 100]),
                    ChartSeries(_tc(tr('anNoShowRate')), const Color(0xFF94A3B8), [for (final m in monthly) m.noShowRate * 100]),
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
                title: _tc(tr('anPeakDays')),
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
                title: _tc(tr('anClientsTitle')),
                subtitle: _tc(tr('anClientsSub')),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DonutChart(
                      centerLabel: tr('navClients').toLowerCase(),
                      slices: [
                        DonutSlice(_tc(tr('anNewClients')), loyalty.newClients.toDouble(), const Color(0xFF60A5FA)),
                        DonutSlice(_tc(tr('anRepeatClients')), loyalty.repeatClients.toDouble(), const Color(0xFF6366F1)),
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
              title: _tc(tr('anMonthlyTable')),
              subtitle: _tc(tr('anLast12')),
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

  /// Pahalang na bars para sa bilang ng booking ayon sa kategorya.
  /// Pinakamaraming [n] lang; pinagsasama ang iba sa "Others" para hindi humaba
  /// ang chart (hal. dami ng bayan sa "Where are you from?").
  List<MapEntry<String, int>> _top(List<MapEntry<String, int>> entries, int n) {
    if (entries.length <= n + 1) return entries;
    final rest = entries.skip(n).fold<int>(0, (s, e) => s + e.value);
    return [...entries.take(n), MapEntry(tr('anOthers'), rest)];
  }

  Widget _countBars(List<MapEntry<String, int>> entries, Color color) {
    final total = entries.fold<int>(0, (s, e) => s + e.value);
    return HorizontalBarList(
      color: color,
      emptyText: tr('noData'),
      items: [
        for (final e in entries)
          BarItem(
            e.key.isEmpty ? tr('anNotRecorded') : e.key,
            e.value.toDouble(),
            trailing: '${e.value} · ${total == 0 ? '0' : (e.value * 100 / total).toStringAsFixed(0)}%',
          ),
      ],
    );
  }

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
        children: [seg(true, _tc(tr('anRevenue'))), seg(false, _tc(tr('bookingsWord')))],
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
          line(const Color(0xFFF59E0B), _tc(tr('anMovingAvg')), ma),
          line(const Color(0xFF6366F1), _tc(tr('anRegression')), reg),
          line(AppColors.primary, _tc(tr('anAlreadyBooked')), booked),
        ],
      ),
    );
  }

  Widget _monthlyTable(List<MonthStat> monthly, double width) {
    const flex = [4, 3, 4, 3, 3, 4, 4, 4, 4];
    final headers = [
      tr('rpcMonth'),
      tr('rpcBookings'),
      tr('anOccupancy'),
      tr('anColCancelled'),
      tr('anColNoShow'),
      tr('rpcBooked'),
      tr('rpcCollected'),
      tr('navExpenses'),
      tr('anNetProfit'),
    ];
    final rows = monthly.reversed.toList();
    final totalActive = rows.fold<int>(0, (s, m) => s + m.active);
    final totalBooked = rows.fold<double>(0, (s, m) => s + m.revenue);
    final totalCollected = rows.fold<double>(0, (s, m) => s + m.collected);
    final totalExpenses = rows.fold<double>(0, (s, m) => s + m.expenses);
    double avg(double Function(MonthStat) f) => rows.isEmpty ? 0 : rows.fold<double>(0, (s, m) => s + f(m)) / rows.length;

    Widget line(List<String> cells, {bool header = false, bool total = false, bool shade = false}) => Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          color: header
              ? AppColors.subtle
              : total
                  ? const Color(0xFFF1F5F9)
                  : shade
                      ? const Color(0xFFFAFBFC)
                      : Colors.white,
          child: Row(
            children: [
              for (var i = 0; i < cells.length; i++)
                Expanded(
                  flex: flex[i],
                  child: Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 12, right: i == cells.length - 1 ? 0 : 12),
                    child: Text(
                      header ? cells[i].toUpperCase() : cells[i],
                      textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: header
                          ? _caps
                          : TextStyle(
                              fontSize: 13.5,
                              fontWeight: total ? FontWeight.w800 : (i == 0 ? FontWeight.w600 : FontWeight.w500),
                              color: !total && i > 0 && cells[i].startsWith('0') ? AppColors.muted : AppColors.text,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                    ),
                  ),
                ),
            ],
          ),
        );

    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        line(headers, header: true),
        const Divider(height: 1),
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const Divider(height: 1, color: Color(0xFFEEF2F6)),
          line([
            '${monthNames[rows[r].month.month - 1]} ${rows[r].month.year}',
            '${rows[r].active}',
            _pct(rows[r].occupancy),
            _pct(rows[r].cancellationRate),
            _pct(rows[r].noShowRate),
            peso(rows[r].revenue),
            peso(rows[r].collected),
            peso(rows[r].expenses),
            peso(rows[r].profit),
          ], shade: r.isOdd),
        ],
        const Divider(height: 1, thickness: 1.5),
        line([
          tr('anTotalAvg'),
          '$totalActive',
          _pct(avg((m) => m.occupancy)),
          _pct(avg((m) => m.cancellationRate)),
          _pct(avg((m) => m.noShowRate)),
          peso(totalBooked),
          peso(totalCollected),
          peso(totalExpenses),
          peso(totalBooked - totalExpenses),
        ], total: true),
      ],
    );
    if (width >= 1200) return table;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(width: 1200, child: table),
    );
  }
}
