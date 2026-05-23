import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';

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

  final FlutterSecureStorage _storage;

  Future<void> save(AuthResponse auth) async {
    final expiresAt = DateTime.now().add(Duration(seconds: auth.expiresIn));

    await Future.wait([
      _storage.write(key: _accessTokenKey, value: auth.accessToken),
      _storage.write(key: _tokenTypeKey, value: auth.tokenType),
      _storage.write(key: _expiresAtKey, value: expiresAt.toIso8601String()),
    ]);
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

    return StoredAuthSession(
      accessToken: accessToken,
      tokenType: values[1] ?? 'Bearer',
      expiresAt: expiresAt,
    );
  }

  Future<void> clear() {
    return Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _tokenTypeKey),
      _storage.delete(key: _expiresAtKey),
    ]);
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
