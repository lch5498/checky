import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:favis_mobile/core/api_client.dart';
import 'package:favis_mobile/core/coupon.dart';
import 'package:favis_mobile/features/scrap/coupon_screen.dart';

Coupon coupon(
  String id, {
  String? expiry,
  bool used = false,
  String? usedByName,
  String created = '2026-10-01',
}) => Coupon(
  id: id,
  title: id,
  memo: '',
  expiresOn: expiry == null ? null : DateTime.parse(expiry),
  usedAt: used ? DateTime(2026, 10, 1) : null,
  usedByName: usedByName,
  createdAt: DateTime.parse(created),
  version: 1,
  canManage: true,
);

void main() {
  final now = DateTime(2026, 10, 7, 23, 59);
  test('completion attribution parses API name and falls back safely', () {
    final json = <String, Object?>{
      'id': 'id',
      'title': '커피',
      'memo': '',
      'expires_on': null,
      'used_at': '2026-10-08T00:00:00Z',
      'used_by_name': '민수',
      'created_at': '2026-10-01',
      'version': 1,
      'can_manage': false,
    };
    expect(Coupon.fromJson(json).completionLabel, '사용 완료: 민수');
    expect(
      Coupon.fromJson({...json, 'used_by_name': null}).completionLabel,
      '사용 완료: 알 수 없는 구성원',
    );
    expect(Coupon.fromJson({...json, 'used_at': null}).completionLabel, isNull);
  });
  test('expiry remains usable through its whole calendar day', () {
    final item = coupon('today', expiry: '2026-10-07');
    expect(item.isExpired(now), false);
    expect(item.isExpired(DateTime(2026, 10, 8)), true);
  });
  test('expiry sorting puts undated last and breaks ties by newest', () {
    final items = [
      coupon('undated'),
      coupon('later', expiry: '2026-11-01'),
      coupon('older', expiry: '2026-10-07'),
      coupon('newer', expiry: '2026-10-07', created: '2026-10-06'),
    ];
    expect(
      visibleCoupons(
        items,
        CouponFilter.available,
        CouponSort.expiry,
        now,
      ).map((c) => c.id),
      ['newer', 'older', 'later', 'undated'],
    );
    expect(items.first.id, 'undated'); // Sorting never mutates server state.
  });
  test('used and expired filters are exclusive; latest ignores expiry', () {
    final items = [
      coupon('expired', expiry: '2026-10-06'),
      coupon('used', expiry: '2026-10-01', used: true),
      coupon('today', expiry: '2026-10-07'),
      coupon('no-expiry', created: '2026-10-07'),
    ];
    expect(
      visibleCoupons(
        items,
        CouponFilter.available,
        CouponSort.newest,
        now,
      ).map((c) => c.id),
      ['no-expiry', 'today'],
    );
    expect(
      visibleCoupons(
        items,
        CouponFilter.used,
        CouponSort.expiry,
        now,
      ).map((c) => c.id),
      ['used'],
    );
    expect(
      visibleCoupons(
        items,
        CouponFilter.expired,
        CouponSort.expiry,
        now,
      ).map((c) => c.id),
      ['expired'],
    );
    expect(
      visibleCoupons(items, CouponFilter.all, CouponSort.expiry, now),
      hasLength(4),
    );
  });

  test(
    'coupon API sends bearer auth, bytes, dates and optimistic version',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final bodies = <Map<String, Object?>>[];
      final methods = <String>[];
      final subscription = server.listen((request) async {
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer test-session',
        );
        methods.add(request.method);
        bodies.add(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, Object?>,
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'id': 'coupon',
            'title': '커피',
            'memo': '',
            'expires_on': '2026-10-07',
            'used_at': null,
            'created_at': '2026-10-01T00:00:00Z',
            'version': 2,
            'can_manage': true,
          }),
        );
        await request.response.close();
      });
      try {
        await HttpOverrides.runWithHttpOverrides(() async {
          final api = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
          final saved = await api.saveCoupon(
            'test-session',
            'group',
            title: '커피',
            memo: '',
            expiresOn: DateTime(2026, 10, 7),
            imageBytes: [1, 2, 3],
          );
          await api.setCouponUsed('test-session', 'group', saved, true);
          await api.deleteCoupon('test-session', 'group', saved);
          expect(methods, ['POST', 'PATCH', 'DELETE']);
          expect(bodies[0]['imageBase64'], 'AQID');
          expect(bodies[0]['expiresOn'], '2026-10-07');
          expect(bodies[1], {'version': 2, 'used': true});
          expect(bodies[2], {'version': 2});
        }, _RealHttpOverrides());
      } finally {
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );

  testWidgets('coupon filters and sorting work in narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final today = DateTime.now();
    final data = [
      coupon('기한 없음'),
      coupon('오늘 쿠폰', expiry: couponDate(today)),
      coupon('사용한 쿠폰', used: true, usedByName: '민수'),
    ];
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: SafeArea(
            child: CouponContent(
              family: const AppFamily(
                id: 'group',
                name: '우리 그룹',
                createdAt: '',
                updatedAt: '',
              ),
              sessionToken: 'test',
              apiClient: FakeCouponApi(data),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('오늘 쿠폰'), findsOneWidget);
    expect(find.text('사용한 쿠폰'), findsNothing);
    expect(
      tester.getTopLeft(find.text('오늘 쿠폰')).dy,
      lessThan(tester.getTopLeft(find.text('기한 없음')).dy),
    );
    await tester.tap(find.text('사용 완료').first);
    await tester.pumpAndSettle();
    expect(find.text('사용한 쿠폰'), findsOneWidget);
    expect(find.text('사용 완료: 민수'), findsOneWidget);
    expect(find.text('오늘 쿠폰'), findsNothing);
    await tester.tap(find.text('만료일순 ▾'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('최신 등록순'));
    await tester.pumpAndSettle();
    expect(find.text('최신순 ▾'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); // Dispose midnight timer.
  });
}

class FakeCouponApi extends ApiClient {
  FakeCouponApi(this.items);
  final List<Coupon> items;
  @override
  Future<List<Coupon>> getCoupons(String token, String familyId) async => items;
}

class _RealHttpOverrides extends HttpOverrides {}
