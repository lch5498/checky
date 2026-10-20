import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../design_system/app_theme_preset.dart';
import '../design_system/app_font_preset.dart';
import 'home_widget_service.dart';

enum AppThemePreference {
  system('system', '시스템'),
  light('light', '라이트'),
  dark('dark', '다크');

  const AppThemePreference(this.storageValue, this.label);

  final String storageValue;
  final String label;

  ThemeMode get themeMode {
    switch (this) {
      case AppThemePreference.system:
        return ThemeMode.system;
      case AppThemePreference.light:
        return ThemeMode.light;
      case AppThemePreference.dark:
        return ThemeMode.dark;
    }
  }

  static AppThemePreference fromStorageValue(String? value) {
    for (final preference in AppThemePreference.values) {
      if (preference.storageValue == value) {
        return preference;
      }
    }

    return AppThemePreference.system;
  }
}

class ThemePreferenceController extends ChangeNotifier {
  ThemePreferenceController({
    FlutterSecureStorage storage = const FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    ),
  }) : _storage = storage;

  static const _storageKey = 'settings.themePreference';
  static const _presetStorageKey = 'settings.themePreset';
  static const _fontStorageKey = 'settings.fontPreset';

  final FlutterSecureStorage _storage;

  AppThemePreference _preference = AppThemePreference.system;
  AppThemePreset _preset = AppThemePreset.mint;
  AppFontPreset _font = AppFontPreset.system;
  bool _isLoaded = false;

  AppThemePreference get preference => _preference;
  AppThemePreset get preset => _preset;
  AppFontPreset get font => _font;
  ThemeMode get themeMode => _preference.themeMode;
  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    final values = await Future.wait([
      _storage.read(key: _storageKey),
      _storage.read(key: _presetStorageKey),
      _storage.read(key: _fontStorageKey),
    ]);
    _preference = AppThemePreference.fromStorageValue(values[0]);
    _preset = AppThemePreset.fromStorageValue(values[1]);
    _font = AppFontPreset.fromStorageValue(values[2]);
    _isLoaded = true;
    notifyListeners();
    await _syncWidgetAppearance();
  }

  Future<void> setPreference(AppThemePreference preference) async {
    if (_preference == preference && _isLoaded) {
      return;
    }

    _preference = preference;
    _isLoaded = true;
    notifyListeners();

    await _storage.write(key: _storageKey, value: preference.storageValue);
    await _syncWidgetAppearance();
  }

  Future<void> setPreset(AppThemePreset preset) async {
    if (_preset == preset && _isLoaded) return;
    _preset = preset;
    _isLoaded = true;
    notifyListeners();
    await _storage.write(key: _presetStorageKey, value: preset.storageValue);
    await _syncWidgetAppearance();
  }

  Future<void> setFont(AppFontPreset font) async {
    if (_font == font && _isLoaded) return;
    _font = font;
    _isLoaded = true;
    notifyListeners();
    await _storage.write(key: _fontStorageKey, value: font.storageValue);
    await _syncWidgetAppearance();
  }

  Future<void> _syncWidgetAppearance() => HomeWidgetService.updateAppearance(
    preset: _preset,
    mode: _preference.storageValue,
    font: _font,
  );
}

class ThemePreferenceScope
    extends InheritedNotifier<ThemePreferenceController> {
  const ThemePreferenceScope({
    super.key,
    required ThemePreferenceController controller,
    required super.child,
  }) : super(notifier: controller);

  static ThemePreferenceController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ThemePreferenceScope>();

    assert(scope != null, 'ThemePreferenceScope가 위젯 트리에 없습니다.');
    return scope!.notifier!;
  }
}
