import 'package:favis_mobile/core/api_client.dart';
import 'package:favis_mobile/core/auth_session_store.dart';
import 'package:favis_mobile/core/home_widget_background_refresh.dart';
import 'package:favis_mobile/core/home_widget_service.dart';
import 'package:favis_mobile/core/widget_refresh_diagnostics.dart';
import 'package:favis_mobile/features/settings/widget_settings_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeApi api;
  late StoredAuthSession? session;
  late String? family;
  late List<String> stages;
  late List<HomeWidgetPageData> snapshots;
  late bool publishSucceeds;

  WidgetRefreshRunner runner() => WidgetRefreshRunner(
    apiClient: api,
    readSession: () async => session,
    readFamily: () async => family,
    record: (source, stage) async => stages.add('$source:$stage'),
    publish: (id, today, tomorrow) async {
      expect(id, 'family');
      snapshots.addAll([today, tomorrow]);
      return publishSucceeds;
    },
  );

  setUp(() {
    api = _FakeApi();
    session = StoredAuthSession(
      accessToken: 'test-token',
      tokenType: 'Bearer',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
    family = 'family';
    stages = [];
    snapshots = [];
    publishSucceeds = true;
  });

  test(
    'periodic callback fetches both APIs and publishes before recording success',
    () async {
      expect(await runner().run(), isTrue);
      expect(api.calls, ['schedules', 'parking']);
      expect(api.rangeEnd!.difference(api.rangeStart!).inDays, 2);
      expect(api.rangeStart!.hour, 0);
      expect(api.includeHolidays, isFalse);
      expect(snapshots, hasLength(2));
      expect(stages, [
        'periodic:started',
        'periodic:fetching',
        'periodic:publishing',
        'periodic:success',
      ]);
    },
  );

  test(
    'missing credentials are visible and never reported as a successful refresh',
    () async {
      session = null;
      await runner().run();
      expect(api.calls, isEmpty);
      expect(stages.last, 'periodic:login_required');
    },
  );

  test('missing group explains why no API request was sent', () async {
    family = null;
    await runner().run();
    expect(api.calls, isEmpty);
    expect(stages.last, 'periodic:group_required');
  });

  test('another group push does not publish the wrong group', () async {
    await runner().run(source: 'push', changedFamilyId: 'other');
    expect(api.calls, isEmpty);
    expect(stages.last, 'push:other_group');
  });

  test('a session change while fetching discards the response', () async {
    api.afterFetch = () => session = null;
    await runner().run();
    expect(snapshots, isEmpty);
    expect(stages.last, 'periodic:session_changed');
  });

  test(
    'API errors record the status and do not overwrite the cached widget',
    () async {
      api.error = const ApiException(500, {});
      expect(await runner().run(), isFalse);
      expect(snapshots, isEmpty);
      expect(stages.last, 'periodic:api_error_500');
    },
  );

  test('native publication failure cannot become a false success', () async {
    publishSucceeds = false;
    expect(await runner().run(), isFalse);
    expect(stages.last, 'periodic:publish_failed');
  });

  test(
    'foreground and push diagnostics do not replace periodic records',
    () async {
      const channel = MethodChannel('home_widget');
      final values = <String, String>{};
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getWidgetData') return values[call.arguments['id']];
        if (call.method == 'saveWidgetData') {
          values[call.arguments['id'] as String] =
              call.arguments['data'] as String;
        }
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await WidgetRefreshDiagnostics.record('periodic', 'started');
      await WidgetRefreshDiagnostics.record('periodic', 'success');
      final periodic = values['widgetRefresh.periodic'];
      await WidgetRefreshDiagnostics.record('foreground', 'started');
      await WidgetRefreshDiagnostics.record('push', 'success');
      expect(values['widgetRefresh.periodic'], periodic);
      final records = await WidgetRefreshDiagnostics.read();
      expect(records['periodic']?['startedAt'], isNotNull);
      expect(records['periodic']?['successAt'], isNotNull);
      expect(values.toString(), isNot(contains('test-token')));
    },
  );

  testWidgets(
    'widget settings shows pending status and the reason for skipped fetches',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      const channel = MethodChannel('home_widget');
      const native = MethodChannel('checky/widget_refresh');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getWidgetData') {
          return call.arguments['id'] == 'widgetRefresh.periodic'
              ? '{"stage":"login_required","startedAt":"2026-09-16T10:00:00Z"}'
              : null;
        }
        return true;
      });
      messenger.setMockMethodCallHandler(
        native,
        (call) async => {
          'pending': true,
          'backgroundRefresh': 'denied',
          'lowPowerMode': true,
        },
      );
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(native, null);
      });
      await tester.pumpWidget(const CupertinoApp(home: WidgetSettingsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('예약됨 · 시스템 실행 대기'), findsOneWidget);
      expect(find.text('꺼져 있음 · iPhone 설정에서 켜 주세요'), findsOneWidget);
      expect(find.text('로그인이 필요해요. 다시 로그인해 주세요.'), findsOneWidget);
      expect(find.text('지금 갱신'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );
}

class _FakeApi extends ApiClient {
  final calls = <String>[];
  DateTime? rangeStart;
  DateTime? rangeEnd;
  bool? includeHolidays;
  Exception? error;
  void Function()? afterFetch;

  @override
  Future<ScheduleDashboard> getScheduleDashboard(
    String token, {
    required String familyId,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    bool includeHolidays = true,
  }) async {
    calls.add('schedules');
    this.rangeStart = rangeStart;
    this.rangeEnd = rangeEnd;
    this.includeHolidays = includeHolidays;
    if (error != null) throw error!;
    afterFetch?.call();
    return const ScheduleDashboard(
      canManage: true,
      members: [],
      schedules: [],
      educationPrograms: [],
      holidays: [],
    );
  }

  @override
  Future<ParkingDashboard> getParkingDashboard(
    String token, {
    required String familyId,
  }) async {
    calls.add('parking');
    return const ParkingDashboard(
      canManage: true,
      vehicles: [],
      presets: [],
      currentLocations: [],
    );
  }
}
