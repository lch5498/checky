import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_theme_extension.dart';
import 'app_theme_preset.dart';
import 'app_typography.dart';
import 'app_font_preset.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData theme(
    Brightness brightness,
    AppThemePreset preset, {
    AppFontPreset font = AppFontPreset.system,
  }) => _theme(brightness, preset.colors(brightness), font);

  static CupertinoThemeData cupertinoTheme(
    Brightness brightness,
    AppThemeExtension tokens, {
    AppFontPreset font = AppFontPreset.system,
  }) {
    final bodyStyle = font
        .applyTo(AppTypography.bodyMedium)
        .copyWith(
          inherit: false,
          color: tokens.textPrimary,
          decoration: TextDecoration.none,
        );
    final actionStyle = font
        .applyTo(AppTypography.button)
        .copyWith(
          inherit: false,
          color: tokens.primary,
          decoration: TextDecoration.none,
        );

    return CupertinoThemeData(
      brightness: brightness,
      primaryColor: tokens.primary,
      primaryContrastingColor: tokens.onPrimary,
      scaffoldBackgroundColor: tokens.background,
      barBackgroundColor: tokens.background.withValues(alpha: 0.92),
      textTheme: CupertinoTextThemeData(
        textStyle: bodyStyle,
        actionTextStyle: actionStyle,
        navActionTextStyle: actionStyle,
        tabLabelTextStyle: font
            .applyTo(AppTypography.caption)
            .copyWith(color: tokens.textSecondary),
        pickerTextStyle: font
            .applyTo(AppTypography.bodyLarge)
            .copyWith(color: tokens.textPrimary),
        dateTimePickerTextStyle: font
            .applyTo(AppTypography.bodyLarge)
            .copyWith(color: tokens.textPrimary),
        navTitleTextStyle: font
            .applyTo(AppTypography.titleSmall)
            .copyWith(
              inherit: false,
              color: tokens.textPrimary,
              decoration: TextDecoration.none,
            ),
        navLargeTitleTextStyle: font
            .applyTo(AppTypography.display)
            .copyWith(
              inherit: false,
              color: tokens.textPrimary,
              decoration: TextDecoration.none,
            ),
      ),
    );
  }

  static ThemeData _theme(
    Brightness brightness,
    AppThemeExtension tokens,
    AppFontPreset font,
  ) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: tokens.primary,
          brightness: brightness,
          primary: tokens.primary,
          surface: tokens.surface,
          error: tokens.danger,
        ).copyWith(
          secondary: tokens.success,
          tertiary: tokens.warning,
          onPrimary: tokens.onPrimary,
          onSurface: tokens.textPrimary,
          onError: brightness == Brightness.dark
              ? const Color(0xFF3D1018)
              : Colors.white,
          surfaceContainerHighest: tokens.surfaceElevated,
          outline: tokens.border,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.background,
      fontFamily: font.fontFamily,
      fontFamilyFallback: AppFontPreset.fallbackFamilies,
      textTheme: TextTheme(
        displayLarge: AppTypography.display.copyWith(color: tokens.textPrimary),
        titleLarge: AppTypography.titleLarge.copyWith(
          color: tokens.textPrimary,
        ),
        titleMedium: AppTypography.titleMedium.copyWith(
          color: tokens.textPrimary,
        ),
        titleSmall: AppTypography.titleSmall.copyWith(
          color: tokens.textPrimary,
        ),
        bodyLarge: AppTypography.bodyLarge.copyWith(color: tokens.textPrimary),
        bodyMedium: AppTypography.bodyMedium.copyWith(
          color: tokens.textPrimary,
        ),
        bodySmall: AppTypography.bodySmall.copyWith(color: tokens.textMuted),
        labelSmall: AppTypography.caption.copyWith(color: tokens.textMuted),
        labelLarge: AppTypography.button.copyWith(color: tokens.primary),
        labelMedium: AppTypography.labelSmall.copyWith(
          color: tokens.textSecondary,
        ),
      ).apply(fontFamily: font.fontFamily),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor: tokens.background,
        foregroundColor: tokens.textPrimary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: font
            .applyTo(AppTypography.titleSmall)
            .copyWith(color: tokens.textPrimary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: tokens.surface,
        indicatorColor: tokens.primarySoft,
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);

          return IconThemeData(
            color: selected ? tokens.primary : tokens.textMuted,
            size: selected ? 23 : 22,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);

          return font
              .applyTo(AppTypography.caption)
              .copyWith(
                color: selected ? tokens.textPrimary : tokens.textMuted,
              );
        }),
      ),
      dividerTheme: DividerThemeData(
        color: tokens.border,
        thickness: 1,
        space: 1,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: tokens.primary,
        selectionColor: tokens.primarySoft,
        selectionHandleColor: tokens.primary,
      ),
      extensions: [tokens],
    );
  }
}
