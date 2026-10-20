import 'package:flutter/material.dart';

import 'app_theme_extension.dart';
import 'app_theme_preset.dart';

class AppColors {
  const AppColors._();

  static Brightness _brightness = Brightness.light;
  static AppThemeExtension _colors = AppThemePreset.mint.colors(
    Brightness.light,
  );

  static void useAppearance(Brightness brightness, AppThemeExtension colors) {
    _brightness = brightness;
    _colors = colors;
  }

  /// Registers a theme dependency so open routes update immediately.
  /// New widgets should keep the returned palette in a local `colors` variable.
  static AppThemeExtension of(BuildContext context) =>
      Theme.of(context).extension<AppThemeExtension>() ?? _colors;

  static Color get background => _colors.background;
  static Color get surface => _colors.surface;
  static Color get surfaceElevated => _colors.surfaceElevated;
  static Color get primary => _colors.primary;
  static Color get onPrimary => _colors.onPrimary;
  static Color get primarySoft => _colors.primarySoft;
  static Color get textPrimary => _colors.textPrimary;
  static Color get textSecondary => _colors.textSecondary;
  static Color get textMuted => _colors.textMuted;
  static Color get border => _colors.border;
  static Color get success => _colors.success;
  static Color get warning => _colors.warning;
  static Color get danger => _colors.danger;
  static Color get onDanger => _brightness == Brightness.dark
      ? const Color(0xFF3D1018)
      : const Color(0xFFFFFFFF);

  // Semantic accents and image surfaces deliberately do not follow the preset.
  static Color get brandCoral => _brightness == Brightness.dark
      ? const Color(0xFFFF98A3)
      : const Color(0xFFB8323D);
  static Color get brandLavender => _brightness == Brightness.dark
      ? const Color(0xFFC7AFF0)
      : const Color(0xFF7150A2);
  static const imageTextPrimary = Color(0xFF142E29);
  static const imageTextSecondary = Color(0xFF405F56);
  static const imageAccent = Color(0xFF087D74);
}
