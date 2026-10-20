import 'package:flutter/cupertino.dart';

enum AppFontPreset {
  system('system', '기본', null, null),
  gowunDodum('gowun-dodum', '고운돋움', 'CheckyGowunDodum', 'gowundodum'),
  gowunBatang('gowun-batang', '고운바탕', 'CheckyGowunBatang', 'gowunbatang'),
  parkDahyun(
    'park-dahyun',
    '온글잎 박다현체',
    'CheckyParkDahyun',
    'parkdahyun',
    licenseFile: 'LICENSE.txt',
  ),
  poorStory('poor-story', '푸어스토리', 'CheckyPoorStory', 'poorstory'),
  incheonHimchan(
    'incheon-himchan',
    '인천교육힘찬체',
    'CheckyIncheonHimchan',
    'incheonhimchan',
    licenseFile: 'LICENSE.txt',
  );

  const AppFontPreset(
    this.storageValue,
    this.label,
    this.fontFamily,
    this.assetDirectory, {
    this.licenseFile = 'OFL.txt',
  });

  final String storageValue;
  final String label;
  final String? fontFamily;
  final String? assetDirectory;
  final String licenseFile;

  // Missing glyphs use the platform fallback rather than another decorative font.
  static const fallbackFamilies = ['sans-serif'];

  String? get licenseAsset => assetDirectory == null
      ? null
      : 'assets/fonts/$assetDirectory/$licenseFile';

  static AppFontPreset fromStorageValue(String? value) {
    // Preserve the user's handwriting preference when replacing Ainmom.
    if (value == 'ainmom') return parkDahyun;
    return values.firstWhere(
      (font) => font.storageValue == value,
      orElse: () => system,
    );
  }

  /// An explicit system family also lets the default-font preview stay native
  /// while another font is selected for the rest of the app.
  TextStyle applyTo(TextStyle style) => style.copyWith(
    fontFamily:
        fontFamily ?? const CupertinoTextThemeData().textStyle.fontFamily,
    fontFamilyFallback: fallbackFamilies,
  );
}
