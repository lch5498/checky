import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:favis_mobile/core/api_client.dart';
import 'package:favis_mobile/core/theme_preference.dart';
import 'package:favis_mobile/design_system/app_colors.dart';
import 'package:favis_mobile/design_system/app_theme_preset.dart';
import 'package:favis_mobile/design_system/app_typography.dart';
import 'package:favis_mobile/features/settings/settings_screen.dart';
import 'package:favis_mobile/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  late Map<String, String> stored;

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

  testWidgets(
    'settings only exposes user-facing menus, not widget diagnostics',
    (tester) async {
      const user = AppUser(id: 'user', nickname: '체키', lastLoginAt: null);
      await tester.pumpWidget(
        CheckyApp(
          home: SettingsScreen(
            user: user,
            sessionToken: 'test-token',
            familyCount: 1,
            currentUserId: user.id,
            onSaveProfile:
                (nickname, {required updateFamilyMemberNicknames}) async =>
                    user,
            onDeleteAccount: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('내 정보 관리'), findsOneWidget);
      expect(find.text('그룹 관리'), findsOneWidget);
      expect(find.text('화면 설정'), findsOneWidget);
      expect(find.text('위젯 갱신'), findsNothing);
      expect(find.text('갱신 상태 확인과 지금 갱신'), findsNothing);
      expect(find.byType(CupertinoButton), findsNWidgets(3));
      await tester.tap(find.text('화면 설정'));
      await tester.pumpAndSettle();
      expect(find.byType(ThemeSettingsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('all palettes keep readable text and primary actions', () {
    for (final preset in AppThemePreset.values) {
      for (final brightness in Brightness.values) {
        final colors = preset.colors(brightness);
        final backgrounds = [
          colors.background,
          colors.surface,
          colors.surfaceElevated,
        ];
        final foregrounds = [
          colors.textPrimary,
          colors.textSecondary,
          colors.textMuted,
        ];
        for (final background in backgrounds) {
          for (final foreground in foregrounds) {
            expect(
              _contrast(foreground, background),
              greaterThanOrEqualTo(4.5),
              reason: '${preset.name}/${brightness.name} body text',
            );
          }
        }
        expect(
          _contrast(colors.primary, colors.onPrimary),
          greaterThanOrEqualTo(4.5),
          reason: '${preset.name}/${brightness.name} primary button',
        );
        expect(
          _contrast(colors.primary, colors.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(colors.primary, colors.primarySoft),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });

  test(
    'unknown preset falls back to mint and keeps the existing screen mode',
    () async {
      stored['settings.themePreference'] = 'dark';
      stored['settings.themePreset'] = 'removed-preset';
      final controller = ThemePreferenceController();
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.preference, AppThemePreference.dark);
      expect(controller.preset, AppThemePreset.mint);
      await controller.setPreset(AppThemePreset.cream);
      expect(stored['settings.themePreset'], 'cream');
      expect(stored['settings.themePreference'], 'dark');
    },
  );

  testWidgets(
    'selection updates open routes, preserves input and restores after restart',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final input = TextEditingController(text: '작성 중인 내용');
      addTearDown(input.dispose);

      await tester.pumpWidget(CheckyApp(home: _ExistingRoute(input: input)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('화면 설정'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('theme-preset-snow')).hitTestable(),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('theme-preset-snow')));
      await tester.pumpAndSettle();
      expect(stored['settings.themePreset'], 'snow');
      final settingsContext = tester.element(find.byType(ThemeSettingsScreen));
      expect(
        CupertinoTheme.of(settingsContext).primaryColor,
        AppThemePreset.snow.colors(Brightness.light).primary,
      );
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.text('다크'),
        -200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('다크'));
      await tester.pumpAndSettle();
      expect(CupertinoTheme.brightnessOf(settingsContext), Brightness.dark);
      Navigator.of(settingsContext).pop();
      await tester.pumpAndSettle();
      expect(input.text, '작성 중인 내용');
      final surface = tester.widget<ColoredBox>(
        find.byKey(const ValueKey('existing-surface')),
      );
      expect(
        surface.color,
        AppThemePreset.snow.colors(Brightness.dark).surface,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(const CheckyApp(home: ThemeSettingsScreen()));
      await tester.pumpAndSettle();
      final restoredContext = tester.element(find.byType(ThemeSettingsScreen));
      final restored = ThemePreferenceScope.of(restoredContext);
      expect(restored.preset, AppThemePreset.snow);
      expect(restored.preference, AppThemePreference.dark);
      expect(tester.takeException(), isNull);
    },
  );

  for (final preset in AppThemePreset.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '${preset.name}/${brightness.name} settings fit a phone screen',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          stored['settings.themePreset'] = preset.storageValue;
          stored['settings.themePreference'] = brightness.name;
          await tester.pumpWidget(const CheckyApp(home: ThemeSettingsScreen()));
          await tester.pumpAndSettle();
          final context = tester.element(find.byType(ThemeSettingsScreen));
          expect(ThemePreferenceScope.of(context).preset, preset);
          expect(
            CupertinoTheme.of(context).primaryColor,
            preset.colors(brightness).primary,
          );
          for (final option in AppThemePreset.values) {
            await tester.scrollUntilVisible(
              find
                  .byKey(ValueKey('theme-preset-${option.storageValue}'))
                  .hitTestable(),
              160,
              scrollable: find.byType(Scrollable).last,
            );
            expect(find.text(option.label), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
}

class _ExistingRoute extends StatelessWidget {
  const _ExistingRoute({required this.input});
  final TextEditingController input;

  @override
  Widget build(BuildContext context) {
    AppColors.of(context);
    return CupertinoPageScaffold(
      child: SafeArea(
        child: ColoredBox(
          key: const ValueKey('existing-surface'),
          color: AppColors.surface,
          child: Column(
            children: [
              CupertinoTextField(controller: input),
              CupertinoButton(
                onPressed: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => const ThemeSettingsScreen(),
                  ),
                ),
                child: const Text('화면 설정', style: AppTypography.button),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
