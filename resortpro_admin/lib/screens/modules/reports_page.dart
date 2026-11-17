import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../services/report_builder.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/list_controls.dart';

/// Reports: daily/monthly sales, bookings list, at collections by method.
/// May preview sa screen, at pwedeng i-download bilang PDF o Excel, o i-print.
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.data});

  final AdminData data;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  ReportType _type = ReportType.dailySales;
  late DateTimeRange _range = _thisMonth();
  bool _exporting = false;

  static DateTimeRange _thisMonth() {
    final now = DateTime.now();
    return DateTimeRange(start: DateTime(now.year, now.month, 1), end: DateTime(now.year, now.month + 1, 0));
  }

  Map<String, DateTimeRange> get _presets {
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    return {
      tr('rpToday'): DateTimeRange(start: today, end: today),
      tr('rpThisMonth'): _thisMonth(),
      tr('rpLastMonth'): DateTimeRange(
        start: DateTime(now.year, now.month - 1, 1),
        end: DateTime(now.year, now.month, 0),
      ),
      tr('rpThisYear'): DateTimeRange(start: DateTime(now.year, 1, 1), end: DateTime(now.year, 12, 31)),
      tr('rpLast12Months'): DateTimeRange(start: DateTime(now.year - 1, now.month, now.day + 1), end: today),
    };
  }

  String _typeLabel(ReportType t) => switch (t) {
        ReportType.dailySales => tr('rpDailySales'),
        ReportType.monthlySales => tr('rpMonthlySales'),
        ReportType.bookings => tr('rpBookingsList'),
        ReportType.collections => tr('rpCollections'),
      };

  IconData _typeIcon(ReportType t) => switch (t) {
        ReportType.dailySales => Icons.today_outlined,
        ReportType.monthlySales => Icons.calendar_view_month_outlined,
        ReportType.bookings => Icons.list_alt_outlined,
        ReportType.collections => Icons.account_balance_wallet_outlined,
      };

  static bool _sameRange(DateTimeRange a, DateTimeRange b) =>
      DateUtils.isSameDay(a.start, b.start) && DateUtils.isSameDay(a.end, b.end);


  Future<void> _pickRange() async {
    final picked = await DateRangeFilter.pickCustom(context, _range);
    if (picked != null) setState(() => _range = picked);
  }

  static const _caps = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.muted);

  /// Malaking dropdown na may label sa itaas (REPORT / PERIOD).
  Widget _dropdownBox<T>({
    required String label,
    required IconData icon,
    required String value,
    String? sub,
    required List<PopupMenuEntry<T>> Function(BuildContext) items,
    required ValueChanged<T> onSelected,
    double width = 300,
  }) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _caps),
          const SizedBox(height: 6),
          PopupMenuButton<T>(
            tooltip: label,
            position: PopupMenuPosition.under,
            constraints: BoxConstraints(minWidth: width, maxWidth: width + 40),
            onSelected: onSelected,
            itemBuilder: items,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
                boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1))],
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: AppColors.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        if (sub != null)
                          Text(sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.expand_more_rounded, color: AppColors.muted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export(Future<void> Function() action) async {
    setState(() => _exporting = true);
    try {
      await action();
      if (!mounted) return;
      showToast(context, tr('rpExported'));
    } catch (e) {
      if (!mounted) return;
      showToast(context, tr('failed', {'e': e}));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = ReportBuilder(widget.data).build(_type, _range);
    String? presetName;
    for (final e in _presets.entries) {
      if (_sameRange(e.value, _range)) presetName = e.key;
    }
    final rangeText = DateUtils.isSameDay(_range.start, _range.end)
        ? formatDate(_range.start)
        : '${formatDate(_range.start)} – ${formatDate(_range.end)}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 700;
        final boxWidth = narrow ? constraints.maxWidth - 64 : 300.0;

        final controls = AppCard(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.end,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _dropdownBox<ReportType>(
                      label: tr('rpReportLabel'),
                      icon: _typeIcon(_type),
                      value: _typeLabel(_type),
                      width: boxWidth,
                      onSelected: (t) => setState(() => _type = t),
                      items: (context) => [
                        for (final t in ReportType.values)
                          CheckedPopupMenuItem(
                            value: t,
                            checked: _type == t,
                            child: Text(_typeLabel(t)),
                          ),
                      ],
                    ),
                    _dropdownBox<String>(
                      label: tr('rpPeriodLabel'),
                      icon: Icons.calendar_month_outlined,
                      value: presetName ?? tr('rpCustomRange'),
                      sub: rangeText,
                      width: boxWidth,
                      onSelected: (v) {
                        if (v == '__custom') {
                          _pickRange();
                        } else {
                          setState(() => _range = _presets[v]!);
                        }
                      },
                      items: (context) => [
                        for (final e in _presets.entries)
                          CheckedPopupMenuItem(value: e.key, checked: presetName == e.key, child: Text(e.key)),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: '__custom',
                          child: Row(
                            children: [
                              const Icon(Icons.edit_calendar_outlined, size: 18, color: AppColors.primary),
                              const SizedBox(width: 10),
                              Text(presetName == null ? '${tr('drCustom')} ✓' : tr('drCustom')),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr('rpExportLabel'), style: _caps),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18)),
                          onPressed: _exporting ? null : () => _export(() => ReportBuilder.downloadPdf(report)),
                          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                          label: Text(tr('rpDownloadPdf')),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18)),
                          onPressed: _exporting ? null : () => _export(() => ReportBuilder.downloadExcel(report)),
                          icon: const Icon(Icons.grid_on_outlined, size: 18),
                          label: Text(tr('rpDownloadExcel')),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18)),
                          onPressed: _exporting ? null : () => _export(() => ReportBuilder.printReport(report)),
                          icon: const Icon(Icons.print_outlined, size: 18),
                          label: Text(tr('rpPrint')),
                        ),
                        if (_exporting)
                          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );

        return ListView(
          padding: pageInsets(context),
          children: [
            Text(tr('rpSubtitle'), style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 14),
            controls,
            const SizedBox(height: 18),
            _reportCard(report, constraints.maxWidth),
            const SizedBox(height: 10),
            Text(tr('rpNote'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ],
        );
      },
    );
  }

  Widget _reportCard(ReportTable report, double width) {
    final lines = report.subtitle.split('\n');
    final totals = report.totals;
    final cols = report.headers.length;
    final flex = report.flex.length == cols ? report.flex : List.filled(cols, 1);
    final tableWidth = width < 1000 ? 1000.0 : null;

    Widget cell(int i, Widget child) => Expanded(
          flex: flex[i],
          child: Padding(
            padding: EdgeInsets.only(right: i == cols - 1 ? 0 : 16),
            child: child,
          ),
        );
    TextAlign align(int i) => report.numericColumns.contains(i) ? TextAlign.right : TextAlign.left;

    Widget row(List<Object> values, {bool header = false, bool total = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          color: header ? AppColors.subtle : (total ? const Color(0xFFF1F5F9) : null),
          child: Row(
            children: [
              for (var i = 0; i < cols; i++)
                cell(
                  i,
                  Text(
                    header ? '${values[i]}'.toUpperCase() : report.cell(values[i], i),
                    textAlign: align(i),
                    maxLines: header ? 2 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: header
                        ? _caps
                        : TextStyle(
                            fontSize: 13.5,
                            fontWeight: total ? FontWeight.w800 : (i == 0 ? FontWeight.w600 : FontWeight.w400),
                          ),
                  ),
                ),
            ],
          ),
        );

    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(report.headers, header: true),
        const Divider(height: 1),
        for (var r = 0; r < report.rows.length; r++) ...[
          if (r > 0) const Divider(height: 1),
          row(report.rows[r]),
        ],
        if (totals != null) ...[
          const Divider(height: 1, thickness: 1.5),
          row(totals, total: true),
        ],
      ],
    );

    return AppCard(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(12)),
                  child: Icon(_typeIcon(_type), color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(report.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      Text(lines.first, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFFE6EBF0), borderRadius: BorderRadius.circular(20)),
                  child: Text(tr('rpRows', {'n': report.rows.length}),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
                ),
              ],
            ),
          ),
          // Mga kabuuan ng bawat numerong column
          if (totals != null && report.rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final i in (report.numericColumns.toList()..sort()))
                    Container(
                      width: 170,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: AppColors.subtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(report.headers[i].toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.muted, letterSpacing: 0.5)),
                          const SizedBox(height: 2),
                          Text(report.cell(totals[i], i),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: report.moneyColumns.contains(i) ? AppColors.primary : AppColors.text,
                              )),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (lines.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Text(lines.skip(1).join('\n'),
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          const Divider(height: 1),
          if (report.rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: EmptyState(icon: Icons.insert_chart_outlined, message: tr('rpNoData')),
            )
          else if (tableWidth == null)
            table
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: tableWidth, child: table),
            ),
        ],
      ),
    );
  }
}
