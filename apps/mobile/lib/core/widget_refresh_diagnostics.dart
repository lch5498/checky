import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'home_widget_service.dart';

/// Only execution stages/timestamps are stored, never credentials or user data.
class WidgetRefreshDiagnostics {
  static const sources = [
    'schedule',
    'periodic',
    'push',
    'foreground',
    'manual',
  ];

  static Future<void> record(String source, String stage) async {
    try {
      await HomeWidget.setAppGroupId(HomeWidgetService.appGroupId);
      final previous = await _read(source);
      final now = DateTime.now().toUtc().toIso8601String();
      await HomeWidget.saveWidgetData<String>(
        'widgetRefresh.$source',
        jsonEncode({
          ...previous,
          'stage': stage,
          'at': now,
          if (stage == 'started') 'startedAt': now,
          if (stage == 'success') 'successAt': now,
        }),
      );
    } catch (_) {
      // Diagnostics must never stop a refresh on an unsupported platform.
      debugPrint('Widget refresh [$source]: $stage');
    }
  }

  static Future<Map<String, dynamic>> _read(String source) async {
    final value = await HomeWidget.getWidgetData<String>(
      'widgetRefresh.$source',
    );
    return value == null ? {} : jsonDecode(value) as Map<String, dynamic>;
  }

  static Future<Map<String, Map<String, dynamic>>> read() async {
    await HomeWidget.setAppGroupId(HomeWidgetService.appGroupId);
    return {for (final source in sources) source: await _read(source)};
  }
}
