import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'api_client.dart';
import 'auth_session_store.dart';
import 'home_widget_service.dart';

const _homeWidgetRefreshTask = 'com.family.checky.mobile.homeWidgetRefresh';

@pragma('vm:entry-point')
void homeWidgetCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    if (task != _homeWidgetRefreshTask &&
        task != Workmanager.iOSBackgroundTask) {
      return true;
    }

    return HomeWidgetBackgroundRefresh.refresh();
  });
}

class HomeWidgetBackgroundRefresh {
  const HomeWidgetBackgroundRefresh._();

  static Future<void> initialize() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return;
    }

    try {
      await Workmanager().initialize(homeWidgetCallbackDispatcher);
      await Workmanager().registerPeriodicTask(
        _homeWidgetRefreshTask,
        _homeWidgetRefreshTask,
        frequency: const Duration(minutes: 15),
        initialDelay: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (error, stackTrace) {
      debugPrint('Home widget background refresh registration failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<bool> refresh({String? changedFamilyId}) async {
    try {
      final session = await AuthSessionStore().read();
      final familyId = await HomeWidgetService.readFamilyId();
      if (session == null || session.isExpired || familyId == null) {
        return true;
      }
      if (changedFamilyId != null && changedFamilyId != familyId) return true;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final dayAfterTomorrow = today.add(const Duration(days: 2));
      final apiClient = ApiClient();
      final results = await Future.wait<dynamic>([
        apiClient.getScheduleDashboard(
          session.accessToken,
          familyId: familyId,
          rangeStart: today,
          rangeEnd: dayAfterTomorrow,
          includeHolidays: false,
        ),
        apiClient.getParkingDashboard(session.accessToken, familyId: familyId),
      ]);
      final dashboard = results[0] as ScheduleDashboard;
      final parking = results[1] as ParkingDashboard;
      final memberColors = _memberColors(dashboard.members);
      final parkingItems = _parkingItems(parking);

      // Discard a response from a session/group that changed during the fetch.
      final activeSession = await AuthSessionStore().read();
      if (activeSession?.accessToken != session.accessToken ||
          await HomeWidgetService.readFamilyId() != familyId) {
        return true;
      }

      await HomeWidgetService.update(
        familyId: familyId,
        schedule: _pageData(
          date: today,
          schedules: dashboard.schedules,
          memberColors: memberColors,
          parkingItems: parkingItems,
        ),
        nextSchedule: _pageData(
          date: tomorrow,
          schedules: dashboard.schedules,
          memberColors: memberColors,
          parkingItems: parkingItems,
        ),
      );
      return true;
    } on ApiException catch (error) {
      // An expired or revoked session cannot recover by retrying in background.
      return error.statusCode == 401;
    } catch (error, stackTrace) {
      debugPrint('Home widget background refresh failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  static HomeWidgetPageData _pageData({
    required DateTime date,
    required List<AppSchedule> schedules,
    required Map<String, String> memberColors,
    required List<HomeWidgetParkingItem> parkingItems,
  }) {
    final dayEnd = date.add(const Duration(days: 1));
    final daySchedules =
        schedules
            .where(
              (schedule) =>
                  schedule.startsAt.isBefore(dayEnd) &&
                  schedule.endsAt.isAfter(date),
            )
            .toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final items = daySchedules.take(5).map((schedule) {
      return HomeWidgetScheduleItem(
        startsAt: schedule.isAllDay ? '종일' : _timeText(schedule.startsAt),
        endsAt: schedule.isAllDay ? '' : _timeText(schedule.endsAt),
        title: schedule.title,
        memberName: schedule.memberNickname,
        memberColor: memberColors[schedule.familyMemberId] ?? 'gray',
      );
    }).toList();

    return HomeWidgetPageData(
      title: '체키 오늘 일정',
      weekday: _weekday(date),
      day: date.day.toString(),
      fullDate: '${date.month}월 ${date.day}일 ${_weekday(date)}',
      items: items,
      moreCount: daySchedules.length - items.length,
      parkingItems: parkingItems,
    );
  }

  static Map<String, String> _memberColors(List<FamilyMember> members) {
    const colors = <String>[
      'red',
      'blue',
      'green',
      'orange',
      'purple',
      'pink',
      'teal',
      'yellow',
      'indigo',
      'mint',
      'gray',
    ];
    return {
      for (var index = 0; index < members.length; index++)
        members[index].id:
            members[index].color ?? colors[index % colors.length],
    };
  }

  static List<HomeWidgetParkingItem> _parkingItems(ParkingDashboard dashboard) {
    final vehicleNames = {
      for (final vehicle in dashboard.vehicles) vehicle.id: vehicle.nickname,
    };
    return dashboard.currentLocations.map((record) {
      return HomeWidgetParkingItem(
        vehicleName: vehicleNames[record.vehicleId] ?? '차량',
        location: record.locationText,
      );
    }).toList();
  }

  static String _timeText(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static String _weekday(DateTime date) {
    const labels = <String>['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
    return labels[date.weekday - 1];
  }
}
