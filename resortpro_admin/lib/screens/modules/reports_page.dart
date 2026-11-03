import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../services/report_builder.dart';
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in ReportType.values)
                      ChoiceChip(
                        avatar: Icon(_typeIcon(t), size: 18),
                        label: Text(_typeLabel(t)),
                        selected: _type == t,
                        onSelected: (_) => setState(() => _type = t),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // ---- Date range ----
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.date_range, size: 18),
                      label: Text('${formatDate(_range.start)} – ${formatDate(_range.end)}'),
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(now.year - 5),
                          lastDate: DateTime(now.year + 3, 12, 31),
                          initialDateRange: _range,
                        );
                        if (picked != null) setState(() => _range = picked);
                      },
                    ),
                    for (final e in _presets.entries)
                      ActionChip(label: Text(e.key), onPressed: () => setState(() => _range = e.value)),
                  ],
                ),
                const SizedBox(height: 16),

                // ---- Export buttons ----
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
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
                        DataRow(cells: [for (final c in r) DataCell(Text(ReportBuilder.cellText(c)))]),
                      if (report.totals != null)
                        DataRow(
                          color: WidgetStatePropertyAll(theme.colorScheme.surfaceContainerHighest),
                          cells: [
                            for (final c in report.totals!)
                              DataCell(Text(
                                ReportBuilder.cellText(c),
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
