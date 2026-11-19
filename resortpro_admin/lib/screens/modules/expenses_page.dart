import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/charts.dart';

/// Gastos ng resort: kuryente, tubig, chlorine, sahod, at iba pa.
/// Ginagamit ng Analytics para makita ang tunay na kita (net profit).
class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key, required this.data, required this.onChanged});

  final AdminData data;
  final VoidCallback onChanged;

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  /// 0 = lahat ng buwan ng taon, 1–12 = isang buwan.
  int _month = 0;
  late int _year = DateTime.now().year;

  static const _caps = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.muted);

  List<Map<String, dynamic>> get _yearExpenses =>
      widget.data.expenses.where((e) => expenseDateOf(e)?.year == _year).toList();

  double _sum(Iterable<Map<String, dynamic>> list) => list.fold(0.0, (s, e) => s + asDouble(e['amount']));

  double _revenueOfYear() => widget.data.activeBookings
      .where((b) => bookingDateOf(b)?.year == _year)
      .fold(0.0, (s, b) => s + totalOf(b));

  Future<void> _add() async {
    final saved = await showDialog<bool>(context: context, builder: (_) => const _ExpenseDialog());
    if (saved == true) {
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('exSaved'))));
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('exDeleteQ')),
        content: Text('${e['category']} · ${peso(asDouble(e['amount']))} · ${formatDate(expenseDateOf(e))}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.from('expenses').delete().eq('id', e['id']);
      widget.onChanged();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('exFailed')}: $err')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final yearList = _yearExpenses;
    final yearTotal = _sum(yearList);
    final thisMonth = _sum(yearList.where((e) => expenseDateOf(e)?.month == now.month));
    final monthsWithData = {for (final e in yearList) expenseDateOf(e)!.month};
    final avg = monthsWithData.isEmpty ? 0.0 : yearTotal / monthsWithData.length;
    final revenue = _revenueOfYear();
    final profit = revenue - yearTotal;

    final byCategory = <String, double>{};
    for (final e in yearList) {
      final c = '${e['category']}';
      byCategory[c] = (byCategory[c] ?? 0) + asDouble(e['amount']);
    }
    final categories = byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final shown = _month == 0 ? yearList : yearList.where((e) => expenseDateOf(e)?.month == _month).toList();
    final years = {now.year, for (final e in widget.data.expenses) expenseDateOf(e)?.year ?? now.year}.toList()..sort();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return ListView(
          padding: pageInsets(context),
          children: [
            Text(tr('exIntro'), style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 14),
            _overviewCard(width, [
              _tile(tr('exKMonth').toUpperCase(), monthNames[now.month - 1], peso(thisMonth), Colors.white,
                  Icons.calendar_today_outlined),
              _tile(tr('exKYear').toUpperCase(), '$_year', peso(yearTotal), const Color(0xFFF87171),
                  Icons.receipt_long_outlined),
              _tile(tr('exKAvg').toUpperCase(), tr('exKAvgSub', {'n': monthsWithData.length}), peso(avg),
                  const Color(0xFFFBBF24), Icons.equalizer_rounded),
              _tile(tr('exKRevenue').toUpperCase(), tr('exKRevenueSub'), peso(revenue), const Color(0xFF4ADE80),
                  Icons.payments_outlined),
              _tile(tr('exKProfit').toUpperCase(), tr('exKProfitSub'), peso(profit),
                  profit >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFF87171), Icons.account_balance_wallet_outlined),
              _tile(tr('exKTop').toUpperCase(), categories.isEmpty ? '—' : peso(categories.first.value),
                  categories.isEmpty ? '—' : categories.first.key, const Color(0xFF60A5FA), Icons.pie_chart_outline),
            ]),
            const SizedBox(height: 18),
            _section(
              icon: Icons.pie_chart_outline,
              title: tr('exByCategory'),
              subtitle: '$_year',
              child: categories.isEmpty
                  ? Text(tr('exNone'), style: const TextStyle(color: AppColors.muted))
                  : HorizontalBarList(
                      color: const Color(0xFFF87171),
                      valueFormat: peso,
                      items: [for (final c in categories) BarItem(c.key, c.value)],
                    ),
            ),
            const SizedBox(height: 18),
            _section(
              icon: Icons.receipt_long_outlined,
              title: tr('exListTitle'),
              subtitle: tr('exListSub', {'n': shown.length, 'total': peso(_sum(shown))}),
              padBody: false,
              trailing: Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _dropdown<int>(
                    value: _year,
                    items: {for (final y in years) y: '$y'},
                    onChanged: (v) => setState(() {
                      _year = v;
                      _month = 0;
                    }),
                  ),
                  _dropdown<int>(
                    value: _month,
                    items: {0: tr('exAllMonths'), for (var m = 1; m <= 12; m++) m: monthNames[m - 1]},
                    onChanged: (v) => setState(() => _month = v),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.ink, foregroundColor: Colors.white),
                    onPressed: _add,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(tr('exAdd')),
                  ),
                ],
              ),
              child: shown.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(28),
                      child: Center(child: Text(tr('exNone'), style: const TextStyle(color: AppColors.muted))),
                    )
                  : _table(shown, width),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Widget _table(List<Map<String, dynamic>> rows, double width) {
    const flex = [3, 4, 6, 3, 1];
    Widget line(List<Widget> cells, {bool header = false, bool shade = false}) => Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          color: header ? AppColors.subtle : (shade ? const Color(0xFFFAFBFC) : Colors.white),
          child: Row(
            children: [
              for (var i = 0; i < cells.length; i++)
                Expanded(
                  flex: flex[i],
                  child: Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
                    child: Align(alignment: i == 3 || i == 4 ? Alignment.centerRight : Alignment.centerLeft, child: cells[i]),
                  ),
                ),
            ],
          ),
        );
    Text head(String t) => Text(t.toUpperCase(), style: _caps);
    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        line([head(tr('fieldDate')), head(tr('exCategory')), head(tr('exNote')), head(tr('rpcAmount')), const SizedBox()],
            header: true),
        const Divider(height: 1),
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const Divider(height: 1, color: Color(0xFFEEF2F6)),
          line([
            Text(formatDate(expenseDateOf(rows[r])), style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('${rows[r]['category']}'),
            Text(
              '${rows[r]['note'] ?? ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            Text(peso(asDouble(rows[r]['amount'])), style: const TextStyle(fontWeight: FontWeight.w700)),
            IconButton(
              tooltip: tr('delete'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, size: 19, color: AppColors.muted),
              onPressed: () => _delete(rows[r]),
            ),
          ], shade: r.isOdd),
        ],
      ],
    );
    if (width >= 760) return table;
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: 760, child: table));
  }

  Widget _dropdown<T>({required T value, required Map<T, String> items, required ValueChanged<T> onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          borderRadius: BorderRadius.circular(12),
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.text),
          items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
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
              const Icon(Icons.receipt_long_rounded, color: AppColors.inkText, size: 20),
              const SizedBox(width: 8),
              Text(tr('exOverview'),
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                        if (subtitle != null)
                          Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      ],
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
}

/// Dialog para magdagdag ng gastos.
class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog();

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  String _category = expenseCategories.first;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2022),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = tr('exAmountError'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.from('expenses').insert({
        'expense_date': dateKey(_date),
        'category': _category,
        'amount': amount,
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = '${tr('exFailed')}: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('exAdd')),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.all(16)),
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(formatDate(_date)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: InputDecoration(labelText: tr('exCategory'), border: const OutlineInputBorder()),
              items: [for (final c in expenseCategories) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(
                labelText: tr('rpcAmount'),
                prefixText: '₱ ',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: InputDecoration(labelText: tr('exNoteOptional'), border: const OutlineInputBorder()),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: Text(tr('cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.ink, foregroundColor: Colors.white),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? tr('saving') : tr('save')),
        ),
      ],
    );
  }
}
