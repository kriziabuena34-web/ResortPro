import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/admin_data.dart';
import '../theme/app_theme.dart';
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
        maxLength: 60,
        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
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

/// Filter ng petsa: mabilisang pagpili (Today, This month…) o sariling range
/// sa isang maayos na calendar dialog.
class DateRangeFilter extends StatelessWidget {
  const DateRangeFilter({super.key, required this.range, required this.onChanged});

  final DateTimeRange? range;
  final ValueChanged<DateTimeRange?> onChanged;

  static DateTimeRange _day(DateTime d) => DateTimeRange(start: DateUtils.dateOnly(d), end: DateUtils.dateOnly(d));

  static Map<String, DateTimeRange> presets() {
    final now = DateUtils.dateOnly(DateTime.now());
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    return {
      'drToday': _day(now),
      'drYesterday': _day(now.subtract(const Duration(days: 1))),
      'drThisWeek': DateTimeRange(start: weekStart, end: weekStart.add(const Duration(days: 6))),
      'drLast7': DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
      'drThisMonth': DateTimeRange(start: DateTime(now.year, now.month), end: DateTime(now.year, now.month + 1, 0)),
      'drLastMonth': DateTimeRange(start: DateTime(now.year, now.month - 1), end: DateTime(now.year, now.month, 0)),
    };
  }

  static bool _same(DateTimeRange a, DateTimeRange b) =>
      DateUtils.isSameDay(a.start, b.start) && DateUtils.isSameDay(a.end, b.end);

  /// Calendar na nasa gitna at hindi full screen.
  static Future<DateTimeRange?> pickCustom(BuildContext context, DateTimeRange? initial, {DateTime? firstDate}) {
    final now = DateTime.now();
    return showDateRangePicker(
      context: context,
      firstDate: firstDate ?? DateTime(now.year - 3),
      lastDate: DateTime(now.year + 3, 12, 31),
      initialDateRange: initial,
      currentDate: now,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: tr('drPickTitle'),
      saveText: tr('drApply'),
      builder: (context, child) {
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            datePickerTheme: theme.datePickerTheme.copyWith(
              backgroundColor: Colors.white,
              headerBackgroundColor: AppColors.ink,
              headerForegroundColor: Colors.white,
              rangeSelectionBackgroundColor: AppColors.primary.withValues(alpha: 0.12),
              rangePickerHeaderBackgroundColor: AppColors.ink,
              rangePickerHeaderForegroundColor: Colors.white,
              rangePickerBackgroundColor: Colors.white,
              todayBorder: const BorderSide(color: AppColors.primary),
              dayShape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420, maxHeight: 640),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Material(
                    elevation: 12,
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = range;
    final p = presets();
    String? presetKey;
    if (r != null) {
      for (final e in p.entries) {
        if (_same(e.value, r)) presetKey = e.key;
      }
    }
    final label = r == null
        ? tr('anyDate')
        : presetKey != null
            ? tr(presetKey)
            : DateUtils.isSameDay(r.start, r.end)
                ? formatDate(r.start)
                : '${formatDate(r.start)} – ${formatDate(r.end)}';

    return PopupMenuButton<String>(
      tooltip: tr('fieldDate'),
      position: PopupMenuPosition.under,
      onSelected: (v) async {
        if (v == '__any') return onChanged(null);
        if (v == '__custom') {
          final picked = await pickCustom(context, r);
          if (picked != null) onChanged(picked);
          return;
        }
        onChanged(p[v]);
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(value: '__any', checked: r == null, child: Text(tr('anyDate'))),
        const PopupMenuDivider(),
        for (final e in p.entries)
          CheckedPopupMenuItem(value: e.key, checked: presetKey == e.key, child: Text(tr(e.key))),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: '__custom',
          child: Row(
            children: [
              const Icon(Icons.edit_calendar_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 10),
              Text(r != null && presetKey == null ? '${tr('drCustom')} ✓' : tr('drCustom')),
            ],
          ),
        ),
      ],
      child: FilterPill(
        icon: Icons.calendar_month_outlined,
        label: label,
        active: r != null,
        dropdown: r == null,
        onClear: () => onChanged(null),
      ),
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

/// Iisang itsura ng filter button: pill na may icon at label.
/// Teal ang kulay kapag naka-on; may ⌄ kapag dropdown, may ✓ kapag toggle, may ✕ para alisin.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.icon,
    required this.label,
    this.active = false,
    this.dropdown = false,
    this.toggle = false,
    this.onTap,
    this.onClear,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool dropdown;
  final bool toggle;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppColors.primaryDark : AppColors.text;
    final pill = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 38,
      padding: EdgeInsets.only(left: 12, right: active && onClear != null ? 4 : 12),
      decoration: BoxDecoration(
        color: active ? AppColors.primary.withValues(alpha: 0.10) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? AppColors.primary.withValues(alpha: 0.55) : AppColors.border),
        boxShadow: active ? null : const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(toggle && active ? Icons.check_circle_rounded : icon, size: 17, color: active ? AppColors.primary : AppColors.muted),
          const SizedBox(width: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontWeight: active ? FontWeight.w700 : FontWeight.w600, fontSize: 13.5),
            ),
          ),
          if (dropdown) ...[
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 18, color: active ? AppColors.primary : AppColors.muted),
          ],
          if (active && onClear != null)
            InkWell(
              onTap: onClear,
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(5),
                child: Icon(Icons.close_rounded, size: 16, color: AppColors.primaryDark),
              ),
            ),
        ],
      ),
    );
    if (onTap == null) return pill;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(20), child: pill),
    );
  }
}

/// Mga tab na may bilang (hal. All · Verified · Pending). Madilim ang napili.
class CountTabs<T> extends StatelessWidget {
  const CountTabs({super.key, required this.items, required this.value, required this.onChanged, this.accent});

  final List<({T value, String label, int count})> items;
  final T value;
  final ValueChanged<T> onChanged;

  /// Tab na may dilaw na bilang kapag napili (hal. "Active").
  final T? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.subtle,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final it in items) _tab(it.label, it.count, it.value == value, () => onChanged(it.value), it.value == accent),
          ],
        ),
      ),
    );
  }

  Widget _tab(String label, int n, bool selected, VoidCallback onTap, bool highlight) {
    return Material(
      color: selected ? AppColors.ink : Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.text,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 13,
                  )),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: selected ? Colors.white24 : const Color(0xFFE6EBF0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$n',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : AppColors.muted,
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
