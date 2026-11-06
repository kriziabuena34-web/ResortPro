import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../widgets/admin_widgets.dart';

/// Availability control:
///  • Blocked dates (maintenance, private event, fully booked)
///  • Seasonal pricing (weekend, holiday, peak season)
///  • Price preview ng susunod na 30 araw
class AvailabilityPage extends StatefulWidget {
  const AvailabilityPage({super.key, required this.data, required this.onChanged});

  final AdminData data;
  final Future<void> Function() onChanged;

  @override
  State<AvailabilityPage> createState() => _AvailabilityPageState();
}

enum _Section { blocked, pricing, preview }

class _AvailabilityPageState extends State<AvailabilityPage> {
  final supabase = Supabase.instance.client;
  _Section _section = _Section.blocked;
  bool _showPast = false;
  String? _previewPackageId;

  static const _weekdayKeys = ['dowMon', 'dowTue', 'dowWed', 'dowThu', 'dowFri', 'dowSat', 'dowSun'];

  String _packageName(dynamic id) =>
      id == null ? tr('avAllPackages') : '${widget.data.packageById(id)?['name'] ?? '#$id'}';

  // -------------------------------------------------------------------------
  // Blocked dates
  // -------------------------------------------------------------------------

  Future<void> _addBlock() async {
    DateTimeRange? range;
    String? packageId;
    final reason = TextEditingController();
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) {
          final conflicts = range == null
              ? <Map<String, dynamic>>[]
              : widget.data.activeBookings.where((b) {
                  final d = bookingDateOf(b);
                  if (d == null) return false;
                  if (d.isBefore(range!.start) || d.isAfter(range!.end)) return false;
                  return packageId == null || '${b['package_id']}' == packageId;
                }).toList();

          return AlertDialog(
            title: Text(tr('avBlockTitle')),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.date_range),
                    label: Text(range == null
                        ? tr('avPickDates')
                        : DateUtils.isSameDay(range!.start, range!.end)
                            ? formatDate(range!.start)
                            : '${formatDate(range!.start)} – ${formatDate(range!.end)}'),
                    onPressed: () async {
                      final now = DateTime.now();
                      final picked = await showDateRangePicker(
                        context: dialogContext,
                        firstDate: DateTime(now.year, now.month, now.day),
                        lastDate: DateTime(now.year + 3, 12, 31),
                      );
                      if (picked != null) setDialog(() => range = picked);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: packageId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('avAppliesTo')),
                    items: [
                      DropdownMenuItem<String?>(value: null, child: Text(tr('avAllPackages'))),
                      for (final p in widget.data.packages)
                        DropdownMenuItem<String?>(value: '${p['id']}', child: Text('${p['name']}')),
                    ],
                    onChanged: (v) => setDialog(() => packageId = v),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final key in const ['avReasonMaintenance', 'avReasonPrivate', 'avReasonFull', 'avReasonHoliday'])
                        ActionChip(label: Text(tr(key)), onPressed: () => reason.text = tr(key)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reason,
                    decoration: InputDecoration(labelText: tr('avReason')),
                  ),
                  if (conflicts.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE08A00).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(tr('avConflicts', {'n': conflicts.length})),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr('cancel'))),
              FilledButton(
                onPressed: () {
                  if (range == null) {
                    setDialog(() => error = tr('avPickDates'));
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                child: Text(tr('avBlockBtn')),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || range == null) return;

    final rows = <Map<String, dynamic>>[];
    for (var d = DateUtils.dateOnly(range!.start);
        !d.isAfter(range!.end);
        d = DateTime(d.year, d.month, d.day + 1)) {
      rows.add({
        'block_date': dateKey(d),
        'package_id': packageId == null ? null : int.tryParse(packageId!),
        'reason': reason.text.trim().isEmpty ? null : reason.text.trim(),
      });
    }

    try {
      await supabase.from('blocked_dates').insert(rows);
      if (!mounted) return;
      showToast(context, tr('avBlocked', {'n': rows.length}));
      await widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      showToast(context, tr('failed', {'e': e}));
    }
  }

  Future<void> _removeBlock(Map<String, dynamic> block) async {
    try {
      await supabase.from('blocked_dates').delete().eq('id', block['id']);
      if (!mounted) return;
      showToast(context, tr('avUnblocked'));
      await widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      showToast(context, tr('failed', {'e': e}));
    }
  }

  // -------------------------------------------------------------------------
  // Pricing rules
  // -------------------------------------------------------------------------

  Future<void> _editRule([Map<String, dynamic>? rule]) async {
    final name = TextEditingController(text: '${rule?['name'] ?? ''}');
    final value = TextEditingController(text: rule == null ? '' : asDouble(rule['value']).toStringAsFixed(0));
    final priority = TextEditingController(text: '${rule?['priority'] ?? 0}');
    String? packageId = rule?['package_id']?.toString();
    String type = '${rule?['adjust_type'] ?? 'percent'}';
    DateTime? start = parseDate(rule?['start_date']);
    DateTime? end = parseDate(rule?['end_date']);
    final days = <int>{...((rule?['days_of_week'] as List?)?.map(asInt) ?? const <int>[])};
    String? error;

    final saved = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: Text(rule == null ? tr('avNewRule') : tr('avEditRule')),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.weekend_outlined, size: 18),
                        label: Text(tr('avPresetWeekend')),
                        onPressed: () => setDialog(() {
                          name.text = tr('avPresetWeekend');
                          type = 'percent';
                          value.text = '20';
                          days
                            ..clear()
                            ..addAll([6, 7]);
                          start = null;
                          end = null;
                        }),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.wb_sunny_outlined, size: 18),
                        label: Text(tr('avPresetSummer')),
                        onPressed: () => setDialog(() {
                          final y = DateTime.now().year + (DateTime.now().month > 5 ? 1 : 0);
                          name.text = '${tr('avPresetSummer')} $y';
                          type = 'percent';
                          value.text = '15';
                          days.clear();
                          start = DateTime(y, 3, 15);
                          end = DateTime(y, 5, 31);
                        }),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.church_outlined, size: 18),
                        label: Text(tr('avPresetHolyWeek')),
                        onPressed: () => setDialog(() {
                          name.text = tr('avPresetHolyWeek');
                          type = 'percent';
                          value.text = '30';
                          days.clear();
                          priority.text = '10';
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: name, decoration: InputDecoration(labelText: tr('avRuleName'))),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: packageId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('avAppliesTo')),
                    items: [
                      DropdownMenuItem<String?>(value: null, child: Text(tr('avAllPackages'))),
                      for (final p in widget.data.packages)
                        DropdownMenuItem<String?>(value: '${p['id']}', child: Text('${p['name']}')),
                    ],
                    onChanged: (v) => setDialog(() => packageId = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: type,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: tr('avAdjustType')),
                          items: [
                            DropdownMenuItem(value: 'percent', child: Text(tr('avTypePercent'))),
                            DropdownMenuItem(value: 'fixed_amount', child: Text(tr('avTypeFixed'))),
                            DropdownMenuItem(value: 'set_price', child: Text(tr('avTypeSet'))),
                          ],
                          onChanged: (v) => setDialog(() => type = v ?? 'percent'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 130,
                        child: TextField(
                          controller: value,
                          keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                          decoration: InputDecoration(
                            labelText: tr('avValue'),
                            suffixText: type == 'percent' ? '%' : null,
                            prefixText: type == 'percent' ? null : '₱ ',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(tr('avValueHint'), style: Theme.of(dialogContext).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Text(tr('avDateRange'), style: Theme.of(dialogContext).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.date_range, size: 18),
                        label: Text(start == null
                            ? tr('avAnyDate')
                            : '${formatDate(start)} – ${formatDate(end ?? start)}'),
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDateRangePicker(
                            context: dialogContext,
                            firstDate: DateTime(now.year - 1),
                            lastDate: DateTime(now.year + 3, 12, 31),
                            initialDateRange: start == null
                                ? null
                                : DateTimeRange(start: start!, end: end ?? start!),
                          );
                          if (picked != null) {
                            setDialog(() {
                              start = picked.start;
                              end = picked.end;
                            });
                          }
                        },
                      ),
                      if (start != null)
                        TextButton(
                          onPressed: () => setDialog(() {
                            start = null;
                            end = null;
                          }),
                          child: Text(tr('clear')),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(tr('avDays'), style: Theme.of(dialogContext).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var d = 1; d <= 7; d++)
                        FilterChip(
                          label: Text(tr(_weekdayKeys[d - 1])),
                          selected: days.contains(d),
                          onSelected: (v) => setDialog(() => v ? days.add(d) : days.remove(d)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(tr('avDaysHint'), style: Theme.of(dialogContext).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 160,
                    child: TextField(
                      controller: priority,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: tr('avPriority')),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(tr('avPriorityHint'), style: Theme.of(dialogContext).textTheme.bodySmall),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('cancel'))),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(value.text.replaceAll(',', ''));
                if (name.text.trim().isEmpty || v == null) {
                  setDialog(() => error = tr('avRuleError'));
                  return;
                }
                Navigator.pop(dialogContext, {
                  'name': name.text.trim(),
                  'package_id': packageId == null ? null : int.tryParse(packageId!),
                  'adjust_type': type,
                  'value': v,
                  'start_date': start == null ? null : dateKey(start!),
                  'end_date': start == null ? null : dateKey(end ?? start!),
                  'days_of_week': days.isEmpty ? null : (days.toList()..sort()),
                  'priority': int.tryParse(priority.text) ?? 0,
                });
              },
              child: Text(tr('save')),
            ),
          ],
        ),
      ),
    );
    if (saved == null) return;

    try {
      if (rule == null) {
        await supabase.from('pricing_rules').insert(saved);
      } else {
        await supabase.from('pricing_rules').update(saved).eq('id', rule['id']);
      }
      if (!mounted) return;
      showToast(context, tr('avRuleSaved'));
      await widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      showToast(context, tr('failed', {'e': e}));
    }
  }

  Future<void> _toggleRule(Map<String, dynamic> rule, bool active) async {
    try {
      await supabase.from('pricing_rules').update({'is_active': active}).eq('id', rule['id']);
      await widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      showToast(context, tr('failed', {'e': e}));
    }
  }

  Future<void> _deleteRule(Map<String, dynamic> rule) async {
    final ok = await confirmDialog(
      context,
      title: tr('avDeleteRuleQ'),
      message: '${rule['name']}',
      confirmText: tr('delete'),
      destructive: true,
    );
    if (!ok) return;
    try {
      await supabase.from('pricing_rules').delete().eq('id', rule['id']);
      await widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      showToast(context, tr('failed', {'e': e}));
    }
  }

  String _ruleSummary(Map<String, dynamic> r) {
    final v = asDouble(r['value']);
    final adj = switch (r['adjust_type']) {
      'percent' => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(0)}%',
      'fixed_amount' => '${v >= 0 ? '+' : '−'}${peso(v.abs())}',
      _ => '= ${peso(v)}',
    };
    final start = parseDate(r['start_date']);
    final end = parseDate(r['end_date']);
    final dates = start == null ? tr('avAnyDate') : '${formatDate(start)} – ${formatDate(end ?? start)}';
    final days = (r['days_of_week'] as List?)?.map(asInt).toList() ?? const <int>[];
    final dayText = days.isEmpty ? tr('avEveryDay') : days.map((d) => tr(_weekdayKeys[d - 1])).join(', ');
    return '$adj · ${_packageName(r['package_id'])}\n$dates · $dayText';
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final fab = switch (_section) {
      _Section.blocked => AppFab(icon: Icons.block, label: tr('avBlockBtn'), onPressed: _addBlock),
      _Section.pricing => AppFab(icon: Icons.add, label: tr('avNewRule'), onPressed: () => _editRule()),
      _Section.preview => null,
    };

    return ModuleBody(
      fab: fab,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pageGutter(context), pageGutter(context) - 4, pageGutter(context), 0),
            child: PillTabs<_Section>(
              value: _section,
              onChanged: (v) => setState(() => _section = v),
              items: [
                (value: _Section.blocked, icon: Icons.event_busy, label: tr('avBlockedTab')),
                (value: _Section.pricing, icon: Icons.sell_outlined, label: tr('avPricingTab')),
                (value: _Section.preview, icon: Icons.preview_outlined, label: tr('avPreviewTab')),
              ],
            ),
          ),
          Expanded(
            child: switch (_section) {
              _Section.blocked => _buildBlocked(),
              _Section.pricing => _buildPricing(),
              _Section.preview => _buildPreview(),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBlocked() {
    final theme = Theme.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final blocks = widget.data.blockedDates.where((b) {
      final d = parseDate(b['block_date']);
      return d != null && (_showPast || !DateUtils.dateOnly(d).isBefore(today));
    }).toList();

    return ListView(
      padding: pageInsets(context, fab: true),
      children: [
        GlassPanel(
          child: Row(
            children: [
              Expanded(child: Text(tr('avBlockedHint'), style: theme.textTheme.bodyMedium)),
              const SizedBox(width: 12),
              FilterChip(
                label: Text(tr('avShowPast')),
                selected: _showPast,
                onSelected: (v) => setState(() => _showPast = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (blocks.isEmpty)
          EmptyState(icon: Icons.event_available, message: tr('avNoBlocks'))
        else
          AppCard(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < blocks.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.errorContainer,
                      child: Icon(Icons.block, color: theme.colorScheme.error),
                    ),
                    title: Text(formatDate(parseDate(blocks[i]['block_date']))),
                    subtitle: Text(
                      '${_packageName(blocks[i]['package_id'])}'
                      '${'${blocks[i]['reason'] ?? ''}'.isEmpty ? '' : ' · ${blocks[i]['reason']}'}',
                    ),
                    trailing: TextButton.icon(
                      onPressed: () => _removeBlock(blocks[i]),
                      icon: const Icon(Icons.lock_open, size: 18),
                      label: Text(tr('avUnblock')),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPricing() {
    final theme = Theme.of(context);
    final rules = widget.data.pricingRules;

    return ListView(
      padding: pageInsets(context, fab: true),
      children: [
        GlassPanel(child: Text(tr('avPricingHint'), style: theme.textTheme.bodyMedium)),
        const SizedBox(height: 16),
        if (rules.isEmpty)
          EmptyState(icon: Icons.sell_outlined, message: tr('avNoRules'))
        else
          for (final r in rules)
            AppCard(
              margin: const EdgeInsets.only(bottom: 16),
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text('${r['priority'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                title: Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(_ruleSummary(r)),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(value: r['is_active'] != false, onChanged: (v) => _toggleRule(r, v)),
                    IconButton(tooltip: tr('avEditRule'), onPressed: () => _editRule(r), icon: const Icon(Icons.edit_outlined)),
                    IconButton(
                      tooltip: tr('delete'),
                      onPressed: () => _deleteRule(r),
                      icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildPreview() {
    final theme = Theme.of(context);
    final packages = widget.data.packages;
    if (packages.isEmpty) return EmptyState(icon: Icons.inventory_2_outlined, message: tr('noPackages'));

    final pkg = widget.data.packageById(_previewPackageId) ?? packages.first;
    final base = asDouble(pkg['price']);
    final today = DateUtils.dateOnly(DateTime.now());
    final days = [for (var i = 0; i < 30; i++) DateTime(today.year, today.month, today.day + i)];

    return ListView(
      padding: pageInsets(context),
      children: [
        GlassPanel(child: Text(tr('avPreviewHint'), style: theme.textTheme.bodyMedium)),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: '${pkg['id']}',
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('navPackages')),
          items: [
            for (final p in packages)
              DropdownMenuItem(value: '${p['id']}', child: Text('${p['name']} · ${peso(asDouble(p['price']))}')),
          ],
          onChanged: (v) => setState(() => _previewPackageId = v),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final d in days) _dayTile(theme, pkg, d, base),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _legend(theme.colorScheme.surfaceContainerHighest, tr('avLegendBase')),
            _legend(const Color(0xFFFFE7C2), tr('avLegendHigher')),
            _legend(const Color(0xFFD7F2E1), tr('avLegendLower')),
            _legend(theme.colorScheme.errorContainer, tr('avLegendBlocked')),
            _legend(const Color(0xFFDDE6FF), tr('avLegendBooked')),
          ],
        ),
      ],
    );
  }

  Widget _dayTile(ThemeData theme, Map<String, dynamic> pkg, DateTime d, double base) {
    final blocked = widget.data.blocksOn(d, packageId: pkg['id']).isNotEmpty;
    final booked = widget.data.isTimeTaken(d, pkg['id']);
    final price = priceForLocal(pkg, d, widget.data.pricingRules);
    final color = blocked
        ? theme.colorScheme.errorContainer
        : booked
            ? const Color(0xFFDDE6FF)
            : price > base
                ? const Color(0xFFFFE7C2)
                : price < base
                    ? const Color(0xFFD7F2E1)
                    : theme.colorScheme.surfaceContainerHighest;

    return Container(
      width: 104,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${tr(_weekdayKeys[d.weekday - 1])} ${monthShort[d.month - 1]} ${d.day}',
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            blocked
                ? tr('avLegendBlocked')
                : booked
                    ? tr('avLegendBooked')
                    : pesoCompact(price),
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _legend(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 14, height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );
}
