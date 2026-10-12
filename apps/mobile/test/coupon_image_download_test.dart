import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:favis_mobile/core/api_client.dart';

void main() {
  test(
    'downloads the private coupon image with session authorization',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      String? authorization;
      String? path;
      server.listen((request) async {
        authorization = request.headers.value(HttpHeaders.authorizationHeader);
        path = request.uri.path;
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add([137, 80, 78, 71]);
        await request.response.close();
      });

      final image = await ApiClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
      ).downloadCouponImage('session', 'family', 'coupon');
      expect(authorization, 'Bearer session');
      expect(path, '/api/mobile/families/family/coupons/coupon/image');
      expect(image.mimeType, 'image/png');
      expect(image.bytes, [137, 80, 78, 71]);
    },
  );

  test('does not treat a failed image response as an image', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = 403;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'forbidden'}));
      await request.response.close();
    });

    await expectLater(
      ApiClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
      ).downloadCouponImage('session', 'family', 'coupon'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
    );
  });
}
