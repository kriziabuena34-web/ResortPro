import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/list_controls.dart';

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
                      final picked = await DateRangeFilter.pickCustom(dialogContext, range,
                          firstDate: DateUtils.dateOnly(DateTime.now()));
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
                          final picked = await DateRangeFilter.pickCustom(
                            dialogContext,
                            start == null ? null : DateTimeRange(start: start!, end: end ?? start!),
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

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  static const _caps = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.muted);

  List<Map<String, dynamic>> get _upcomingBlocks {
    final today = DateUtils.dateOnly(DateTime.now());
    return widget.data.blockedDates.where((b) {
      final d = parseDate(b['block_date']);
      return d != null && !DateUtils.dateOnly(d).isBefore(today);
    }).toList()
      ..sort((a, b) => '${a['block_date']}'.compareTo('${b['block_date']}'));
  }

  @override
  Widget build(BuildContext context) {
    final upcoming = _upcomingBlocks;
    final rules = widget.data.pricingRules;
    return LayoutBuilder(
      builder: (context, constraints) {
        final body = switch (_section) {
          _Section.blocked => _blockedSection(),
          _Section.pricing => _pricingSection(constraints.maxWidth),
          _Section.preview => _previewSection(constraints.maxWidth),
        };
        return ListView(
          padding: pageInsets(context),
          children: [
            Text(tr('avSubtitle'), style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 14),
            _overviewCard(upcoming, rules, wide: constraints.maxWidth >= 700),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: CountTabs<_Section>(
                value: _section,
                onChanged: (v) => setState(() => _section = v),
                items: [
                  (value: _Section.blocked, label: tr('avBlockedTab'), count: upcoming.length),
                  (value: _Section.pricing, label: tr('avPricingTab'), count: rules.length),
                  (value: _Section.preview, label: tr('avPreviewTab'), count: 30),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ...body,
          ],
        );
      },
    );
  }

  Widget _overviewCard(List<Map<String, dynamic>> upcoming, List<Map<String, dynamic>> rules, {required bool wide}) {
    final next = upcoming.isEmpty ? null : parseDate(upcoming.first['block_date']);
    final activeRules = rules.where((r) => r['is_active'] != false).length;
    final today = DateUtils.dateOnly(DateTime.now());
    final pkgs = widget.data.packages;
    var changed = 0;
    for (var i = 0; i < 30; i++) {
      final d = DateTime(today.year, today.month, today.day + i);
      if (pkgs.any((p) => priceForLocal(p, d, rules) != asDouble(p['price']))) changed++;
    }

    final tiles = [
      _tile(tr('avKBlocked'), tr('avKBlockedSub'), '${upcoming.length}', const Color(0xFFF87171), Icons.event_busy_outlined,
          () => setState(() => _section = _Section.blocked)),
      _tile(tr('avKNext'), next == null ? tr('avKNextNone') : tr(_weekdayKeys[next.weekday - 1]),
          next == null ? '—' : '${monthShort[next.month - 1]} ${next.day}', Colors.white, Icons.block_outlined,
          () => setState(() => _section = _Section.blocked)),
      _tile(tr('avKRules'), tr('avKRulesSub', {'n': rules.length}), '$activeRules', const Color(0xFF60A5FA),
          Icons.sell_outlined, () => setState(() => _section = _Section.pricing)),
      _tile(tr('avKChanged'), tr('avKChangedSub'), '$changed', const Color(0xFFFACC15), Icons.trending_up_rounded,
          () => setState(() => _section = _Section.preview)),
    ];
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
              const Icon(Icons.event_available_rounded, color: AppColors.inkText, size: 20),
              const SizedBox(width: 8),
              Text(tr('avOverview'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.8, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 14),
          if (wide)
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
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.45,
              children: tiles,
            ),
        ],
      ),
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
                        style: const TextStyle(
                            color: AppColors.inkText, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                  ),
                  Icon(icon, size: 16, color: const Color(0xFF7F93A6)),
                ],
              ),
              const SizedBox(height: 2),
              Text(sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF7F93A6), fontSize: 10.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(value, style: TextStyle(color: valueColor, fontSize: 24, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }

  /// Card sa itaas ng bawat section: paliwanag + mga control + pangunahing button.
  Widget _toolbar({required String hint, List<Widget> controls = const [], Widget? action}) => AppCard(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.info_outline_rounded, size: 18, color: AppColors.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(hint, style: const TextStyle(fontSize: 13, height: 1.4))),
                ],
              ),
              if (controls.isNotEmpty || action != null) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: controls)),
                    if (action != null) ...[const SizedBox(width: 12), action],
                  ],
                ),
              ],
            ],
          ),
        ),
      );

  Widget _emptyCard(IconData icon, String message) => AppCard(
        margin: EdgeInsets.zero,
        child: Padding(padding: const EdgeInsets.all(24), child: EmptyState(icon: icon, message: message)),
      );

  Widget _squareBtn(IconData icon, String tooltip, VoidCallback onTap, {Color color = AppColors.text}) => Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(width: 36, height: 36, child: Icon(icon, size: 18, color: color)),
          ),
        ),
      );

  // -------------------------------------------------------------------------
  // Blocked dates
  // -------------------------------------------------------------------------

  List<Widget> _blockedSection() {
    final today = DateUtils.dateOnly(DateTime.now());
    final blocks = widget.data.blockedDates.where((b) {
      final d = parseDate(b['block_date']);
      return d != null && (_showPast || !DateUtils.dateOnly(d).isBefore(today));
    }).toList()
      ..sort((a, b) => '${a['block_date']}'.compareTo('${b['block_date']}'));

    return [
      _toolbar(
        hint: tr('avBlockedHint'),
        controls: [
          FilterPill(
            icon: Icons.history_rounded,
            label: tr('avShowPast'),
            active: _showPast,
            toggle: true,
            onTap: () => setState(() => _showPast = !_showPast),
          ),
        ],
        action: FilledButton.icon(
          onPressed: _addBlock,
          icon: const Icon(Icons.event_busy_outlined, size: 18),
          label: Text(tr('avBlockBtn')),
        ),
      ),
      const SizedBox(height: 18),
      if (blocks.isEmpty)
        _emptyCard(Icons.event_available, tr('avNoBlocks'))
      else
        AppCard(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < blocks.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _blockRow(blocks[i], today),
              ],
            ],
          ),
        ),
    ];
  }

  Widget _blockRow(Map<String, dynamic> b, DateTime today) {
    final d = parseDate(b['block_date'])!;
    final past = DateUtils.dateOnly(d).isBefore(today);
    final reason = '${b['reason'] ?? ''}'.trim();
    final all = b['package_id'] == null;
    final soon = !past && DateUtils.dateOnly(d).difference(today).inDays <= 7;
    return Opacity(
      opacity: past ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 16, 12),
        child: Row(
          children: [
            Container(
              width: 54,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Column(
                children: [
                  Text(monthShort[d.month - 1].toUpperCase(),
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.danger)),
                  Text('${d.day}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, height: 1.1)),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('${tr(_weekdayKeys[d.weekday - 1])}, ${formatDate(d)}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (soon) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFFFACC15), borderRadius: BorderRadius.circular(6)),
                          child: Text(tr('avSoon'),
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.ink)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _chip(all ? Icons.select_all_rounded : Icons.inventory_2_outlined, _packageName(b['package_id']),
                          all ? AppColors.danger : AppColors.primary),
                      if (reason.isNotEmpty) _chip(Icons.notes_rounded, reason, AppColors.muted),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => _removeBlock(b),
              icon: const Icon(Icons.lock_open_rounded, size: 17),
              label: Text(tr('avUnblock')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      );

  // -------------------------------------------------------------------------
  // Pricing rules
  // -------------------------------------------------------------------------

  List<Widget> _pricingSection(double width) {
    final rules = [...widget.data.pricingRules]
      ..sort((a, b) => asInt(b['priority']).compareTo(asInt(a['priority'])));
    return [
      _toolbar(
        hint: tr('avPricingHint'),
        action: FilledButton.icon(
          onPressed: () => _editRule(),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(tr('avNewRule')),
        ),
      ),
      const SizedBox(height: 18),
      if (rules.isEmpty)
        _emptyCard(Icons.sell_outlined, tr('avNoRules'))
      else
        CardGrid(
          columns: width >= 1000 ? 2 : 1,
          children: [for (final r in rules) _ruleCard(r)],
        ),
    ];
  }

  Widget _ruleCard(Map<String, dynamic> r) {
    final active = r['is_active'] != false;
    final v = asDouble(r['value']);
    final type = '${r['adjust_type']}';
    final adj = switch (type) {
      'percent' => '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(0)}%',
      'fixed_amount' => '${v >= 0 ? '+' : '−'}${peso(v.abs())}',
      _ => peso(v),
    };
    final up = type == 'set_price' ? null : v >= 0;
    final color = up == null ? AppColors.info : (up ? AppColors.danger : AppColors.success);
    final start = parseDate(r['start_date']);
    final end = parseDate(r['end_date']);
    final dates = start == null ? tr('avAnyDate') : '${formatDate(start)} – ${formatDate(end ?? start)}';
    final days = (r['days_of_week'] as List?)?.map(asInt).toList() ?? const <int>[];

    Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 17, color: AppColors.muted),
              const SizedBox(width: 9),
              SizedBox(width: 92, child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
              Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            ],
          ),
        );

    return Opacity(
      opacity: active ? 1 : 0.6,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(adj, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                            Text(
                              '${switch (type) {
                                'percent' => tr('avTypePercent'),
                                'fixed_amount' => tr('avTypeFixed'),
                                _ => tr('avTypeSet'),
                              }} · ${tr('avPriority')} ${r['priority'] ?? 0}',
                              style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      Switch(value: active, onChanged: (x) => _toggleRule(r, x)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        row(Icons.inventory_2_outlined, tr('avAppliesTo'), _packageName(r['package_id'])),
                        const Divider(height: 1),
                        row(Icons.date_range_outlined, tr('avDateRange'), dates),
                        const Divider(height: 1),
                        row(Icons.view_week_outlined, tr('avDays'),
                            days.isEmpty ? tr('avEveryDay') : days.map((d) => tr(_weekdayKeys[d - 1])).join(', ')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
              child: Row(
                children: [
                  Text(active ? tr('avRuleOn') : tr('avRuleOff'),
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700, color: active ? AppColors.success : AppColors.muted)),
                  const Spacer(),
                  _squareBtn(Icons.edit_outlined, tr('avEditRule'), () => _editRule(r)),
                  const SizedBox(width: 6),
                  _squareBtn(Icons.delete_outline_rounded, tr('delete'), () => _deleteRule(r), color: AppColors.danger),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 30-day preview
  // -------------------------------------------------------------------------

  static const _cBase = Color(0xFFF1F5F9);
  static const _cHigher = Color(0xFFFEE2E2);
  static const _cLower = Color(0xFFDCFCE7);
  static const _cBlocked = Color(0xFF334155);
  static const _cBooked = Color(0xFFDBEAFE);

  List<Widget> _previewSection(double width) {
    final packages = widget.data.packages;
    if (packages.isEmpty) return [_emptyCard(Icons.inventory_2_outlined, tr('noPackages'))];

    final pkg = widget.data.packageById(_previewPackageId) ?? packages.first;
    final base = asDouble(pkg['price']);
    final today = DateUtils.dateOnly(DateTime.now());
    final days = [for (var i = 0; i < 30; i++) DateTime(today.year, today.month, today.day + i)];
    // Blangkong cell bago ang unang araw para tumapat sa tamang araw ng linggo.
    final lead = today.weekday - 1;

    return [
      _toolbar(
        hint: tr('avPreviewHint'),
        controls: [
          PopupMenuButton<String>(
            tooltip: tr('navPackages'),
            position: PopupMenuPosition.under,
            onSelected: (v) => setState(() => _previewPackageId = v),
            itemBuilder: (context) => [
              for (final p in packages)
                CheckedPopupMenuItem(
                  value: '${p['id']}',
                  checked: '${p['id']}' == '${pkg['id']}',
                  child: Text('${p['name']} · ${peso(asDouble(p['price']))}'),
                ),
            ],
            child: FilterPill(
              icon: Icons.inventory_2_outlined,
              label: '${pkg['name']} · ${peso(base)}',
              active: true,
              dropdown: true,
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      AppCard(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  for (final k in _weekdayKeys)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(tr(k).toUpperCase(), textAlign: TextAlign.center, style: _caps),
                      ),
                    ),
                ],
              ),
              GridView.count(
                crossAxisCount: 7,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: width >= 900 ? 1.5 : 0.9,
                children: [
                  for (var i = 0; i < lead; i++) const SizedBox.shrink(),
                  for (final d in days) _dayTile(pkg, d, base, today),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _legend(_cBase, tr('avLegendBase')),
                  _legend(_cHigher, tr('avLegendHigher')),
                  _legend(_cLower, tr('avLegendLower')),
                  _legend(_cBooked, tr('avLegendBooked')),
                  _legend(_cBlocked, tr('avLegendBlocked')),
                ],
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _dayTile(Map<String, dynamic> pkg, DateTime d, double base, DateTime today) {
    final blocked = widget.data.blocksOn(d, packageId: pkg['id']).isNotEmpty;
    final booked = widget.data.isTimeTaken(d, pkg['id']);
    final price = priceForLocal(pkg, d, widget.data.pricingRules);
    final isToday = DateUtils.isSameDay(d, today);
    final bg = blocked
        ? _cBlocked
        : booked
            ? _cBooked
            : price > base
                ? _cHigher
                : price < base
                    ? _cLower
                    : _cBase;
    final fg = blocked ? Colors.white : AppColors.text;
    final label = blocked
        ? tr('avLegendBlocked')
        : booked
            ? tr('avLegendBooked')
            : pesoCompact(price);

    return Tooltip(
      message: '${formatDate(d)} · $label',
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isToday ? AppColors.primary : Colors.transparent, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(d.day == 1 || isToday ? '${monthShort[d.month - 1]} ${d.day}' : '${d.day}',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: blocked ? Colors.white70 : AppColors.muted)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: fg)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.border),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
        ],
      );
}
