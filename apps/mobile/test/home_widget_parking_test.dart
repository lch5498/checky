import 'package:favis_mobile/core/home_widget_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const widgetChannel = MethodChannel('home_widget');
  const storageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Map<String, Object?> values;
  late List<Map<String, Object?>> published;
  late String? storedFamily;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    storedFamily = 'family';
    values = {
      'schedule.item.0.title': '오늘 일정',
      'nextSchedule.item.0.title': '내일 일정',
      'parking.itemCount': 2,
      'parking.item.0.location': '이전 위치',
      'parking.item.1.vehicleName': '삭제한 차량',
      'parking.item.1.location': '지하 1층',
    };
    published = [];
    messenger.setMockMethodCallHandler(storageChannel, (call) async {
      if (call.method == 'read' &&
          call.arguments['key'] == 'homeWidget.familyId') {
        return storedFamily;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(widgetChannel, (call) async {
      if (call.method == 'saveWidgetData') {
        values[call.arguments['id'] as String] = call.arguments['data'];
      } else if (call.method == 'updateWidget') {
        expect(
          call.arguments['qualifiedAndroidName'],
          HomeWidgetService.androidProvider,
        );
        expect(call.arguments['ios'], HomeWidgetService.iosWidgetKind);
        published.add(Map.of(values));
      }
      return true;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(widgetChannel, null);
    messenger.setMockMethodCallHandler(storageChannel, null);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '$platform publishes new parking before reload, preserving schedules',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        await HomeWidgetService.updateParking(
          familyId: 'family',
          items: const [
            HomeWidgetParkingItem(
              vehicleName: '새 차량 이름',
              location: '지하 3층 B12',
            ),
          ],
        );

        expect(published, hasLength(1));
        final snapshot = published.single;
        expect(snapshot['parking.itemCount'], 1);
        expect(snapshot['parking.item.0.vehicleName'], '새 차량 이름');
        expect(snapshot['parking.item.0.location'], '지하 3층 B12');
        expect(snapshot['parking.item.1.vehicleName'], '');
        expect(snapshot['parking.item.1.location'], '');
        expect(snapshot['schedule.item.0.title'], '오늘 일정');
        expect(snapshot['nextSchedule.item.0.title'], '내일 일정');
      },
    );
  }

  test(
    'deleting all parked vehicles clears parking but preserves schedules',
    () async {
      await HomeWidgetService.updateParking(
        familyId: 'family',
        items: const [],
      );
      expect(published.single['parking.itemCount'], 0);
      expect(published.single['parking.moreCount'], 0);
      expect(published.single['parking.item.0.location'], '');
      expect(published.single['schedule.item.0.title'], '오늘 일정');
    },
  );

  test(
    'full snapshot updates still publish parking with today and tomorrow',
    () async {
      const page = HomeWidgetPageData(
        title: '오늘 일정',
        weekday: '수요일',
        day: '16',
        fullDate: '9월 16일 수요일',
        items: [],
        moreCount: 0,
        parkingItems: [
          HomeWidgetParkingItem(vehicleName: '내 차', location: '아파트 B2'),
        ],
        parkingMoreCount: 2,
      );
      await HomeWidgetService.update(
        familyId: 'family',
        schedule: page,
        nextSchedule: page,
      );
      expect(published.single['parking.itemCount'], 1);
      expect(published.single['parking.moreCount'], 2);
      expect(published.single['parking.item.0.location'], '아파트 B2');
      expect(published.single['schedule.itemCount'], 0);
      expect(published.single['nextSchedule.itemCount'], 0);
    },
  );

  test(
    'parking overflow keeps five rows and the correct remaining count',
    () async {
      await HomeWidgetService.updateParking(
        familyId: 'family',
        items: List.generate(
          7,
          (index) => HomeWidgetParkingItem(
            vehicleName: '차량 $index',
            location: '$index층',
          ),
        ),
      );
      expect(published.single['parking.itemCount'], 5);
      expect(published.single['parking.moreCount'], 2);
      expect(published.single.containsKey('parking.item.5.location'), isFalse);
    },
  );

  test('another group cannot overwrite the selected group widget', () async {
    await HomeWidgetService.updateParking(
      familyId: 'another-family',
      items: const [],
    );
    expect(published, isEmpty);
    expect(values['parking.itemCount'], 2);
    storedFamily = null;
    await HomeWidgetService.updateParking(familyId: 'family', items: const []);
    expect(published, isEmpty);
  });

  test(
    'native refresh failure does not fail an already saved parking change',
    () async {
      messenger.setMockMethodCallHandler(widgetChannel, (call) async {
        throw PlatformException(code: 'widget_unavailable');
      });
      await expectLater(
        HomeWidgetService.updateParking(familyId: 'family', items: const []),
        completes,
      );
    },
  );
}
