import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:favis_mobile/core/theme_preference.dart';
import 'package:favis_mobile/design_system/app_colors.dart';
import 'package:favis_mobile/design_system/app_font_preset.dart';
import 'package:favis_mobile/design_system/app_theme_preset.dart';
import 'package:favis_mobile/design_system/app_typography.dart';
import 'package:favis_mobile/features/settings/font_settings_screen.dart';
import 'package:favis_mobile/features/settings/settings_screen.dart';
import 'package:favis_mobile/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  late Map<String, String> stored;
  const assets = {
    AppFontPreset.gowunDodum: ['gowundodum/GowunDodum-Regular.ttf'],
    AppFontPreset.gowunBatang: [
      'gowunbatang/GowunBatang-Regular.ttf',
      'gowunbatang/GowunBatang-Bold.ttf',
    ],
    AppFontPreset.parkDahyun: ['parkdahyun/Ownglyph-ParkDaHyun.ttf'],
    AppFontPreset.poorStory: ['poorstory/PoorStory-Regular.ttf'],
    AppFontPreset.incheonHimchan: ['incheonhimchan/ICEHimchan-Regular.ttf'],
  };

  setUpAll(() async {
    // Load the actual bundled fonts so overflow checks use their real metrics.
    for (final entry in assets.entries) {
      final loader = FontLoader(entry.key.fontFamily!);
      for (final asset in entry.value) {
        loader.addFont(rootBundle.load('assets/fonts/$asset'));
      }
      await loader.load();
    }
  });

  setUp(() {
    stored = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('home_widget'),
          (_) async => true,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (call) async {
          final arguments = Map<String, dynamic>.from(call.arguments as Map);
          final key = arguments['key'] as String;
          if (call.method == 'read') return stored[key];
          if (call.method == 'write') {
            stored[key] = arguments['value'] as String;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
  });

  test(
    'font choices contain the six supported presets without removed fonts',
    () {
      expect(AppFontPreset.values.map((font) => font.label), [
        '기본',
        '고운돋움',
        '고운바탕',
        '온글잎 박다현체',
        '푸어스토리',
        '인천교육힘찬체',
      ]);
      for (final retired in ['gaegu', 'nanum-pen', 'myoeun-ddobak']) {
        expect(AppFontPreset.fromStorageValue(retired), AppFontPreset.system);
      }
      expect(
        AppFontPreset.fromStorageValue('ainmom'),
        AppFontPreset.parkDahyun,
      );
    },
  );

  test(
    'removed Myoeun preference restores as default without changing theme',
    () async {
      stored.addAll({
        'settings.themePreference': 'dark',
        'settings.themePreset': 'cream',
        'settings.fontPreset': 'myoeun-ddobak',
      });
      final controller = ThemePreferenceController();
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.font, AppFontPreset.system);
      expect(controller.preference, AppThemePreference.dark);
      expect(controller.preset, AppThemePreset.cream);
    },
  );

  test(
    'saved Ainmom selection restores as Park Dahyun without changing theme',
    () async {
      stored.addAll({
        'settings.themePreference': 'dark',
        'settings.themePreset': 'lavender',
        'settings.fontPreset': 'ainmom',
      });
      final controller = ThemePreferenceController();
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.font, AppFontPreset.parkDahyun);
      expect(controller.preference, AppThemePreference.dark);
      expect(controller.preset, AppThemePreset.lavender);
      await controller.setFont(AppFontPreset.system);
      await controller.setFont(AppFontPreset.parkDahyun);
      expect(stored['settings.fontPreset'], 'park-dahyun');
      final restored = ThemePreferenceController();
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.font, AppFontPreset.parkDahyun);
    },
  );

  test(
    'all bundled families render mixed text and include their original licenses',
    () async {
      final widths = <double>{};
      for (final font in assets.keys) {
        final painter = TextPainter(
          text: TextSpan(
            text: '가족과 함께 Checky 123',
            style: font.applyTo(AppTypography.bodyLarge),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        widths.add(painter.width);
        expect(painter.width, greaterThan(0));
        painter.dispose();
        final license = await rootBundle.loadString(font.licenseAsset!);
        expect(license, contains('Copyright'));
        if (font == AppFontPreset.parkDahyun) {
          expect(license, contains('온글잎 오리지널 폰트 라이선스'));
          expect(license, contains('폰트 수정 | 폰트 파일의 수정 가능 | X'));
          expect(license, contains('임베딩 | HW 내 탑재, SW 내 탑재, 웹폰트 등 웹서버 탑재 | O'));
        } else if (font == AppFontPreset.incheonHimchan) {
          expect(license, contains('인천교육서체 저작권 안내'));
          expect(license, contains('특별한 허가절차 없이 사용할 수 있습니다.'));
          expect(license, contains('https://www.ice.go.kr/'));
        } else {
          expect(license, contains('SIL OPEN FONT LICENSE Version 1.1'));
        }
        expect(
          font.applyTo(AppTypography.bodyMedium).fontFamilyFallback,
          contains('sans-serif'),
        );
      }
      // Different font metrics confirm these assets did not all resolve to a fallback.
      expect(widths.length, assets.length);
    },
  );

  test(
    'font preference restores independently and unknown values use the default',
    () async {
      stored.addAll({
        'settings.themePreference': 'dark',
        'settings.themePreset': 'rose',
        'settings.fontPreset': 'unknown-font',
      });
      final controller = ThemePreferenceController();
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.font, AppFontPreset.system);
      for (final font in AppFontPreset.values) {
        await controller.setFont(font);
        final restored = ThemePreferenceController();
        await restored.load();
        expect(restored.font, font);
        expect(restored.preference, AppThemePreference.dark);
        expect(restored.preset, AppThemePreset.rose);
        restored.dispose();
      }
    },
  );

  testWidgets(
    'font changes apply to open routes and inputs and survive restart',
    (tester) async {
      final input = TextEditingController(text: '입력 유지 · Checky');
      addTearDown(input.dispose);
      await tester.pumpWidget(CheckyApp(home: _TypographyRoute(input: input)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('화면 설정'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-font-settings')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('font-preset-park-dahyun')).hitTestable(),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('font-preset-park-dahyun')));
      await tester.pumpAndSettle();
      expect(stored['settings.fontPreset'], 'park-dahyun');
      Navigator.of(tester.element(find.byType(FontSettingsScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.text('온글잎 박다현체'), findsOneWidget);
      Navigator.of(tester.element(find.byType(ThemeSettingsScreen))).pop();
      await tester.pumpAndSettle();
      final richText = tester.widget<RichText>(
        find.descendant(
          of: find.byKey(const ValueKey('mixed-title')),
          matching: find.byType(RichText),
        ),
      );
      expect(
        richText.text.style!.fontFamily,
        AppFontPreset.parkDahyun.fontFamily,
      );
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).style.fontFamily,
        AppFontPreset.parkDahyun.fontFamily,
      );
      expect(input.text, '입력 유지 · Checky');
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(const CheckyApp(home: FontSettingsScreen()));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(FontSettingsScreen));
      expect(ThemePreferenceScope.of(context).font, AppFontPreset.parkDahyun);
      expect(
        CupertinoTheme.of(context).textTheme.textStyle.fontFamily,
        AppFontPreset.parkDahyun.fontFamily,
      );
    },
  );

  testWidgets(
    'all font previews work on a narrow screen with large text and can reset to default',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(const CheckyApp(home: FontSettingsScreen()));
      await tester.pumpAndSettle();
      for (final font in AppFontPreset.values) {
        final option = find.byKey(ValueKey('font-preset-${font.storageValue}'));
        await tester.scrollUntilVisible(
          option.hitTestable(),
          160,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(option);
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(FontSettingsScreen));
        expect(ThemePreferenceScope.of(context).font, font);
        expect(
          CupertinoTheme.of(context).textTheme.textStyle.fontFamily,
          font.applyTo(AppTypography.bodyMedium).fontFamily,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.scrollUntilVisible(
        find.text('글꼴 라이선스').hitTestable(),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future.wait([
          for (final font in assets.keys)
            rootBundle.loadString(font.licenseAsset!),
        ]);
        await tester.tap(find.text('글꼴 라이선스'));
        await tester.pump();
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('SIL OPEN FONT LICENSE'), findsWidgets);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.text('글꼴 라이선스').first)).pop();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('font-preset-system')).hitTestable(),
        -200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('font-preset-system')));
      await tester.pumpAndSettle();
      expect(stored['settings.fontPreset'], 'system');
      final context = tester.element(find.byType(FontSettingsScreen));
      expect(
        CupertinoTheme.of(context).textTheme.textStyle.fontFamily,
        AppFontPreset.system.applyTo(AppTypography.bodyMedium).fontFamily,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _TypographyRoute extends StatelessWidget {
  const _TypographyRoute({required this.input});
  final TextEditingController input;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          '가족 · Checky',
          key: const ValueKey('mixed-title'),
          style: AppTypography.titleSmall.copyWith(color: colors.textPrimary),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            CupertinoTextField(controller: input),
            CupertinoButton(
              onPressed: () => Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) => const ThemeSettingsScreen(),
                ),
              ),
              child: const Text('화면 설정'),
            ),
          ],
        ),
      ),
    );
  }
}
