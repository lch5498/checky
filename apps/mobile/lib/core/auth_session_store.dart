import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';
import 'api_config.dart';

class AuthSessionStore {
  AuthSessionStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    ),
  }) : _storage = storage;

  static const _accessTokenKey = 'auth.accessToken';
  static const _expiresAtKey = 'auth.expiresAt';
  static const _tokenTypeKey = 'auth.tokenType';
  static const _shareSessionChannel = MethodChannel('checky/share_session');

  final FlutterSecureStorage _storage;

  Future<void> save(AuthResponse auth) async {
    final expiresAt = DateTime.now().add(Duration(seconds: auth.expiresIn));

    await Future.wait([
      _storage.write(key: _accessTokenKey, value: auth.accessToken),
      _storage.write(key: _tokenTypeKey, value: auth.tokenType),
      _storage.write(key: _expiresAtKey, value: expiresAt.toIso8601String()),
    ]);
    await _syncShareSession(
      accessToken: auth.accessToken,
      tokenType: auth.tokenType,
      expiresAt: expiresAt,
    );
  }

  Future<StoredAuthSession?> read() async {
    final values = await Future.wait([
      _storage.read(key: _accessTokenKey),
      _storage.read(key: _tokenTypeKey),
      _storage.read(key: _expiresAtKey),
    ]);

    final accessToken = values[0];
    final expiresAtValue = values[2];

    if (accessToken == null || expiresAtValue == null) {
      return null;
    }

    final expiresAt = DateTime.tryParse(expiresAtValue);

    if (expiresAt == null) {
      await clear();
      return null;
    }

    final session = StoredAuthSession(
      accessToken: accessToken,
      tokenType: values[1] ?? 'Bearer',
      expiresAt: expiresAt,
    );
    await _syncShareSession(
      accessToken: session.accessToken,
      tokenType: session.tokenType,
      expiresAt: session.expiresAt,
    );
    return session;
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _tokenTypeKey),
      _storage.delete(key: _expiresAtKey),
    ]);
    await _clearShareSession();
  }

  Future<void> _syncShareSession({
    required String accessToken,
    required String tokenType,
    required DateTime expiresAt,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    try {
      await _shareSessionChannel.invokeMethod<void>('sync', {
        'accessToken': accessToken,
        'tokenType': tokenType,
        'expiresAt': expiresAt.toIso8601String(),
        'apiBaseUrl': ApiConfig.baseUrl,
      });
    } on MissingPluginException {
      // Share extensions are unavailable on non-iOS test hosts.
    } on PlatformException {
      // Login must remain usable if the optional share extension is unavailable.
    }
  }

  Future<void> _clearShareSession() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    try {
      await _shareSessionChannel.invokeMethod<void>('clear');
    } on MissingPluginException {
      // Share extensions are unavailable on non-iOS test hosts.
    } on PlatformException {
      // The app's own session has already been removed above.
    }
  }
}

class StoredAuthSession {
  const StoredAuthSession({
    required this.accessToken,
    required this.tokenType,
    required this.expiresAt,
  });

  final String accessToken;
  final String tokenType;
  final DateTime expiresAt;

  bool get isExpired => remainingSeconds <= 0;

  int get remainingSeconds => expiresAt.difference(DateTime.now()).inSeconds;
}
