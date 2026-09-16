import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'api_client.dart';
import 'group_refresh.dart';
import 'home_widget_background_refresh.dart';

@pragma('vm:entry-point')
Future<void> checkyBackgroundMessage(RemoteMessage message) async {
  if (!_refreshMessage(message)) return;
  final familyId = message.data['familyId'];
  if (familyId is! String || familyId.isEmpty) return;
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  await HomeWidgetBackgroundRefresh.refresh(
    changedFamilyId: familyId,
    source: 'push',
  );
}

bool _refreshMessage(RemoteMessage message) =>
    message.data['type'] == 'group_refresh' ||
    message.data['type'] == 'schedule_alert';

class PushNotificationService {
  static Future<void> initializeBackgroundMessages() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return;
    }
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(checkyBackgroundMessage);
    } catch (_) {
      // Local builds may not have Firebase configuration.
    }
  }

  PushNotificationService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  final Map<String, Timer> _refreshTimers = {};
  String? _sessionToken;
  bool _firebaseReady = false;

  Future<void> attachSession(String sessionToken) async {
    _sessionToken = sessionToken;
    final platform = _platformName();
    if (platform == null) return;

    final ready = await _ensureFirebaseReady();
    if (!ready) return;

    FirebaseMessaging.onBackgroundMessage(checkyBackgroundMessage);
    await _messageSubscription?.cancel();
    await _openedSubscription?.cancel();
    _messageSubscription = FirebaseMessaging.onMessage.listen(_handleMessage);
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _handleMessage,
    );

    await _requestPermission();
    await _registerCurrentToken(sessionToken, platform);

    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh
        .listen((token) {
          final activeSession = _sessionToken;
          final activePlatform = _platformName();
          if (activeSession == null || activePlatform == null) return;
          unawaited(_registerToken(activeSession, token, activePlatform));
        });
  }

  Future<void> detachSession() async {
    final activeSession = _sessionToken;
    _sessionToken = null;
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    await _stopMessages();

    if (activeSession == null || _platformName() == null || !_firebaseReady) {
      return;
    }

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        return;
      }
      await _apiClient.deletePushToken(activeSession, token: token);
    } catch (_) {
      // Token cleanup is best effort. Logout/account deletion should not fail here.
    }
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _stopMessages();
  }

  void _handleMessage(RemoteMessage message) {
    if (_sessionToken == null || !_refreshMessage(message)) return;
    final familyId = message.data['familyId'];
    if (familyId is! String || familyId.isEmpty) return;
    _refreshTimers[familyId]?.cancel();
    _refreshTimers[familyId] = Timer(const Duration(milliseconds: 500), () {
      _refreshTimers.remove(familyId);
      if (_sessionToken == null) return;
      GroupRefresh.notify(familyId);
      unawaited(
        HomeWidgetBackgroundRefresh.refresh(
          changedFamilyId: familyId,
          source: 'push',
        ),
      );
    });
  }

  Future<void> _stopMessages() async {
    await _messageSubscription?.cancel();
    await _openedSubscription?.cancel();
    _messageSubscription = null;
    _openedSubscription = null;
    for (final timer in _refreshTimers.values) {
      timer.cancel();
    }
    _refreshTimers.clear();
  }

  Future<bool> _ensureFirebaseReady() async {
    if (_firebaseReady) return true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _firebaseReady = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _requestPermission() async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {}
  }

  Future<void> _registerCurrentToken(
    String sessionToken,
    String platform,
  ) async {
    try {
      await _waitForApnsTokenIfNeeded();
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await _registerToken(sessionToken, token, platform);
    } catch (_) {}
  }

  Future<void> _registerToken(
    String sessionToken,
    String token,
    String platform,
  ) async {
    try {
      await _apiClient.upsertPushToken(
        sessionToken,
        token: token,
        platform: platform,
      );
    } catch (_) {}
  }

  Future<void> _waitForApnsTokenIfNeeded() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    for (var attempt = 0; attempt < 10; attempt += 1) {
      final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
      if (apnsToken != null && apnsToken.isNotEmpty) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  String? _platformName() {
    if (kIsWeb) return null;
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      _ => null,
    };
  }
}
