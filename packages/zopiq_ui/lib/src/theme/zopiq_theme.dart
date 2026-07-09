import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:zopiq_ui/src/theme/zopiq_colors.dart';
import 'package:zopiq_ui/src/tokens/zopiq_palette.dart';
import 'package:zopiq_ui/src/tokens/zopiq_radii.dart';
import 'package:zopiq_ui/src/tokens/zopiq_spacing.dart';
import 'package:zopiq_ui/src/tokens/zopiq_typography.dart';

/// The single entry point for app theming (Rule 2). Apps do:
/// `MaterialApp.router(theme: ZopiqTheme.light, darkTheme: ZopiqTheme.dark, ...)`.
///
/// Material 3 base, restyled to the Swiggy-premium look — nothing here is stock.
@immutable
abstract final class ZopiqTheme {
  static final ThemeData light = _build(
    brightness: Brightness.light,
    zc: ZopiqColors.light,
    scaffold: ZopiqPalette.backgroundLight,
    surface: ZopiqPalette.surfaceLight,
  );

  static final ThemeData dark = _build(
    brightness: Brightness.dark,
    zc: ZopiqColors.dark,
    scaffold: ZopiqPalette.backgroundDark,
    surface: ZopiqPalette.surfaceDark,
  );

  static ThemeData _build({
    required Brightness brightness,
    required ZopiqColors zc,
    required Color scaffold,
    required Color surface,
  }) {
    final bool isDark = brightness == Brightness.dark;
    final Color onSurface = zc.textStrong;

    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: zc.primary,
      onPrimary: ZopiqPalette.white,
      primaryContainer: isDark
          ? const Color(0xFF3A2410)
          : const Color(0xFFFFE9D5),
      onPrimaryContainer: isDark
          ? const Color(0xFFFFD8B5)
          : ZopiqPalette.textDark,
      secondary: zc.primaryDeep,
      onSecondary: ZopiqPalette.white,
      secondaryContainer: isDark
          ? const Color(0xFF3A1608)
          : const Color(0xFFFFDCCC),
      onSecondaryContainer: isDark
          ? const Color(0xFFFFC7AE)
          : ZopiqPalette.textDark,
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: zc.textMuted,
      error: zc.nonVeg,
      onError: ZopiqPalette.white,
      outline: zc.divider,
      outlineVariant: zc.divider,
      shadow: ZopiqPalette.black,
      scrim: zc.scrim,
      inverseSurface: isDark
          ? ZopiqPalette.surfaceLight
          : ZopiqPalette.textDark,
      onInverseSurface: isDark ? ZopiqPalette.textDark : ZopiqPalette.white,
      surfaceContainerLowest: isDark
          ? const Color(0xFF141519)
          : ZopiqPalette.white,
      surfaceContainerLow: isDark
          ? ZopiqPalette.surfaceDark
          : const Color(0xFFFAFAFB),
      surfaceContainer: isDark
          ? ZopiqPalette.surfaceDark
          : const Color(0xFFF4F4F5),
      surfaceContainerHigh: isDark
          ? ZopiqPalette.surfaceDarkElevated
          : const Color(0xFFEDEDEF),
      surfaceContainerHighest: isDark
          ? const Color(0xFF2E2F36)
          : const Color(0xFFE6E6E9),
    );

    final TextTheme textTheme = ZopiqTypography.textTheme(onSurface);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      canvasColor: scaffold,
      fontFamily: ZopiqTypography.fontFamily,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      extensions: <ThemeExtension<dynamic>>[zc],
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: ZopiqRadii.rLg),
      ),
      dividerTheme: DividerThemeData(color: zc.divider, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: zc.primaryDeep,
          foregroundColor: ZopiqPalette.white,
          textStyle: textTheme.labelLarge,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.xl),
          shape: const RoundedRectangleBorder(borderRadius: ZopiqRadii.rMd),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: zc.primary,
          foregroundColor: ZopiqPalette.white,
          textStyle: textTheme.labelLarge,
          elevation: 0,
          minimumSize: const Size(0, 52),
          shape: const RoundedRectangleBorder(borderRadius: ZopiqRadii.rMd),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: zc.primary,
          textStyle: textTheme.labelLarge,
          minimumSize: const Size(0, 52),
          side: BorderSide(color: zc.primary, width: 1.5),
          shape: const RoundedRectangleBorder(borderRadius: ZopiqRadii.rMd),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        side: BorderSide(color: zc.divider),
        labelStyle: textTheme.labelMedium,
        shape: const RoundedRectangleBorder(borderRadius: ZopiqRadii.rPill),
        padding: const EdgeInsets.symmetric(
          horizontal: ZopiqSpacing.md,
          vertical: ZopiqSpacing.sm,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(ZopiqRadii.xl),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? ZopiqPalette.surfaceDarkElevated
            : const Color(0xFFF1F1F3),
        hintStyle: textTheme.bodyMedium?.copyWith(color: zc.textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ZopiqSpacing.lg,
          vertical: ZopiqSpacing.md,
        ),
        border: const OutlineInputBorder(
          borderRadius: ZopiqRadii.rMd,
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: ZopiqRadii.rMd,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: ZopiqRadii.rMd,
          borderSide: BorderSide(color: zc.primary, width: 1.5),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: zc.primary,
        unselectedItemColor: zc.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: textTheme.labelSmall,
        unselectedLabelStyle: textTheme.labelSmall,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark
            ? ZopiqPalette.surfaceDarkElevated
            : ZopiqPalette.textDark,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: ZopiqPalette.white,
        ),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: ZopiqRadii.rMd),
      ),
      splashColor: zc.primary.withValues(alpha: 0.08),
      highlightColor: zc.primary.withValues(alpha: 0.04),
    );
  }
}
