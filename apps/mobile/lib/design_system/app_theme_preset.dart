import 'package:flutter/material.dart';

import 'app_theme_extension.dart';

enum AppThemePreset {
  mint('mint', '민트'),
  cream('cream', '크림'),
  lavender('lavender', '라벤더'),
  rose('rose', '로즈'),
  snow('snow', '스노우');

  const AppThemePreset(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static AppThemePreset fromStorageValue(String? value) => values.firstWhere(
    (preset) => preset.storageValue == value,
    orElse: () => mint,
  );

  AppThemeExtension colors(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (this) {
      mint => dark ? _mintDark : _mintLight,
      cream => dark ? _creamDark : _creamLight,
      lavender => dark ? _lavenderDark : _lavenderLight,
      rose => dark ? _roseDark : _roseLight,
      snow => dark ? _snowDark : _snowLight,
    };
  }
}

// Status and member colors have the same meaning in every preset.
const _lightSuccess = Color(0xFF28734F);
const _lightWarning = Color(0xFF855400);
const _lightDanger = Color(0xFFB8323D);
const _darkSuccess = Color(0xFF86CDA4);
const _darkWarning = Color(0xFFF2C16B);
const _darkDanger = Color(0xFFFF98A3);

const _mintLight = AppThemeExtension(
  background: Color(0xFFEEF9F6),
  surface: Color(0xFFF8FFFC),
  surfaceElevated: Color(0xFFDFF2EC),
  primary: Color(0xFF067168),
  onPrimary: Color(0xFFFFFFFF),
  primarySoft: Color(0xFFD5EEE7),
  textPrimary: Color(0xFF142E29),
  textSecondary: Color(0xFF405F56),
  textMuted: Color(0xFF526F66),
  border: Color(0xFFC8DED5),
  success: _lightSuccess,
  warning: _lightWarning,
  danger: _lightDanger,
);

const _mintDark = AppThemeExtension(
  background: Color(0xFF101B1A),
  surface: Color(0xFF182725),
  surfaceElevated: Color(0xFF223530),
  primary: Color(0xFF75DAC5),
  onPrimary: Color(0xFF10261F),
  primarySoft: Color(0xFF244A40),
  textPrimary: Color(0xFFF0FCF7),
  textSecondary: Color(0xFFC3D9D0),
  textMuted: Color(0xFF9FB9AE),
  border: Color(0xFF365148),
  success: _darkSuccess,
  warning: _darkWarning,
  danger: _darkDanger,
);

const _creamLight = AppThemeExtension(
  background: Color(0xFFFAF6ED),
  surface: Color(0xFFFFFCF5),
  surfaceElevated: Color(0xFFF0E7D6),
  primary: Color(0xFF7B5732),
  onPrimary: Color(0xFFFFFFFF),
  primarySoft: Color(0xFFEDE0C8),
  textPrimary: Color(0xFF342B21),
  textSecondary: Color(0xFF675A48),
  textMuted: Color(0xFF756550),
  border: Color(0xFFDED1BA),
  success: _lightSuccess,
  warning: _lightWarning,
  danger: _lightDanger,
);

const _creamDark = AppThemeExtension(
  background: Color(0xFF211C16),
  surface: Color(0xFF2D261E),
  surfaceElevated: Color(0xFF3B3227),
  primary: Color(0xFFE7C28E),
  onPrimary: Color(0xFF312414),
  primarySoft: Color(0xFF4D3C26),
  textPrimary: Color(0xFFFFF8EC),
  textSecondary: Color(0xFFE0D1BC),
  textMuted: Color(0xFFBEAC92),
  border: Color(0xFF554835),
  success: _darkSuccess,
  warning: _darkWarning,
  danger: _darkDanger,
);

const _lavenderLight = AppThemeExtension(
  background: Color(0xFFF5F2FC),
  surface: Color(0xFFFDFBFF),
  surfaceElevated: Color(0xFFEAE3F7),
  primary: Color(0xFF7150A2),
  onPrimary: Color(0xFFFFFFFF),
  primarySoft: Color(0xFFE9DFF5),
  textPrimary: Color(0xFF2B2338),
  textSecondary: Color(0xFF62556F),
  textMuted: Color(0xFF705C7F),
  border: Color(0xFFDAD0E7),
  success: _lightSuccess,
  warning: _lightWarning,
  danger: _lightDanger,
);

const _lavenderDark = AppThemeExtension(
  background: Color(0xFF1B1724),
  surface: Color(0xFF262032),
  surfaceElevated: Color(0xFF342C43),
  primary: Color(0xFFC7AFF0),
  onPrimary: Color(0xFF29183E),
  primarySoft: Color(0xFF47355E),
  textPrimary: Color(0xFFF7F0FF),
  textSecondary: Color(0xFFD9C9E9),
  textMuted: Color(0xFFB8A5CE),
  border: Color(0xFF4D405E),
  success: _darkSuccess,
  warning: _darkWarning,
  danger: _darkDanger,
);

const _roseLight = AppThemeExtension(
  background: Color(0xFFFFF2F6),
  surface: Color(0xFFFFFBFD),
  surfaceElevated: Color(0xFFF7E1EA),
  primary: Color(0xFFA23B68),
  onPrimary: Color(0xFFFFFFFF),
  primarySoft: Color(0xFFF6DDE7),
  textPrimary: Color(0xFF3B202E),
  textSecondary: Color(0xFF71485D),
  textMuted: Color(0xFF7F5368),
  border: Color(0xFFE8C7D5),
  success: _lightSuccess,
  warning: _lightWarning,
  danger: _lightDanger,
);

const _roseDark = AppThemeExtension(
  background: Color(0xFF24171F),
  surface: Color(0xFF30212B),
  surfaceElevated: Color(0xFF402D39),
  primary: Color(0xFFF1ADC8),
  onPrimary: Color(0xFF3A1728),
  primarySoft: Color(0xFF5A3045),
  textPrimary: Color(0xFFFFF1F7),
  textSecondary: Color(0xFFE5C7D6),
  textMuted: Color(0xFFC8A6B8),
  border: Color(0xFF604151),
  success: _darkSuccess,
  warning: _darkWarning,
  danger: _darkDanger,
);

const _snowLight = AppThemeExtension(
  background: Color(0xFFF5F6F8),
  surface: Color(0xFFFFFFFF),
  surfaceElevated: Color(0xFFE9EBEF),
  primary: Color(0xFF35445A),
  onPrimary: Color(0xFFFFFFFF),
  primarySoft: Color(0xFFE3E7ED),
  textPrimary: Color(0xFF1E2632),
  textSecondary: Color(0xFF4B5768),
  textMuted: Color(0xFF5D6878),
  border: Color(0xFFD4D9E1),
  success: _lightSuccess,
  warning: _lightWarning,
  danger: _lightDanger,
);

const _snowDark = AppThemeExtension(
  background: Color(0xFF15171B),
  surface: Color(0xFF202329),
  surfaceElevated: Color(0xFF2C3038),
  primary: Color(0xFFD7DFEC),
  onPrimary: Color(0xFF1E293B),
  primarySoft: Color(0xFF3D4656),
  textPrimary: Color(0xFFF7F8FA),
  textSecondary: Color(0xFFD3D8E1),
  textMuted: Color(0xFFAFB8C6),
  border: Color(0xFF454D5A),
  success: _darkSuccess,
  warning: _darkWarning,
  danger: _darkDanger,
);
