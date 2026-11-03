import 'package:flutter/material.dart';

/// Mga kulay ng ResortPro Admin. Iisang lugar para pare-pareho ang itsura.
class AppColors {
  AppColors._();

  // Sidebar (madilim na navy)
  static const ink = Color(0xFF0B1B2B);
  static const inkRaised = Color(0xFF142B40);
  static const inkLine = Color(0xFF1F3A52);
  static const inkText = Color(0xFFB7C4D1);

  // Brand
  static const primary = Color(0xFF0F766E); // lagoon teal
  static const primaryDark = Color(0xFF0B5A54);
  static const accent = Color(0xFFD4A24C); // sand gold

  // Surfaces at text
  static const background = Color(0xFFEEF2F6);
  static const neu = Color(0xFFEEF2F6); // kapareho ng background para sa neumorphism
  static const surface = Colors.white;
  static const border = Color(0xFFE3E8EE);
  static const text = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const subtle = Color(0xFFF8FAFB);

  // Semantic
  static const success = Color(0xFF15803D);
  static const warning = Color(0xFFC2410C);
  static const danger = Color(0xFFDC2626);
  static const info = Color(0xFF2563EB);
}

/// Floating na anino (mas mataas ang "lutang").
const List<BoxShadow> floatShadow = [
  BoxShadow(color: Color(0x0A0F172A), blurRadius: 3, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x140F172A), blurRadius: 28, offset: Offset(0, 14)),
];

/// Malambot na anino para sa cards (pang-"pro" na itsura, hindi flat na flat).
const List<BoxShadow> softShadow = [
  BoxShadow(color: Color(0x0A0F172A), blurRadius: 2, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x0D0F172A), blurRadius: 16, offset: Offset(0, 6)),
];

ThemeData buildAdminTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    secondary: AppColors.accent,
    surface: AppColors.surface,
    error: AppColors.danger,
  ).copyWith(
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.muted,
    outlineVariant: AppColors.border,
    surfaceContainerHighest: const Color(0xFFEDF1F4),
    primaryContainer: const Color(0xFFDDF2EF),
    onPrimaryContainer: AppColors.primaryDark,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text);
  final radius = BorderRadius.circular(10);

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    visualDensity: VisualDensity.standard,
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.1),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.45),
      bodySmall: text.bodySmall?.copyWith(color: AppColors.muted, height: 1.4),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.1),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: AppColors.border)),
      titleTextStyle: TextStyle(
        color: AppColors.text,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: const Color(0x140F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
      border: OutlineInputBorder(borderRadius: radius),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(borderRadius: radius),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: radius),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: const Color(0xFFDDF2EF),
      checkmarkColor: AppColors.primaryDark,
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.text),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: const BorderSide(color: AppColors.border),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: const Color(0xFFDDF2EF),
        selectedForegroundColor: AppColors.primaryDark,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: const TextStyle(
        color: AppColors.text,
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: const Color(0xFFDDF2EF),
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? AppColors.primaryDark : AppColors.muted,
        ),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.muted,
      indicatorColor: AppColors.primary,
      dividerColor: AppColors.border,
      labelStyle: TextStyle(fontWeight: FontWeight.w700),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
    badgeTheme: const BadgeThemeData(backgroundColor: AppColors.danger),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentTextStyle: const TextStyle(color: Colors.white),
    ),
    listTileTheme: const ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1, thickness: 1),
  );
}
