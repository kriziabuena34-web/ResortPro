import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/admin_data.dart';
import 'ui_kit.dart';

/// Search box na ginagamit sa lahat ng listahan.
class SearchBox extends StatelessWidget {
  const SearchBox({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: tr('clear'),
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          isDense: true,
        ),
      ),
    );
  }
}

/// Pahalang na hanay ng filter chips na pwedeng i-scroll.
class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Center(child: children[i]),
      ),
    );
  }
}

/// Chip para pumili ng date range. Walang laman = kahit anong petsa.
class DateRangeChip extends StatelessWidget {
  const DateRangeChip({super.key, required this.range, required this.onChanged});

  final DateTimeRange? range;
  final ValueChanged<DateTimeRange?> onChanged;

  @override
  Widget build(BuildContext context) {
    final r = range;
    final label = r == null
        ? tr('anyDate')
        : DateUtils.isSameDay(r.start, r.end)
            ? formatDate(r.start)
            : '${formatDate(r.start)} – ${formatDate(r.end)}';

    return InputChip(
      avatar: const Icon(Icons.date_range, size: 18),
      label: Text(label),
      selected: r != null,
      showCheckmark: false,
      onPressed: () async {
        final now = DateTime.now();
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(now.year - 3),
          lastDate: DateTime(now.year + 3, 12, 31),
          initialDateRange: r,
        );
        if (picked != null) onChanged(picked);
      },
      onDeleted: r == null ? null : () => onChanged(null),
    );
  }
}

/// Dropdown para sa sort order.
class SortMenu<T> extends StatelessWidget {
  const SortMenu({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: tr('sortBy'),
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final e in options.entries)
          CheckedPopupMenuItem<T>(value: e.key, checked: e.key == value, child: Text(e.value)),
      ],
      child: Chip(
        avatar: const Icon(Icons.sort, size: 18),
        label: Text(options[value] ?? ''),
      ),
    );
  }
}

/// Maliit na text na nagsasabi kung ilan ang resulta.
class ResultCount extends StatelessWidget {
  const ResultCount({super.key, required this.shown, required this.total, this.onClear});

  final int shown;
  final int total;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(pageGutter(context) + 6, 2, pageGutter(context) - 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              tr('showingOf', {'shown': shown, 'total': total}),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if (onClear != null && shown != total)
            TextButton(onPressed: onClear, child: Text(tr('clearFilters'))),
        ],
      ),
    );
  }
}

/// True kung pasok ang [date] sa [range] (kasama ang dulo).
bool inRange(DateTime? date, DateTimeRange? range) {
  if (range == null) return true;
  if (date == null) return false;
  final d = DateUtils.dateOnly(date);
  return !d.isBefore(DateUtils.dateOnly(range.start)) && !d.isAfter(DateUtils.dateOnly(range.end));
}
