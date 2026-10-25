import 'package:flutter/material.dart';

/// Цвета матового стекла для светлой и тёмной темы.
class GlassColors {
  /// Синий цвет активного / выбранного пункта.
  static const Color active = Color(0xFF0A6CFF);

  final Color tint; // слой 2: заливка поверх размытия
  final Color text;
  final Color muted;
  final Color stroke; // тонкая рамка по краю стекла
  final Color hover; // лёгкая подложка разделителей и полей
  final Color page; // фон экранов приложения
  final Color card;
  final Color shadow;

  const GlassColors({
    required this.tint,
    required this.text,
    required this.muted,
    required this.stroke,
    required this.hover,
    required this.page,
    required this.card,
    required this.shadow,
  });

  static const GlassColors light = GlassColors(
    tint: Color(0xCCFFFFFF), // белое стекло, 80%
    text: Color(0xFF000000),
    muted: Color(0x8C000000),
    stroke: Color(0x0F000000),
    hover: Color(0x0F000000),
    page: Color(0xFFEEF0F3),
    card: Color(0xFFFFFFFF),
    shadow: Color(0x2E000000),
  );

  static const GlassColors dark = GlassColors(
    tint: Color(0xB8000000), // тёмное стекло, 72%
    text: Color(0xFFFFFFFF),
    muted: Color(0x8CFFFFFF),
    stroke: Color(0x14FFFFFF),
    hover: Color(0x14FFFFFF),
    page: Color(0xFF1C1C1F), // тёмный графит, а не чёрный
    card: Color(0xFF2A2A2E),
    shadow: Color(0x66000000),
  );

  static GlassColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Тема всего приложения в матовом стиле.
class GlassTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final c =
        brightness == Brightness.dark ? GlassColors.dark : GlassColors.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: GlassColors.active,
      brightness: brightness,
    ).copyWith(
      primary: GlassColors.active,
      onPrimary: Colors.white,
      surface: c.card,
      onSurface: c.text,
    );

    final radius20 = BorderRadius.circular(20);

    // cardTheme / dialogTheme / tabBarTheme не задаём: их типы отличаются
    // между Flutter 3.24 и новыми версиями — так проект собирается на обеих.

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      scaffoldBackgroundColor: c.page,
      canvasColor: c.page,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      dividerColor: c.hover,
      iconTheme: IconThemeData(color: c.text),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle:
            TextStyle(color: c.text, fontSize: 20, fontWeight: FontWeight.w600),
        iconTheme: IconThemeData(color: c.text),
        actionsIconTheme: IconThemeData(color: c.text),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.card,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: radius20),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalBackgroundColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: brightness == Brightness.dark
            ? const Color(0xFF2C2C2E)
            : const Color(0xFF1C1C1E),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: radius20),
        elevation: 0,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.text,
        textColor: c.text,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? GlassColors.active : null),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? GlassColors.active : null),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: GlassColors.active),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: GlassColors.active,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: GlassColors.active,
          shape: const StadiumBorder(),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.hover,
        hintStyle: TextStyle(color: c.muted),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: GlassColors.active, width: 1.2)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: GlassColors.active,
        selectionColor: GlassColors.active.withOpacity(0.3),
        selectionHandleColor: GlassColors.active,
      ),
    );
  }
}
