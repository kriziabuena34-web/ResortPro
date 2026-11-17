import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/list_controls.dart';

/// Packages module: makikita ang performance ng bawat package at
/// ma-eedit ang presyo at capacity.
class PackagesPage extends StatefulWidget {
  const PackagesPage({super.key, required this.data, required this.onChanged});

  final AdminData data;
  final Future<void> Function() onChanged;

  @override
  State<PackagesPage> createState() => _PackagesPageState();
}

enum _PkgSort { defaultOrder, mostBooked, priceHigh, priceLow, name }

class _PackagesPageState extends State<PackagesPage> {
  final supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  String _query = '';
  _PkgSort _sort = _PkgSort.defaultOrder;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _editPackage(Map<String, dynamic> pkg) async {
    final priceController =
        TextEditingController(text: asDouble(pkg['price']).toStringAsFixed(0));
    final minController =
        TextEditingController(text: pkg['min_pax'] == null ? '' : '${pkg['min_pax']}');
    final maxController =
        TextEditingController(text: pkg['max_pax'] == null ? '' : '${pkg['max_pax']}');

    final saved = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        String? error;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text(tr('editPackage', {'name': pkg['name']})),
            content: SizedBox(
              width: 420,
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('pkEditHint'), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 16),
                TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: tr('price'),
                    prefixText: '₱ ',
                    prefixIcon: const Icon(Icons.sell_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: minController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: tr('minPax'),
                          prefixIcon: const Icon(Icons.group_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: maxController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: tr('maxPax'),
                          prefixIcon: const Icon(Icons.groups_outlined),
                        ),
                      ),
                    ),
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
                ],
              ],
            ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr('cancel')),
              ),
              FilledButton(
                onPressed: () {
                  final price = double.tryParse(priceController.text.replaceAll(',', ''));
                  final minPax = minController.text.trim().isEmpty
                      ? null
                      : int.tryParse(minController.text.trim());
                  final maxPax = maxController.text.trim().isEmpty
                      ? null
                      : int.tryParse(maxController.text.trim());

                  if (price == null || price <= 0) {
                    setDialogState(() => error = tr('invalidPrice'));
                    return;
                  }
                  if ((minController.text.trim().isNotEmpty && minPax == null) ||
                      (maxController.text.trim().isNotEmpty && maxPax == null)) {
                    setDialogState(() => error = tr('paxNumbersOnly'));
                    return;
                  }
                  if (minPax != null && maxPax != null && minPax > maxPax) {
                    setDialogState(() => error = tr('minOverMax'));
                    return;
                  }
                  Navigator.pop(dialogContext, {
                    'price': price,
                    'min_pax': minPax,
                    'max_pax': maxPax,
                  });
                },
                child: Text(tr('save')),
              ),
            ],
          ),
        );
      },
    );

    if (saved == null) return;

    try {
      await supabase.from('packages').update(saved).eq('id', pkg['id']);
      if (!mounted) return;
      showToast(context, tr('packageUpdated'));
      await widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      showToast(
        context,
        tr('packageUpdateFailed', {'e': e}),
      );
    }
  }

  static const _caps = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.muted);

  /// Kulay at icon ayon sa oras ng package (pareho sa Calendar).
  static ({Color color, IconData icon, String key}) _slotOf(Map<String, dynamic> pkg) {
    final n = '${pkg['name']}'.toLowerCase();
    if (n.contains('overnight') || n.contains('22')) {
      return (color: const Color(0xFF0F766E), icon: Icons.bedtime_rounded, key: 'pkSlotOvernight');
    }
    if (n.contains('night')) return (color: const Color(0xFF6366F1), icon: Icons.nights_stay_rounded, key: 'pkSlotNight');
    return (color: const Color(0xFFF59E0B), icon: Icons.wb_sunny_rounded, key: 'pkSlotDay');
  }

  @override
  Widget build(BuildContext context) {
    final packages = widget.data.packages;
    final active = widget.data.activeBookings;

    if (packages.isEmpty) {
      return EmptyState(icon: Icons.inventory_2_outlined, message: tr('noPackages'));
    }

    List<Map<String, dynamic>> bookingsOf(Map<String, dynamic> pkg) =>
        active.where((b) => '${b['package_id']}' == '${pkg['id']}').toList();
    final today = DateUtils.dateOnly(DateTime.now());
    int upcomingOf(List<Map<String, dynamic>> list) => list.where((b) {
          final d = bookingDateOf(b);
          return d != null && !d.isBefore(today);
        }).length;

    final counts = {for (final p in packages) '${p['id']}': bookingsOf(p).length};
    final maxCount = counts.values.fold<int>(0, (m, v) => v > m ? v : m);

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 3
            : constraints.maxWidth >= 700
                ? 2
                : 1;

        final q = _query.trim().toLowerCase();
        final shown = packages
            .where((p) => q.isEmpty || '${p['name']}'.toLowerCase().contains(q))
            .toList();
        switch (_sort) {
          case _PkgSort.defaultOrder:
            break;
          case _PkgSort.mostBooked:
            shown.sort((a, b) => counts['${b['id']}']!.compareTo(counts['${a['id']}']!));
          case _PkgSort.priceHigh:
            shown.sort((a, b) => asDouble(b['price']).compareTo(asDouble(a['price'])));
          case _PkgSort.priceLow:
            shown.sort((a, b) => asDouble(a['price']).compareTo(asDouble(b['price'])));
          case _PkgSort.name:
            shown.sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
        }
        final sortOptions = {
          _PkgSort.defaultOrder: tr('sortDefault'),
          _PkgSort.mostBooked: tr('sortMostBookings'),
          _PkgSort.priceHigh: tr('sortPriceHigh'),
          _PkgSort.priceLow: tr('sortPriceLow'),
          _PkgSort.name: tr('sortName'),
        };

        return ListView(
          padding: pageInsets(context),
          children: [
            Text(tr('pkSubtitle'), style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 14),
            _overviewCard(packages, counts, active.fold<double>(0, (s, b) => s + totalOf(b)), wide: constraints.maxWidth >= 700),
            const SizedBox(height: 18),
            AppCard(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: constraints.maxWidth >= 900 ? 380 : double.infinity,
                      child: SearchBox(
                        controller: _searchController,
                        hint: tr('searchPackagesHint'),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                    PopupMenuButton<_PkgSort>(
                      tooltip: tr('sortBy'),
                      position: PopupMenuPosition.under,
                      onSelected: (v) => setState(() => _sort = v),
                      itemBuilder: (context) => [
                        for (final e in sortOptions.entries)
                          CheckedPopupMenuItem(value: e.key, checked: e.key == _sort, child: Text(e.value)),
                      ],
                      child: FilterPill(
                        icon: Icons.swap_vert_rounded,
                        label: sortOptions[_sort] ?? '',
                        active: _sort != _PkgSort.defaultOrder,
                        dropdown: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (shown.isEmpty)
              AppCard(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: EmptyState(icon: Icons.search_off, message: tr('noPackagesMatch')),
                ),
              )
            else
              CardGrid(
                columns: columns,
                children: [
                  for (final pkg in shown)
                    _buildPackageCard(pkg, bookingsOf(pkg), upcomingOf(bookingsOf(pkg)), maxCount),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _overviewCard(
    List<Map<String, dynamic>> packages,
    Map<String, int> counts,
    double bookedValue, {
    required bool wide,
  }) {
    final prices = packages.map((p) => asDouble(p['price'])).toList()..sort();
    Map<String, dynamic>? top;
    for (final p in packages) {
      if (top == null || counts['${p['id']}']! > counts['${top['id']}']!) top = p;
    }
    final topCount = top == null ? 0 : counts['${top['id']}']!;

    final tiles = [
      _tile(tr('pkKPackages'), tr('pkKPackagesSub'), '${packages.length}', Colors.white, Icons.inventory_2_outlined),
      _tile(tr('pkKTop'), topCount == 0 ? tr('pkKTopNone') : tr('pkKTopSub', {'n': topCount}),
          topCount == 0 ? '—' : '${top!['name']}', const Color(0xFFFACC15), Icons.local_fire_department_outlined),
      _tile(tr('pkKValue'), tr('pkKValueSub'), pesoCompact(bookedValue), const Color(0xFF4ADE80), Icons.payments_outlined),
      _tile(tr('pkKRange'), tr('pkKRangeSub'),
          prices.isEmpty ? '—' : '${pesoCompact(prices.first)} – ${pesoCompact(prices.last)}', const Color(0xFF60A5FA),
          Icons.sell_outlined),
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
              const Icon(Icons.inventory_2_rounded, color: AppColors.inkText, size: 20),
              const SizedBox(width: 8),
              Text(tr('pkOverview'),
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

  Widget _tile(String label, String sub, String value, Color valueColor, IconData icon) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
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
                    style: const TextStyle(color: AppColors.inkText, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
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
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(color: valueColor, fontSize: 22, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Icon(icon, size: 17, color: AppColors.muted),
            const SizedBox(width: 9),
            SizedBox(width: 80, child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
            Expanded(
              child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ],
        ),
      );

  Widget _buildPackageCard(
    Map<String, dynamic> pkg,
    List<Map<String, dynamic>> bookings,
    int upcoming,
    int maxCount,
  ) {
    final revenue = bookings.fold<double>(0, (s, b) => s + totalOf(b));
    final slot = _slotOf(pkg);
    final start = formatTime(pkg['start_time']);
    final end = formatTime(pkg['end_time']);
    final minPax = pkg['min_pax'];
    final maxPax = pkg['max_pax'];
    final capacity = minPax != null && maxPax != null
        ? '$minPax–$maxPax pax'
        : maxPax != null
            ? tr('capUpTo', {'max': maxPax})
            : tr('capNoLimit');
    final share = maxCount == 0 ? 0.0 : bookings.length / maxCount;

    Widget stat(String value, String label) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: AppColors.subtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.muted, letterSpacing: 0.5)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ],
            ),
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(height: 5, color: slot.color),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: slot.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(slot.icon, color: slot.color, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${pkg['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                          const SizedBox(height: 2),
                          Text(tr(slot.key),
                              style: TextStyle(color: slot.color, fontWeight: FontWeight.w700, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(peso(asDouble(pkg['price'])),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: AppColors.primary)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      _infoRow(Icons.schedule_rounded, tr('fieldTime'),
                          start.isEmpty ? '—' : (end.isEmpty ? start : '$start – $end')),
                      const Divider(height: 1),
                      _infoRow(Icons.groups_outlined, tr('fieldCapacity'), capacity),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: Row(
                  children: [
                    stat('${bookings.length}', tr('bookingsWord')),
                    const SizedBox(width: 8),
                    stat('$upcoming', tr('statUpcoming')),
                    const SizedBox(width: 8),
                    stat(pesoCompact(revenue), tr('statBookedValue')),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(tr('pkPopularity').toUpperCase(), style: _caps),
                        const Spacer(),
                        Text('${(share * 100).round()}%',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.muted)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: share,
                        minHeight: 7,
                        backgroundColor: const Color(0xFFE6EBF0),
                        valueColor: AlwaysStoppedAnimation(slot.color),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 14, 12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            child: Row(
              children: [
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => _editPackage(pkg),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(tr('pkEditBtn')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
