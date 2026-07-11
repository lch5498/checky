import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ScrapReadState {
  ScrapReadState._();

  static const _storage = FlutterSecureStorage();

  static String _key(String familyId, String channelId) {
    return 'scrap.channelReadAt.$familyId.$channelId';
  }

  static Future<DateTime?> readAt({
    required String familyId,
    required String channelId,
  }) async {
    final value = await _storage.read(key: _key(familyId, channelId));

    if (value == null) {
      return null;
    }

    return DateTime.tryParse(value);
  }

  static Future<void> markRead({
    required String familyId,
    required String channelId,
  }) async {
    await _storage.write(
      key: _key(familyId, channelId),
      value: DateTime.now().toUtc().toIso8601String(),
    );
  }
}
