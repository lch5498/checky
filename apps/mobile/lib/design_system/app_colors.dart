import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  static Brightness _brightness = Brightness.dark;

  static const checkyMint = Color(0xFF4ECDC4);
  static const checkyCoral = Color(0xFFFF6B6B);
  static const checkyLavender = Color(0xFFA78BFA);

  static const darkBackgroundValue = Color(0xFF10171B);
  static const darkSurfaceValue = Color(0xFF172225);
  static const darkSurfaceElevatedValue = Color(0xFF203033);
  static const darkPrimaryValue = Color(0xFF63DCD4);
  static const darkPrimarySoftValue = Color(0xFF1D4545);
  static const darkTextPrimaryValue = Color(0xFFF6FFFD);
  static const darkTextSecondaryValue = Color(0xFFC5D7D8);
  static const darkTextMutedValue = Color(0xFF89A3A5);
  static const darkBorderValue = Color(0xFF2B4245);
  static const darkSuccessValue = Color(0xFFA78BFA);
  static const darkWarningValue = Color(0xFFFFC66D);
  static const darkDangerValue = Color(0xFFFF8585);
  static const darkCoralValue = Color(0xFFFF8585);
  static const darkLavenderValue = Color(0xFFBCA7FF);

  static const lightBackground = Color(0xFFF6FFFD);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceElevated = Color(0xFFEFFFFD);
  static const lightPrimary = checkyMint;
  static const lightPrimarySoft = Color(0xFFDDF7F5);
  static const lightTextPrimary = Color(0xFF132224);
  static const lightTextSecondary = Color(0xFF486164);
  static const lightTextMuted = Color(0xFF81989B);
  static const lightBorder = Color(0xFFD8EDEA);
  static const lightSuccess = checkyLavender;
  static const lightWarning = Color(0xFFE78B00);
  static const lightDanger = checkyCoral;
  static const lightCoral = checkyCoral;
  static const lightLavender = checkyLavender;

  static void useBrightness(Brightness brightness) {
    _brightness = brightness;
  }

  static bool get _isDark => _brightness == Brightness.dark;

  static Color get darkBackground =>
      _isDark ? darkBackgroundValue : lightBackground;
  static Color get darkSurface => _isDark ? darkSurfaceValue : lightSurface;
  static Color get darkSurfaceElevated =>
      _isDark ? darkSurfaceElevatedValue : lightSurfaceElevated;
  static Color get darkPrimary => _isDark ? darkPrimaryValue : lightPrimary;
  static Color get darkPrimarySoft =>
      _isDark ? darkPrimarySoftValue : lightPrimarySoft;
  static Color get darkTextPrimary =>
      _isDark ? darkTextPrimaryValue : lightTextPrimary;
  static Color get darkTextSecondary =>
      _isDark ? darkTextSecondaryValue : lightTextSecondary;
  static Color get darkTextMuted =>
      _isDark ? darkTextMutedValue : lightTextMuted;
  static Color get darkBorder => _isDark ? darkBorderValue : lightBorder;
  static Color get darkSuccess => _isDark ? darkSuccessValue : lightSuccess;
  static Color get darkWarning => _isDark ? darkWarningValue : lightWarning;
  static Color get darkDanger => _isDark ? darkDangerValue : lightDanger;
  static Color get brandCoral => _isDark ? darkCoralValue : lightCoral;
  static Color get brandLavender => _isDark ? darkLavenderValue : lightLavender;
}
