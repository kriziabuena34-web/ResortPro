import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_theme.dart';

// ===========================================================================
// ResortPro UI kit
// Iisang hanay ng building blocks para pare-pareho ang lahat ng module:
//   • GlassPanel   – glassmorphism (blur + translucent), para sa floating toolbars
//   • NeuCard      – neumorphism (malambot na dalawang anino), para sa KPI/stat
//   • AppCard      – floating card, para sa mga item sa listahan
//   • StatGrid     – pantay-pantay na lapad ng stat cards
//   • ModuleBody   – standard padding + FAB sa bawat module
// ===========================================================================

/// Standard na padding ng bawat module (mas maluwag sa malapad na screen).
EdgeInsets pageInsets(BuildContext context, {bool fab = false}) {
  final wide = MediaQuery.sizeOf(context).width >= 800;
  final h = wide ? 24.0 : 16.0;
  return EdgeInsets.fromLTRB(h, wide ? 20 : 16, h, fab ? 104 : 32);
}

/// Pahalang na padding lang (para sa toolbars sa itaas ng listahan).
double pageGutter(BuildContext context) => MediaQuery.sizeOf(context).width >= 800 ? 24 : 16;

/// Glassmorphism panel: malabong likod, translucent na puti, at manipis na liwanag sa gilid.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 18,
    this.opacity = 0.62,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: const [
          BoxShadow(color: Color(0x140F172A), blurRadius: 30, offset: Offset(0, 12)),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: r,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: opacity + 0.12),
                  Colors.white.withValues(alpha: opacity - 0.08),
                ],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.75), width: 1.2),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Neumorphic na card: kapareho ng kulay ng background, may liwanag sa
/// kaliwang-itaas at anino sa kanang-ibaba.
class NeuCard extends StatelessWidget {
  const NeuCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 20,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.neu,
        borderRadius: r,
        boxShadow: const [
          BoxShadow(color: Color(0xFFFFFFFF), blurRadius: 16, offset: Offset(-6, -6)),
          BoxShadow(color: Color(0x2E8A9BB0), blurRadius: 18, offset: Offset(7, 8)),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: r,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Floating card para sa mga item. Drop-in kapalit ng `Card`.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.margin = EdgeInsets.zero,
    this.clipBehavior = Clip.antiAlias,
    this.color,
    this.onTap,
    // Tinatanggap para drop-in sa `Card(...)`; hindi na ginagamit.
    this.shape,
    this.elevation,
  });

  final Widget? child;
  final EdgeInsetsGeometry? margin;
  final Clip clipBehavior;
  final Color? color;
  final VoidCallback? onTap;
  final ShapeBorder? shape;
  final double? elevation;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(18);
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color ?? AppColors.surface,
          borderRadius: r,
          border: Border.all(color: const Color(0xFFE8EDF2)),
          boxShadow: floatShadow,
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: r,
          clipBehavior: clipBehavior,
          child: onTap == null ? child : InkWell(onTap: onTap, child: child),
        ),
      ),
    );
  }
}

/// Pantay-pantay na grid ng stat cards (umaabot sa buong lapad).
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children, this.minWidth = 210, this.spacing = 16});

  final List<Widget> children;
  final double minWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (children.isEmpty) return const SizedBox.shrink();
        final w = constraints.maxWidth;
        var columns = ((w + spacing) / (minWidth + spacing)).floor().clamp(1, children.length);
        // Iwasan ang isang naiwang card sa huling hanay kung kaya.
        if (columns > 2 && children.length % columns == 1 && children.length > columns) columns -= 1;
        final itemWidth = ((w - spacing * (columns - 1)) / columns).floorToDouble();
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final c in children) SizedBox(width: itemWidth, child: c)],
        );
      },
    );
  }
}

/// Floating na toolbar (glass) sa itaas ng listahan: search, tabs at filters.
class FloatingToolbar extends StatelessWidget {
  const FloatingToolbar({super.key, required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final g = pageGutter(context);
    return Padding(
      padding: padding ?? EdgeInsets.fromLTRB(g, g - 4, g, 8),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }
}

/// Module na may floating action button sa kanang-ibaba.
class ModuleBody extends StatelessWidget {
  const ModuleBody({super.key, required this.child, this.fab});

  final Widget child;
  final Widget? fab;

  @override
  Widget build(BuildContext context) {
    if (fab == null) return child;
    final g = pageGutter(context);
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(right: g, bottom: g, child: fab!),
      ],
    );
  }
}

/// Standard na FAB ng ResortPro (extended, may gradient at floating na anino).
class AppFab extends StatelessWidget {
  const AppFab({super.key, required this.icon, required this.label, required this.onPressed, this.showLabel});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// null = itago ang label sa maliit na screen; true/false = laging ipakita/itago.
  final bool? showLabel;

  @override
  Widget build(BuildContext context) {
    final compact = showLabel == null ? MediaQuery.sizeOf(context).width < 600 : !showLabel!;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(colors: [Color(0xFF14B8A6), AppColors.primary]),
        boxShadow: const [
          BoxShadow(color: Color(0x550F766E), blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 22, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white),
                if (!compact) ...[
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pill-style na tabs (kapalit ng SegmentedButton sa mga module).
class PillTabs<T> extends StatelessWidget {
  const PillTabs({super.key, required this.value, required this.items, required this.onChanged});

  final T value;
  final List<({T value, IconData icon, String label})> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.neu,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(color: Color(0x228A9BB0), blurRadius: 6, offset: Offset(2, 2)),
            BoxShadow(color: Color(0xFFFFFFFF), blurRadius: 6, offset: Offset(-2, -2)),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in items)
                _PillTab(
                  selected: item.value == value,
                  icon: item.icon,
                  label: item.label,
                  onTap: () => onChanged(item.value),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillTab extends StatelessWidget {
  const _PillTab({required this.selected, required this.icon, required this.label, required this.onTap});

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.muted;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            gradient: selected
                ? const LinearGradient(colors: [Color(0xFF14B8A6), AppColors.primary])
                : null,
            boxShadow: selected
                ? const [BoxShadow(color: Color(0x400F766E), blurRadius: 12, offset: Offset(0, 4))]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Malambot na background ng content area (para may "lalim" ang glass).
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: AppColors.background)),
        Positioned(top: -140, right: -80, child: _blob(420, const Color(0x3314B8A6))),
        Positioned(bottom: -160, left: -120, child: _blob(460, const Color(0x26D4A24C))),
        Positioned(top: 260, left: 340, child: _blob(300, const Color(0x1A2563EB))),
        Positioned.fill(child: child),
      ],
    );
  }

  static Widget _blob(double size, Color color) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
          ),
        ),
      );
}

/// Hanay ng cards na pare-pareho ang lapad AT taas (sinusunod ang pinakamataas).
/// Ginagamit para pantay ang mga graph/card na magkatabi.
class EqualHeightRow extends MultiChildRenderObjectWidget {
  const EqualHeightRow({super.key, required super.children, this.spacing = 16, this.flex});

  final double spacing;

  /// Optional na hati ng lapad (hal. [3, 2]). Kapag wala, pantay.
  final List<int>? flex;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderEqualHeightRow(spacing, flex);

  @override
  void updateRenderObject(BuildContext context, RenderEqualHeightRow renderObject) {
    renderObject
      ..spacing = spacing
      ..flex = flex;
  }
}

class _EqualHeightParentData extends ContainerBoxParentData<RenderBox> {}

class RenderEqualHeightRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _EqualHeightParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _EqualHeightParentData> {
  RenderEqualHeightRow(this._spacing, this._flex);

  double _spacing;
  List<int>? _flex;
  set flex(List<int>? v) {
    _flex = v;
    markNeedsLayout();
  }

  set spacing(double v) {
    if (v == _spacing) return;
    _spacing = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _EqualHeightParentData) child.parentData = _EqualHeightParentData();
  }

  @override
  void performLayout() {
    final count = childCount;
    if (count == 0) {
      size = constraints.smallest;
      return;
    }
    final width = constraints.maxWidth;
    final usable = width - _spacing * (count - 1);
    final flex = _flex != null && _flex!.length == count ? _flex! : List.filled(count, 1);
    final totalFlex = flex.fold<int>(0, (a, b) => a + b);
    double widthOf(int i) => (usable * flex[i] / totalFlex).floorToDouble();

    // 1) Sukatin ang natural na taas ng bawat isa.
    var maxHeight = 0.0;
    var child = firstChild;
    var i = 0;
    while (child != null) {
      child.layout(BoxConstraints.tightFor(width: widthOf(i)), parentUsesSize: true);
      if (child.size.height > maxHeight) maxHeight = child.size.height;
      child = childAfter(child);
      i++;
    }

    // 2) I-layout ulit lahat sa iisang taas.
    var x = 0.0;
    child = firstChild;
    i = 0;
    while (child != null) {
      final w = widthOf(i);
      child.layout(BoxConstraints.tightFor(width: w, height: maxHeight), parentUsesSize: true);
      (child.parentData! as _EqualHeightParentData).offset = Offset(x, 0);
      x += w + _spacing;
      child = childAfter(child);
      i++;
    }
    size = constraints.constrain(Size(width, maxHeight));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// Grid ng cards: bawat hanay ay pantay ang taas, at pantay ang lapad ng lahat.
class CardGrid extends StatelessWidget {
  const CardGrid({super.key, required this.columns, required this.children, this.spacing = 16});

  final int columns;
  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final cols = columns < 1 ? 1 : columns;
    if (cols == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: spacing),
            children[i],
          ],
        ],
      );
    }
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += cols) {
      final slice = children.sublist(i, (i + cols).clamp(0, children.length));
      while (slice.length < cols) {
        slice.add(const SizedBox.shrink());
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
      rows.add(EqualHeightRow(spacing: spacing, children: slice));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}
