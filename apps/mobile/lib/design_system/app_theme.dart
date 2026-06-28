import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_theme_extension.dart';
import 'app_typography.dart';

class AppTheme {
  const AppTheme._();

  static const darkTokens = AppThemeExtension(
    background: AppColors.darkBackgroundValue,
    surface: AppColors.darkSurfaceValue,
    surfaceElevated: AppColors.darkSurfaceElevatedValue,
    primary: AppColors.darkPrimaryValue,
    primarySoft: AppColors.darkPrimarySoftValue,
    textPrimary: AppColors.darkTextPrimaryValue,
    textSecondary: AppColors.darkTextSecondaryValue,
    textMuted: AppColors.darkTextMutedValue,
    border: AppColors.darkBorderValue,
    success: AppColors.darkSuccessValue,
    warning: AppColors.darkWarningValue,
    danger: AppColors.darkDangerValue,
  );

  static const lightTokens = AppThemeExtension(
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    surfaceElevated: AppColors.lightSurfaceElevated,
    primary: AppColors.lightPrimary,
    primarySoft: AppColors.lightPrimarySoft,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
    textMuted: AppColors.lightTextMuted,
    border: AppColors.lightBorder,
    success: AppColors.lightSuccess,
    warning: AppColors.lightWarning,
    danger: AppColors.lightDanger,
  );

  static ThemeData get darkTheme => _theme(Brightness.dark, darkTokens);

  static ThemeData get lightTheme => _theme(Brightness.light, lightTokens);

  static CupertinoThemeData cupertinoTheme(Brightness brightness) {
    final tokens = brightness == Brightness.dark ? darkTokens : lightTokens;
    final bodyStyle = AppTypography.bodyMedium.copyWith(
      inherit: false,
      color: tokens.textPrimary,
      decoration: TextDecoration.none,
    );
    final actionStyle = bodyStyle.copyWith(
      color: tokens.primary,
      fontSize: 17,
      fontWeight: FontWeight.w600,
    );

    return CupertinoThemeData(
      brightness: brightness,
      primaryColor: tokens.primary,
      scaffoldBackgroundColor: tokens.background,
      barBackgroundColor: tokens.background.withValues(alpha: 0.92),
      textTheme: CupertinoTextThemeData(
        textStyle: bodyStyle,
        actionTextStyle: actionStyle,
        navActionTextStyle: actionStyle,
        navTitleTextStyle: AppTypography.titleMedium.copyWith(
          inherit: false,
          color: tokens.textPrimary,
          decoration: TextDecoration.none,
        ),
        navLargeTitleTextStyle: AppTypography.display.copyWith(
          inherit: false,
          color: tokens.textPrimary,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }

  static ThemeData _theme(Brightness brightness, AppThemeExtension tokens) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: tokens.primary,
          brightness: brightness,
          primary: tokens.primary,
          surface: tokens.surface,
          error: tokens.danger,
        ).copyWith(
          secondary: brightness == Brightness.dark
              ? AppColors.darkCoralValue
              : AppColors.lightCoral,
          tertiary: brightness == Brightness.dark
              ? AppColors.darkLavenderValue
              : AppColors.lightLavender,
          onPrimary: brightness == Brightness.dark
              ? AppColors.darkBackgroundValue
              : AppColors.lightSurface,
          onSurface: tokens.textPrimary,
          onError: brightness == Brightness.dark
              ? AppColors.darkBackgroundValue
              : AppColors.lightSurface,
          surfaceContainerHighest: tokens.surfaceElevated,
          outline: tokens.border,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.background,
      fontFamily: null,
      textTheme: TextTheme(
        displayLarge: AppTypography.display.copyWith(color: tokens.textPrimary),
        titleLarge: AppTypography.titleLarge.copyWith(
          color: tokens.textPrimary,
        ),
        titleMedium: AppTypography.titleMedium.copyWith(
          color: tokens.textPrimary,
        ),
        bodyLarge: AppTypography.bodyLarge.copyWith(color: tokens.textPrimary),
        bodyMedium: AppTypography.bodyMedium.copyWith(
          color: tokens.textSecondary,
        ),
        bodySmall: AppTypography.bodySmall.copyWith(color: tokens.textMuted),
        labelSmall: AppTypography.caption.copyWith(color: tokens.textMuted),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor: tokens.background,
        foregroundColor: tokens.textPrimary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTypography.titleMedium.copyWith(
          color: tokens.textPrimary,
        ),
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

          return AppTypography.caption.copyWith(
            color: selected ? tokens.textPrimary : tokens.textMuted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
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
