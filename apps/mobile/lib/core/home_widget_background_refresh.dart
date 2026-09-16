import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';

import 'api_client.dart';
import 'auth_session_store.dart';
import 'home_widget_service.dart';
import 'widget_refresh_diagnostics.dart';

const _homeWidgetRefreshTask = 'com.family.checky.mobile.homeWidgetRefresh';

@pragma('vm:entry-point')
void iosWidgetRefreshDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('checky/widget_worker');
  channel.setMethodCallHandler((call) async {
    if (call.method != 'refresh') throw MissingPluginException();
    return HomeWidgetBackgroundRefresh.refresh(source: 'periodic');
  });
  // Native invokes refresh only after this handler has been installed.
  unawaited(channel.invokeMethod<void>('ready'));
}

@pragma('vm:entry-point')
void homeWidgetCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    if (task != _homeWidgetRefreshTask &&
        task != Workmanager.iOSBackgroundTask) {
      return true;
    }

    return HomeWidgetBackgroundRefresh.refresh(source: 'periodic');
  });
}

class HomeWidgetBackgroundRefresh {
  const HomeWidgetBackgroundRefresh._();
  static const _iosScheduler = MethodChannel('checky/widget_refresh');

  static Future<void> initialize() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return;
    }

    try {
      if (Platform.isIOS) {
        // Native submission reports errors and preserves an existing pending
        // request instead of moving its earliest date on every app launch.
        final handle = PluginUtilities.getCallbackHandle(
          iosWidgetRefreshDispatcher,
        );
        if (handle == null) throw StateError('missing_callback');
        final scheduled = await _iosScheduler.invokeMethod<bool>('schedule', {
          'callbackHandle': handle.toRawHandle(),
        });
        if (scheduled != true) throw StateError('schedule_failed');
      } else {
        await Workmanager().initialize(homeWidgetCallbackDispatcher);
        await Workmanager().registerPeriodicTask(
          _homeWidgetRefreshTask,
          _homeWidgetRefreshTask,
          frequency: const Duration(minutes: 15),
          initialDelay: const Duration(minutes: 15),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
          constraints: Constraints(networkType: NetworkType.connected),
        );
      }
      await WidgetRefreshDiagnostics.record('schedule', 'success');
    } catch (error, stackTrace) {
      await WidgetRefreshDiagnostics.record('schedule', 'schedule_failed');
      debugPrint('Home widget background refresh registration failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<Map<String, dynamic>> schedulingStatus() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return Map<String, dynamic>.from(
        await _iosScheduler.invokeMapMethod<String, dynamic>('status') ?? {},
      );
    }
    return {
      'pending': await Workmanager().isScheduledByUniqueName(
        _homeWidgetRefreshTask,
      ),
    };
  }

  static Future<bool> refresh({
    String? changedFamilyId,
    String source = 'foreground',
  }) {
    return WidgetRefreshRunner().run(
      changedFamilyId: changedFamilyId,
      source: source,
    );
  }
}

/// Injectable dependencies allow the background path to be tested without a
/// device scheduler, real credentials, push delivery or a live API.
class WidgetRefreshRunner {
  WidgetRefreshRunner({
    ApiClient? apiClient,
    Future<StoredAuthSession?> Function()? readSession,
    Future<String?> Function()? readFamily,
    Future<bool> Function(String, HomeWidgetPageData, HomeWidgetPageData)?
    publish,
    Future<void> Function(String, String)? record,
  }) : _apiClient = apiClient ?? ApiClient(),
       _readSession = readSession ?? AuthSessionStore().read,
       _readFamily = readFamily ?? HomeWidgetService.readFamilyId,
       _publish =
           publish ??
           ((family, today, tomorrow) => HomeWidgetService.update(
             familyId: family,
             schedule: today,
             nextSchedule: tomorrow,
           )),
       _record = record ?? WidgetRefreshDiagnostics.record;

  final ApiClient _apiClient;
  final Future<StoredAuthSession?> Function() _readSession;
  final Future<String?> Function() _readFamily;
  final Future<bool> Function(String, HomeWidgetPageData, HomeWidgetPageData)
  _publish;
  final Future<void> Function(String, String) _record;

  Future<bool> run({
    String? changedFamilyId,
    String source = 'periodic',
  }) async {
    await _record(source, 'started');
    try {
      final session = await _readSession();
      final familyId = await _readFamily();
      if (session == null || session.isExpired) {
        await _record(source, 'login_required');
        return true; // Do not retry revoked credentials; this is not a success.
      }
      if (familyId == null) {
        await _record(source, 'group_required');
        return true;
      }
      if (changedFamilyId != null && changedFamilyId != familyId) {
        await _record(source, 'other_group');
        return true;
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final dayAfterTomorrow = today.add(const Duration(days: 2));
      await _record(source, 'fetching');
      final results = await Future.wait<dynamic>([
        _apiClient.getScheduleDashboard(
          session.accessToken,
          familyId: familyId,
          rangeStart: today,
          rangeEnd: dayAfterTomorrow,
          includeHolidays: false,
        ),
        _apiClient.getParkingDashboard(session.accessToken, familyId: familyId),
      ]);
      final dashboard = results[0] as ScheduleDashboard;
      final parking = results[1] as ParkingDashboard;
      final memberColors = _memberColors(dashboard.members);
      final parkingItems = _parkingItems(parking);

      // Discard a response from a session/group that changed during the fetch.
      final activeSession = await _readSession();
      if (activeSession?.accessToken != session.accessToken ||
          await _readFamily() != familyId) {
        await _record(source, 'session_changed');
        return true;
      }

      await _record(source, 'publishing');
      final published = await _publish(
        familyId,
        _pageData(
          date: today,
          schedules: dashboard.schedules,
          memberColors: memberColors,
          parkingItems: parkingItems,
        ),
        _pageData(
          date: tomorrow,
          schedules: dashboard.schedules,
          memberColors: memberColors,
          parkingItems: parkingItems,
        ),
      );
      await _record(source, published ? 'success' : 'publish_failed');
      return published;
    } on ApiException catch (error) {
      await _record(source, 'api_error_${error.statusCode}');
      // An expired or revoked session cannot recover by retrying in background.
      return error.statusCode == 401;
    } catch (error, stackTrace) {
      await _record(source, 'refresh_failed');
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
