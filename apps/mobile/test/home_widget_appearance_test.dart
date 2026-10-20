import 'dart:async';
import 'dart:convert';

import 'package:favis_mobile/core/home_widget_service.dart';
import 'package:favis_mobile/core/theme_preference.dart';
import 'package:favis_mobile/design_system/app_font_preset.dart';
import 'package:favis_mobile/design_system/app_theme_preset.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('home_widget');
  const storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Map<String, Object?> values;
  late Map<String, String> settings;
  late List<Map<String, Object?>> published;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    values = {'schedule.item.0.memberColor': 'blue'};
    settings = {
      'settings.themePreference': 'dark',
      'settings.themePreset': 'lavender',
      'settings.fontPreset': 'poor-story',
      'homeWidget.familyId': 'family',
    };
    published = [];
    messenger.setMockMethodCallHandler(storage, (call) async {
      final key = call.arguments['key'] as String;
      if (call.method == 'read') return settings[key];
      if (call.method == 'write') {
        settings[key] = call.arguments['value'] as String;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'saveWidgetData') {
        values[call.arguments['id'] as String] = call.arguments['data'];
      } else if (call.method == 'updateWidget') {
        published.add(Map.of(values));
      }
      return true;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(storage, null);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '$platform shares every preset and mode without altering member colors',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        for (final preset in AppThemePreset.values) {
          for (final mode in AppThemePreference.values) {
            await HomeWidgetService.updateAppearance(
              preset: preset,
              mode: mode.storageValue,
            );
            final payload =
                jsonDecode(published.last['appearance'] as String) as Map;
            expect(payload['preset'], preset.storageValue);
            expect(payload['mode'], mode.storageValue);
            expect(payload['font'], 'system');
            for (final brightness in Brightness.values) {
              final colors = preset.colors(brightness);
              expect(payload[brightness.name], {
                'background': colors.primarySoft.toARGB32(),
                'surface': colors.surface.toARGB32(),
                'primary': colors.primary.toARGB32(),
                'textPrimary': colors.textPrimary.toARGB32(),
                'textSecondary': colors.textSecondary.toARGB32(),
                'border': colors.border.toARGB32(),
              });
            }
            expect(values['schedule.item.0.memberColor'], 'blue');
          }
        }
      },
    );
  }

  test(
    'legacy and removed font settings safely migrate in widget appearance',
    () async {
      for (final entry in {
        'ainmom': 'park-dahyun',
        'myoeun-ddobak': 'system',
      }.entries) {
        settings['settings.fontPreset'] = entry.key;
        final controller = ThemePreferenceController();
        await controller.load();
        expect(jsonDecode(values['appearance'] as String)['font'], entry.value);
        controller.dispose();
      }
    },
  );

  test('stored settings, theme, mode and font changes sync together', () async {
    final controller = ThemePreferenceController();
    addTearDown(controller.dispose);
    await controller.load();
    expect(jsonDecode(values['appearance'] as String)['preset'], 'lavender');
    expect(jsonDecode(values['appearance'] as String)['mode'], 'dark');
    expect(jsonDecode(values['appearance'] as String)['font'], 'poor-story');
    await controller.setPreset(AppThemePreset.rose);
    expect(jsonDecode(values['appearance'] as String)['preset'], 'rose');
    expect(jsonDecode(values['appearance'] as String)['font'], 'poor-story');
    await controller.setPreference(AppThemePreference.light);
    expect(jsonDecode(values['appearance'] as String)['mode'], 'light');
    final count = published.length;
    await controller.setFont(AppFontPreset.gowunDodum);
    expect(published.length, count + 1);
    expect(jsonDecode(values['appearance'] as String)['font'], 'gowun-dodum');
    expect(jsonDecode(values['appearance'] as String)['preset'], 'rose');
    expect(jsonDecode(values['appearance'] as String)['mode'], 'light');
    await controller.setFont(AppFontPreset.system);
    expect(jsonDecode(values['appearance'] as String)['font'], 'system');
  });

  test('slow writes cannot overwrite a later selection', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final presets = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'saveWidgetData') {
        final preset =
            jsonDecode(call.arguments['data'] as String)['preset'] as String;
        if (preset == 'cream') {
          started.complete();
          await release.future;
        }
        presets.add(preset);
      }
      return true;
    });
    final first = HomeWidgetService.updateAppearance(
      preset: AppThemePreset.cream,
      mode: 'system',
    );
    await started.future;
    final last = HomeWidgetService.updateAppearance(
      preset: AppThemePreset.snow,
      mode: 'dark',
    );
    release.complete();
    await Future.wait([first, last]);
    expect(presets, ['cream', 'snow']);
  });

  test(
    'failed save does not reload and native failure does not poison next sync',
    () async {
      var saves = 0;
      var reloads = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'saveWidgetData') {
          saves++;
          if (saves == 1) return false;
          if (saves == 2) throw PlatformException(code: 'unavailable');
        }
        if (call.method == 'updateWidget') reloads++;
        return true;
      });
      for (var i = 0; i < 3; i++) {
        await HomeWidgetService.updateAppearance(
          preset: AppThemePreset.mint,
          mode: 'system',
        );
        expect(reloads, i == 2 ? 1 : 0);
      }
    },
  );

  test('data refreshes preserve the independently stored appearance', () async {
    await HomeWidgetService.updateAppearance(
      preset: AppThemePreset.cream,
      mode: 'dark',
      font: AppFontPreset.parkDahyun,
    );
    final appearance = values['appearance'];
    await HomeWidgetService.updateParking(familyId: 'family', items: const []);
    const page = HomeWidgetPageData(
      title: '오늘 일정',
      weekday: '월요일',
      day: '19',
      fullDate: '10월 19일',
      items: [],
      moreCount: 0,
    );
    await HomeWidgetService.update(
      familyId: 'family',
      schedule: page,
      nextSchedule: page,
    );
    expect(published, hasLength(3));
    expect(
      published.every((snapshot) => snapshot['appearance'] == appearance),
      isTrue,
    );
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '$platform shares all font presets without changing theme or data',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        for (final font in AppFontPreset.values) {
          await HomeWidgetService.updateAppearance(
            preset: AppThemePreset.lavender,
            mode: 'system',
            font: font,
          );
          final appearance =
              jsonDecode(published.last['appearance'] as String) as Map;
          expect(appearance['font'], font.storageValue);
          expect(appearance['preset'], 'lavender');
          expect(appearance['mode'], 'system');
          expect(values['schedule.item.0.memberColor'], 'blue');
        }
      },
    );
  }
}
