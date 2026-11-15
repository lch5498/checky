import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:favis_mobile/core/api_client.dart';
import 'package:favis_mobile/core/briefing_settings.dart';
import 'package:favis_mobile/design_system/app_theme.dart';
import 'package:favis_mobile/design_system/app_theme_preset.dart';
import 'package:favis_mobile/features/settings/briefing_settings_screen.dart';

class _BriefingApi extends ApiClient {
  BriefingSettings stored = BriefingSettings.defaults;
  final updates = <BriefingSettings>[];
  bool failUpdates = false;
  bool failLoad = false;

  @override
  Future<BriefingSettings> getBriefingSettings(String sessionToken) async {
    expect(sessionToken, 'test-session');
    if (failLoad) throw const ApiConnectionException('offline');
    return stored;
  }

  @override
  Future<BriefingSettings> updateBriefingSettings(
    String sessionToken,
    BriefingSettings settings,
  ) async {
    expect(sessionToken, 'test-session');
    updates.add(settings);
    if (failUpdates) throw const ApiConnectionException('offline');
    stored = settings;
    return settings;
  }
}

Widget _host(_BriefingApi api) {
  const preset = AppThemePreset.mint;
  const brightness = Brightness.light;
  return CupertinoApp(
    theme: AppTheme.cupertinoTheme(brightness, preset.colors(brightness)),
    builder: (context, child) =>
        material.Theme(data: AppTheme.theme(brightness, preset), child: child!),
    home: BriefingSettingsScreen(sessionToken: 'test-session', apiClient: api),
  );
}

void main() {
  test('BriefingSettings round-trips the API shape and formats times', () {
    final parsed = BriefingSettings.fromJson({
      'enabled': true,
      'sendTime': '07:30',
      'weeklyPreviewEnabled': false,
    });
    expect(parsed.hour, 7);
    expect(parsed.minute, 30);
    expect(parsed.sendTime, '07:30');
    expect(parsed.toJson(), {
      'enabled': true,
      'sendTime': '07:30',
      'weeklyPreviewEnabled': false,
    });
    expect(formatBriefingTime(8, 0), '오전 8:00');
    expect(formatBriefingTime(0, 5), '오전 12:05');
    expect(formatBriefingTime(12, 30), '오후 12:30');
    expect(formatBriefingTime(20, 0), '오후 8:00');
    expect(BriefingSettings.fromJson(const {}), BriefingSettings.defaults);
  });

  testWidgets('loads the saved settings and shows the send time', (
    tester,
  ) async {
    final api = _BriefingApi()
      ..stored = const BriefingSettings(
        enabled: true,
        hour: 7,
        minute: 30,
        weeklyPreviewEnabled: false,
      );
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    expect(find.text('오전 7:30'), findsOneWidget);
    final enabled = tester.widget<CupertinoSwitch>(
      find.byKey(const ValueKey('briefing-enabled')),
    );
    expect(enabled.value, isTrue);
    final weekly = tester.widget<CupertinoSwitch>(
      find.byKey(const ValueKey('briefing-weekly')),
    );
    expect(weekly.value, isFalse);
  });

  testWidgets('toggling saves immediately', (tester) async {
    final api = _BriefingApi();
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('briefing-enabled')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('briefing-weekly')));
    await tester.pumpAndSettle();

    expect(api.updates.map((s) => s.toJson()), [
      {'enabled': true, 'sendTime': '08:00', 'weeklyPreviewEnabled': false},
      {'enabled': true, 'sendTime': '08:00', 'weeklyPreviewEnabled': true},
    ]);
  });

  testWidgets('a failed save restores the previous value and offers retry', (
    tester,
  ) async {
    final api = _BriefingApi()..failUpdates = true;
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('briefing-enabled')));
    await tester.pumpAndSettle();

    expect(find.text('offline'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(
      tester
          .widget<CupertinoSwitch>(
            find.byKey(const ValueKey('briefing-enabled')),
          )
          .value,
      isFalse,
    );

    api.failUpdates = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('offline'), findsNothing);
    expect(api.updates.length, 2);
    expect(api.stored.enabled, isTrue);
  });

  testWidgets('the time picker saves the chosen time', (tester) async {
    final api = _BriefingApi();
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('briefing-time')));
    await tester.pumpAndSettle();
    final picker = tester.widget<CupertinoDatePicker>(
      find.byKey(const ValueKey('briefing-time-picker')),
    );
    picker.onDateTimeChanged(DateTime(2026, 1, 1, 7, 20));
    await tester.tap(find.byKey(const ValueKey('briefing-time-done')));
    await tester.pumpAndSettle();

    expect(api.updates.single.sendTime, '07:20');
    expect(find.text('오전 7:20'), findsOneWidget);
  });

  testWidgets('a failed load shows the error with retry', (tester) async {
    final api = _BriefingApi()..failLoad = true;
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    expect(find.text('offline'), findsOneWidget);

    api.failLoad = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('offline'), findsNothing);
    expect(find.text('오전 8:00'), findsOneWidget);
  });
}
