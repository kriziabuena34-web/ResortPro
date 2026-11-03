import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
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
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: tr('price'),
                    prefixText: '₱ ',
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final packages = widget.data.packages;
    final active = widget.data.activeBookings;

    if (packages.isEmpty) {
      return EmptyState(icon: Icons.inventory_2_outlined, message: tr('noPackages'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 3
            : constraints.maxWidth >= 700
                ? 2
                : 1;

        List<Map<String, dynamic>> bookingsOf(Map<String, dynamic> pkg) =>
            active.where((b) => '${b['package_id']}' == '${pkg['id']}').toList();

        final q = _query.trim().toLowerCase();
        final shown = packages
            .where((p) => q.isEmpty || '${p['name']}'.toLowerCase().contains(q))
            .toList();
        switch (_sort) {
          case _PkgSort.defaultOrder:
            break;
          case _PkgSort.mostBooked:
            shown.sort((a, b) => bookingsOf(b).length.compareTo(bookingsOf(a).length));
          case _PkgSort.priceHigh:
            shown.sort((a, b) => asDouble(b['price']).compareTo(asDouble(a['price'])));
          case _PkgSort.priceLow:
            shown.sort((a, b) => asDouble(a['price']).compareTo(asDouble(b['price'])));
          case _PkgSort.name:
            shown.sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
        }

        return ListView(
          padding: pageInsets(context),
          children: [
            GlassPanel(
              child: Row(
                children: [
                  Expanded(
                    child: SearchBox(
                      controller: _searchController,
                      hint: tr('searchPackagesHint'),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SortMenu<_PkgSort>(
                    value: _sort,
                    options: {
                      _PkgSort.defaultOrder: tr('sortDefault'),
                      _PkgSort.mostBooked: tr('sortMostBookings'),
                      _PkgSort.priceHigh: tr('sortPriceHigh'),
                      _PkgSort.priceLow: tr('sortPriceLow'),
                      _PkgSort.name: tr('sortName'),
                    },
                    onChanged: (v) => setState(() => _sort = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (shown.isEmpty)
              EmptyState(icon: Icons.search_off, message: tr('noPackagesMatch'))
            else
              CardGrid(
                columns: columns,
                children: [
                  for (final pkg in shown) _buildPackageCard(theme, pkg, bookingsOf(pkg)),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _buildPackageCard(
    ThemeData theme,
    Map<String, dynamic> pkg,
    List<Map<String, dynamic>> bookings,
  ) {
    final revenue = bookings.fold<double>(0, (s, b) => s + totalOf(b));
    final today = DateUtils.dateOnly(DateTime.now());
    final upcoming = bookings.where((b) {
      final d = bookingDateOf(b);
      return d != null && !d.isBefore(today);
    }).length;

    final start = formatTime(pkg['start_time']);
    final end = formatTime(pkg['end_time']);
    final minPax = pkg['min_pax'];
    final maxPax = pkg['max_pax'];
    final capacity = minPax != null && maxPax != null
        ? '$minPax–$maxPax pax'
        : maxPax != null
            ? tr('capUpTo', {'max': maxPax})
            : tr('capNoLimit');

    return AppCard(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${pkg['name']}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                IconButton(
                  tooltip: tr('editPackageTooltip'),
                  onPressed: () => _editPackage(pkg),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            Text(
              peso(asDouble(pkg['price'])),
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (start.isNotEmpty) InfoRow(tr('fieldTime'), end.isEmpty ? start : '$start – $end'),
            InfoRow(tr('fieldCapacity'), capacity),
            const Divider(height: 24),
            Row(
              children: [
                _miniStat(theme, '${bookings.length}', tr('bookingsWord')),
                _miniStat(theme, '$upcoming', tr('statUpcoming')),
                _miniStat(theme, pesoCompact(revenue), tr('statBookedValue')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(ThemeData theme, String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
