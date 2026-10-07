import 'package:flutter_test/flutter_test.dart';
import 'package:favis_mobile/core/incoming_share_service.dart';

void main() {
  test('parses a native incoming share payload', () {
    final payload = IncomingSharePayload.fromPlatform({
      'id': ' share-1 ',
      'text': ' https://example.com ',
    });

    expect(payload?.id, 'share-1');
    expect(payload?.text, 'https://example.com');
  });

  test('ignores missing or empty incoming share values', () {
    expect(IncomingSharePayload.fromPlatform(null), isNull);
    expect(IncomingSharePayload.fromPlatform({'id': '1'}), isNull);
    expect(
      IncomingSharePayload.fromPlatform({'id': '1', 'text': '   '}),
      isNull,
    );
  });
}
