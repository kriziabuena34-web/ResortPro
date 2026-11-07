import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

// ===========================================================================
// Grouped bar chart (hal. monthly revenue: booked vs collected)
// I-tap ang isang buwan para makita ang eksaktong halaga.
// ===========================================================================

class ChartSeries {
  const ChartSeries(this.name, this.color, this.values);
  final String name;
  final Color color;
  final List<double> values;
}

class GroupedBarChart extends StatefulWidget {
  const GroupedBarChart({
    super.key,
    required this.labels,
    required this.series,
    this.height = 240,
    this.axisFormat = _plain,
    this.valueFormat = _plain,
  });

  final List<String> labels;
  final List<ChartSeries> series;
  final double height;
  final String Function(double) axisFormat;
  final String Function(double) valueFormat;

  static String _plain(double v) => v.toStringAsFixed(0);

  @override
  State<GroupedBarChart> createState() => _GroupedBarChartState();
}

class _GroupedBarChartState extends State<GroupedBarChart> {
  static const double _left = 52;
  static const double _bottom = 26;
  static const double _top = 8;

  int? _selected;

  int? _hitIndex(double dx, double width) {
    final n = widget.labels.length;
    if (n == 0 || dx < _left) return null;
    final groupW = (width - _left) / n;
    final i = ((dx - _left) / groupW).floor();
    if (i < 0 || i >= n) return null;
    return i;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sel = _selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            for (final s in widget.series) _LegendDot(color: s.color, label: s.name),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  final i = _hitIndex(details.localPosition.dx, width);
                  setState(() => _selected = (i == _selected) ? null : i);
                },
                child: CustomPaint(
                  size: Size(width, widget.height),
                  painter: _GroupedBarPainter(
                    labels: widget.labels,
                    series: widget.series,
                    selected: _selected,
                    axisFormat: widget.axisFormat,
                    gridColor: theme.colorScheme.outlineVariant,
                    textColor: theme.colorScheme.onSurfaceVariant,
                    left: _left,
                    bottom: _bottom,
                    top: _top,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          sel == null
              ? tr('chartTapHint')
              : '${widget.labels[sel]}: ${widget.series.map((s) => '${s.name} ${widget.valueFormat(s.values[sel])}').join('  ·  ')}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: sel == null ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface,
            fontWeight: sel == null ? FontWeight.normal : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _GroupedBarPainter extends CustomPainter {
  _GroupedBarPainter({
    required this.labels,
    required this.series,
    required this.selected,
    required this.axisFormat,
    required this.gridColor,
    required this.textColor,
    required this.left,
    required this.bottom,
    required this.top,
  });

  final List<String> labels;
  final List<ChartSeries> series;
  final int? selected;
  final String Function(double) axisFormat;
  final Color gridColor;
  final Color textColor;
  final double left;
  final double bottom;
  final double top;

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    if (n == 0 || series.isEmpty) return;

    double maxV = 0;
    for (final s in series) {
      for (final v in s.values) {
        if (v > maxV) maxV = v;
      }
    }
    final niceMax = maxV <= 0 ? 4.0 : _niceCeil(maxV);

    final plotW = size.width - left;
    final plotH = size.height - top - bottom;
    final labelStyle = TextStyle(fontSize: 11, color: textColor);

    // Gridlines + y-axis labels
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = top + plotH * (1 - i / 4);
      canvas.drawLine(Offset(left, y), Offset(size.width, y), gridPaint);
      final tp = _text(axisFormat(niceMax * i / 4), labelStyle);
      tp.paint(canvas, Offset(left - tp.width - 8, y - tp.height / 2));
    }

    // Bars
    final groupW = plotW / n;
    final innerW = groupW * 0.72;
    final barW = innerW / series.length;
    for (var g = 0; g < n; g++) {
      final dim = selected != null && selected != g;
      for (var si = 0; si < series.length; si++) {
        final values = series[si].values;
        final v = g < values.length ? values[g] : 0.0;
        if (v <= 0) continue;
        final h = plotH * (v / niceMax);
        final x = left + g * groupW + (groupW - innerW) / 2 + si * barW;
        final rect = Rect.fromLTWH(x + 1, top + plotH - h, math.max(1.0, barW - 2), h);
        final paint = Paint()
          ..color = dim
              ? series[si].color.withValues(alpha: 0.3)
              : series[si].color;
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect,
            topLeft: const Radius.circular(3),
            topRight: const Radius.circular(3),
          ),
          paint,
        );
      }

      // x-axis label
      final tp = _text(
        labels[g],
        labelStyle.copyWith(
          fontWeight: selected == g ? FontWeight.bold : FontWeight.normal,
        ),
      );
      tp.paint(
        canvas,
        Offset(left + g * groupW + groupW / 2 - tp.width / 2, top + plotH + 6),
      );
    }
  }

  TextPainter _text(String s, TextStyle style) {
    return TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  double _niceCeil(double v) {
    final exponent = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    final f = v / exponent;
    final double nice;
    if (f <= 1) {
      nice = 1;
    } else if (f <= 2) {
      nice = 2;
    } else if (f <= 5) {
      nice = 5;
    } else {
      nice = 10;
    }
    return nice * exponent;
  }

  @override
  bool shouldRepaint(covariant _GroupedBarPainter oldDelegate) => true;
}

// ===========================================================================
// Donut chart (hal. bookings by status)
// ===========================================================================

class DonutSlice {
  const DonutSlice(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;
}

class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    required this.centerLabel,
    this.size = 160,
    this.valueFormat,
  });

  final List<DonutSlice> slices;
  final String centerLabel;
  final double size;
  final String Function(double)? valueFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = slices.fold<double>(0, (s, e) => s + e.value);
    String fmt(double v) => valueFormat?.call(v) ?? v.toStringAsFixed(0);

    return Wrap(
      spacing: 28,
      runSpacing: 16,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _DonutPainter(
              slices: slices,
              trackColor: theme.colorScheme.surfaceContainerHighest,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fmt(total),
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(centerLabel, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in slices)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LegendDot(color: s.color, label: s.label),
                    const SizedBox(width: 8),
                    Text(
                      '${fmt(s.value)}'
                      '${total > 0 ? '  (${(s.value / total * 100).toStringAsFixed(0)}%)' : ''}',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.slices, required this.trackColor});

  final List<DonutSlice> slices;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.16;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - stroke / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = trackColor;
    canvas.drawCircle(center, radius, track);

    final total = slices.fold<double>(0, (s, e) => s + e.value);
    if (total <= 0) return;

    final visible = slices.where((s) => s.value > 0).length;
    final gap = visible > 1 ? 0.03 : 0.0;
    var start = -math.pi / 2;
    for (final s in slices) {
      if (s.value <= 0) continue;
      final sweep = 2 * math.pi * (s.value / total);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = s.color;
      canvas.drawArc(rect, start + gap / 2, math.max(0.001, sweep - gap), false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}

// ===========================================================================
// Horizontal bars (hal. top packages, payment methods, guest mix)
// ===========================================================================

class BarItem {
  const BarItem(this.label, this.value, {this.trailing, this.color});
  final String label;
  final double value;
  final String? trailing;
  final Color? color;
}

class HorizontalBarList extends StatelessWidget {
  const HorizontalBarList({
    super.key,
    required this.items,
    this.color,
    this.valueFormat,
    this.emptyText,
  });

  final List<BarItem> items;
  final Color? color;
  final String Function(double)? valueFormat;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text(emptyText ?? tr('noData'), style: theme.textTheme.bodyMedium)),
      );
    }

    final maxV = items.fold<double>(0, (m, e) => math.max(m, e.value));

    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(item.label, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.trailing ??
                          (valueFormat?.call(item.value) ?? item.value.toStringAsFixed(0)),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: maxV <= 0 ? 0 : item.value / maxV,
                    minHeight: 8,
                    color: item.color ?? color ?? theme.colorScheme.primary,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

// ===========================================================================
// Line chart (hal. aktwal vs forecast). Ang null na value ay hindi iginuguhit.
// ===========================================================================

class LineSeries {
  const LineSeries(this.name, this.color, this.values, {this.dashed = false});
  final String name;
  final Color color;
  final List<double?> values;
  final bool dashed;
}

class LineChart extends StatelessWidget {
  const LineChart({
    super.key,
    required this.labels,
    required this.series,
    this.height = 260,
    this.axisFormat,
    this.highlightFrom,
  });

  final List<String> labels;
  final List<LineSeries> series;
  final double height;
  final String Function(double)? axisFormat;

  /// Index kung saan nagsisimula ang forecast (may shaded na background).
  final int? highlightFrom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            for (final s in series)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 18, height: 3, color: s.color),
                  const SizedBox(width: 6),
                  Text(s.name + (s.dashed ? ' (- - -)' : ''), style: theme.textTheme.bodySmall),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _LinePainter(
              labels: labels,
              series: series,
              axisFormat: axisFormat ?? (v) => v.toStringAsFixed(0),
              gridColor: theme.colorScheme.outlineVariant,
              textColor: theme.colorScheme.onSurfaceVariant,
              shadeColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
              highlightFrom: highlightFrom,
            ),
          ),
        ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.labels,
    required this.series,
    required this.axisFormat,
    required this.gridColor,
    required this.textColor,
    required this.shadeColor,
    required this.highlightFrom,
  });

  final List<String> labels;
  final List<LineSeries> series;
  final String Function(double) axisFormat;
  final Color gridColor;
  final Color textColor;
  final Color shadeColor;
  final int? highlightFrom;

  static const double left = 56, bottom = 26, top = 8, right = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    if (n == 0) return;
    double maxV = 0;
    for (final s in series) {
      for (final v in s.values) {
        if (v != null && v > maxV) maxV = v;
      }
    }
    // Walang data: 0–4 para buo ang mga numero sa axis (hindi ₱1, ₱1, ₱0…).
    final empty = maxV <= 0;
    if (empty) maxV = 4;
    final exponent = math.pow(10, (math.log(maxV) / math.ln10).floor()).toDouble();
    final f = maxV / exponent;
    final niceMax = empty ? 4.0 : (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * exponent;

    final plotW = size.width - left - right;
    final plotH = size.height - top - bottom;
    final step = n > 1 ? plotW / (n - 1) : 0.0;
    double xOf(int i) => left + (n > 1 ? i * step : plotW / 2);
    double yOf(double v) => top + plotH * (1 - v / niceMax);
    final style = TextStyle(fontSize: 11, color: textColor);

    // Forecast area
    final hf = highlightFrom;
    if (hf != null && hf < n) {
      final x0 = hf > 0 ? (xOf(hf - 1) + xOf(hf)) / 2 : left;
      canvas.drawRect(Rect.fromLTRB(x0, top, size.width - right, top + plotH), Paint()..color = shadeColor);
    }

    // Grid
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = top + plotH * (1 - i / 4);
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), gridPaint);
      final tp = TextPainter(text: TextSpan(text: axisFormat(niceMax * i / 4), style: style), textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(left - tp.width - 8, y - tp.height / 2));
    }

    // X labels (laktawan kapag masikip)
    final every = (n / 12).ceil().clamp(1, n);
    for (var i = 0; i < n; i += every) {
      final tp = TextPainter(text: TextSpan(text: labels[i], style: style), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(xOf(i) - tp.width / 2, top + plotH + 6));
    }

    // Lines
    for (final s in series) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;
      final dot = Paint()..color = s.color;
      Offset? prev;
      for (var i = 0; i < n && i < s.values.length; i++) {
        final v = s.values[i];
        if (v == null) {
          prev = null;
          continue;
        }
        final p = Offset(xOf(i), yOf(v));
        if (prev != null) {
          if (s.dashed) {
            _dashed(canvas, prev, p, paint);
          } else {
            canvas.drawLine(prev, p, paint);
          }
        }
        canvas.drawCircle(p, 3, dot);
        prev = p;
      }
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 6.0, gap = 4.0;
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final end = math.min(d + dash, total);
      canvas.drawLine(a + dir * d, a + dir * end, paint);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) => true;
}
