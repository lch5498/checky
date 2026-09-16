import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

class HomeWidgetPageData {
  const HomeWidgetPageData({
    required this.title,
    required this.weekday,
    required this.day,
    required this.fullDate,
    required this.items,
    required this.moreCount,
    this.parkingItems = const [],
    this.parkingMoreCount = 0,
  });

  final String title;
  final String weekday;
  final String day;
  final String fullDate;
  final List<HomeWidgetScheduleItem> items;
  final int moreCount;
  final List<HomeWidgetParkingItem> parkingItems;
  final int parkingMoreCount;

  Map<String, Object> toMap() => {
    'title': title,
    'weekday': weekday,
    'day': day,
    'fullDate': fullDate,
    'items': items.map((item) => item.toMap()).toList(),
    'moreCount': moreCount,
    'parkingItems': parkingItems.map((item) => item.toMap()).toList(),
    'parkingMoreCount': parkingMoreCount,
  };
}

class HomeWidgetParkingItem {
  const HomeWidgetParkingItem({
    required this.vehicleName,
    required this.location,
  });

  final String vehicleName;
  final String location;

  Map<String, String> toMap() => {
    'vehicleName': vehicleName,
    'location': location,
  };
}

class HomeWidgetScheduleItem {
  const HomeWidgetScheduleItem({
    required this.startsAt,
    required this.endsAt,
    required this.title,
    required this.memberName,
    required this.memberColor,
  });

  final String startsAt;
  final String endsAt;
  final String title;
  final String memberName;
  final String memberColor;

  Map<String, String> toMap() => {
    'startsAt': startsAt,
    'endsAt': endsAt,
    'title': title,
    'memberName': memberName,
    'memberColor': memberColor,
  };
}

/// Shares the compact home briefing with the native Android/iOS widgets.
///
/// Widgets cannot render Flutter directly, so the native implementations read
/// these preformatted values from platform shared storage.
class HomeWidgetService {
  static const appGroupId = 'group.com.family.checky.mobile';
  static const androidProvider =
      'com.family.checky.mobile.CheckyHomeWidgetProvider';
  static const iosWidgetKind = 'CheckyHomeWidget';
  static const _familyIdKey = 'homeWidget.familyId';
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static bool get _isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<bool> update({
    required HomeWidgetPageData schedule,
    required String familyId,
    HomeWidgetPageData? nextSchedule,
  }) async {
    if (!_isSupported) {
      return false;
    }

    try {
      final previousFamilyId = await _storage.read(key: _familyIdKey);
      await _storage.write(key: _familyIdKey, value: familyId);
      await HomeWidget.setAppGroupId(appGroupId);
      await _saveSchedule('schedule', schedule);
      await _saveParking(schedule.parkingItems, schedule.parkingMoreCount);
      await HomeWidget.saveWidgetData<String>(
        'schedule.snapshotDate',
        _dateKey(DateTime.now()),
      );

      if (nextSchedule != null) {
        await _saveSchedule('nextSchedule', nextSchedule);
        await HomeWidget.saveWidgetData<String>(
          'nextSchedule.snapshotDate',
          _dateKey(DateTime.now().add(const Duration(days: 1))),
        );
      } else if (previousFamilyId != familyId) {
        await HomeWidget.saveWidgetData<String?>(
          'nextSchedule.snapshotDate',
          null,
        );
      }

      final updated = await HomeWidget.updateWidget(
        qualifiedAndroidName: androidProvider,
        iOSName: iosWidgetKind,
      );
      if (updated != true) return false;

      if (defaultTargetPlatform == TargetPlatform.android) {
        final nextMidnight = _dateOnly(
          DateTime.now(),
        ).add(const Duration(days: 1));
        await HomeWidget.scheduleWidgetUpdates([
          nextMidnight,
        ], qualifiedAndroidName: androidProvider);
      }
      return true;
    } on MissingPluginException {
      // Native widget support is unavailable on development-only platforms.
      return false;
    } on PlatformException {
      // The in-app home remains available even if a widget refresh fails.
      return false;
    }
  }

  /// Publish freshly loaded parking without refetching or replacing schedules.
  /// Local saves must not depend on a push arriving or the home tab reopening.
  static Future<void> updateParking({
    required String familyId,
    required List<HomeWidgetParkingItem> items,
  }) async {
    if (!_isSupported) return;

    try {
      // A retained screen from another group must not mix its parking with the
      // schedule snapshot belonging to the currently selected widget group.
      if (await readFamilyId() != familyId) return;
      await HomeWidget.setAppGroupId(appGroupId);
      await _saveParking(items, 0);
      await HomeWidget.updateWidget(
        qualifiedAndroidName: androidProvider,
        iOSName: iosWidgetKind,
      );
    } on MissingPluginException {
      // Native widget support is unavailable on development-only platforms.
    } on PlatformException catch (error) {
      // A successful parking save must not become an in-app error.
      debugPrint('Home widget parking update failed: ${error.code}');
    }
  }

  static Future<String?> readFamilyId() {
    return _storage.read(key: _familyIdKey);
  }

  static Future<void> _saveSchedule(
    String prefix,
    HomeWidgetPageData schedule,
  ) async {
    final items = schedule.items.take(5).toList();
    final values = <String, Object?>{
      '$prefix.title': schedule.title,
      '$prefix.weekday': schedule.weekday,
      '$prefix.day': schedule.day,
      '$prefix.fullDate': schedule.fullDate,
      '$prefix.itemCount': items.length,
      '$prefix.moreCount':
          schedule.moreCount + (schedule.items.length - items.length),
    };

    for (var index = 0; index < 5; index++) {
      final item = index < items.length ? items[index] : null;
      values['$prefix.item.$index.startsAt'] = item?.startsAt ?? '';
      values['$prefix.item.$index.endsAt'] = item?.endsAt ?? '';
      values['$prefix.item.$index.title'] = item?.title ?? '';
      values['$prefix.item.$index.memberName'] = item?.memberName ?? '';
      values['$prefix.item.$index.memberColor'] = item?.memberColor ?? 'gray';
    }

    final saved = await Future.wait(
      values.entries.map(
        (entry) => HomeWidget.saveWidgetData<Object?>(entry.key, entry.value),
      ),
    );
    if (saved.any((value) => value != true)) {
      throw PlatformException(code: 'widget_storage_failed');
    }
  }

  static Future<void> _saveParking(
    List<HomeWidgetParkingItem> allItems,
    int moreCount,
  ) async {
    final items = allItems.take(5).toList();
    final values = <String, Object>{
      'parking.itemCount': items.length,
      'parking.moreCount': moreCount + allItems.length - items.length,
      for (var index = 0; index < 5; index++) ...{
        'parking.item.$index.vehicleName': index < items.length
            ? items[index].vehicleName
            : '',
        'parking.item.$index.location': index < items.length
            ? items[index].location
            : '',
      },
    };
    final saved = await Future.wait(
      values.entries.map(
        (entry) => HomeWidget.saveWidgetData<Object>(entry.key, entry.value),
      ),
    );
    if (saved.any((value) => value != true)) {
      throw PlatformException(code: 'widget_storage_failed');
    }
  }

  static String _dateKey(DateTime date) {
    final local = date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  static DateTime _dateOnly(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}
