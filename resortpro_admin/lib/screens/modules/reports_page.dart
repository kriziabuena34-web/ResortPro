import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../services/report_builder.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_widgets.dart';

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

  /// Tugma ba ang napiling petsa sa isa sa mga preset (Today, This month, …)?
  bool get _isPreset => _presets.values.any((p) => _sameRange(p, _range));

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 3, 12, 31),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  Widget _label(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 1.1,
            fontWeight: FontWeight.w800,
            color: AppColors.muted,
          ),
        ),
      );

  /// Iisang itsura para sa report type at period: puno ang kulay kapag napili.
  Widget _chip({IconData? icon, required String label, required bool selected, required VoidCallback onTap}) {
    final color = selected ? Colors.white : AppColors.text;
    return ChoiceChip(
      showCheckmark: false,
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primary,
      backgroundColor: Colors.white,
      side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: selected ? Colors.white : AppColors.primary),
            const SizedBox(width: 6),
          ],
          Text(label, style: TextStyle(color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
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
    final theme = Theme.of(context);
    final report = ReportBuilder(widget.data).build(_type, _range);

    return ListView(
      padding: pageInsets(context),
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- Uri ng report ----
              _label(theme, tr('rpReportLabel')),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in ReportType.values)
                    _chip(
                      icon: _typeIcon(t),
                      label: _typeLabel(t),
                      selected: _type == t,
                      onTap: () => setState(() => _type = t),
                    ),
                ],
              ),
              const SizedBox(height: 18),

              // ---- Petsa (period) ----
              _label(theme, tr('rpPeriodLabel')),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in _presets.entries)
                    _chip(
                      label: e.key,
                      selected: _sameRange(_range, e.value),
                      onTap: () => setState(() => _range = e.value),
                    ),
                  // Sariling petsa: naka-highlight kapag hindi tugma sa alinmang preset.
                  _chip(
                    icon: Icons.date_range,
                    label: _isPreset ? tr('rpCustomRange') : '${formatDate(_range.start)} – ${formatDate(_range.end)}',
                    selected: !_isPreset,
                    onTap: _pickRange,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${formatDate(_range.start)} – ${formatDate(_range.end)}',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Divider(height: 28),

              // ---- Export ----
              _label(theme, tr('rpExportLabel')),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _exporting ? null : () => _export(() => ReportBuilder.downloadPdf(report)),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(tr('rpDownloadPdf')),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _exporting ? null : () => _export(() => ReportBuilder.downloadExcel(report)),
                    icon: const Icon(Icons.grid_on_outlined),
                    label: Text(tr('rpDownloadExcel')),
                  ),
                  OutlinedButton.icon(
                    onPressed: _exporting ? null : () => _export(() => ReportBuilder.printReport(report)),
                    icon: const Icon(Icons.print_outlined),
                    label: Text(tr('rpPrint')),
                  ),
                  if (_exporting)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ---- Preview ----
        SectionCard(
          title: report.title,
          subtitle: report.subtitle,
          child: report.rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text(tr('rpNoData'))),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStatePropertyAll(theme.colorScheme.primaryContainer),
                    columnSpacing: 24,
                    dataRowMinHeight: 40,
                    columns: [
                      for (var i = 0; i < report.headers.length; i++)
                        DataColumn(
                          numeric: report.numericColumns.contains(i),
                          label: Text(report.headers[i], style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                    ],
                    rows: [
                      for (final r in report.rows)
                        DataRow(cells: [for (var i = 0; i < r.length; i++) DataCell(Text(report.cell(r[i], i)))]),
                      if (report.totals != null)
                        DataRow(
                          color: WidgetStatePropertyAll(theme.colorScheme.surfaceContainerHighest),
                          cells: [
                            for (var i = 0; i < report.totals!.length; i++)
                              DataCell(Text(
                                report.cell(report.totals![i], i),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              )),
                          ],
                        ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 8),
        Text(tr('rpNote'), style: theme.textTheme.bodySmall),
      ],
    );
  }
}
