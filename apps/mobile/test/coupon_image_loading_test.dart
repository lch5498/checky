import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:favis_mobile/core/api_client.dart';
import 'package:favis_mobile/core/coupon.dart';
import 'package:favis_mobile/features/scrap/coupon_screen.dart';

final _coupon = Coupon(
  id: 'coupon',
  title: '커피',
  memo: '',
  expiresOn: null,
  usedAt: null,
  createdAt: DateTime(2026),
  version: 1,
  canManage: false,
);
const _family = AppFamily(
  id: 'group',
  name: '그룹',
  createdAt: '',
  updatedAt: '',
);
const _loading = ValueKey('coupon-image-loading');

void main() {
  testWidgets(
    'shows spinner immediately while awaiting coupon API and stops on failure',
    (tester) async {
      final response = Completer<Coupon>();
      await tester.pumpWidget(
        CupertinoApp(
          home: CouponDetailScreen(
            family: _family,
            sessionToken: 'test',
            coupon: _coupon,
            apiClient: _DetailApi(response.future),
          ),
        ),
      );
      expect(find.byKey(_loading), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(_loading), findsOneWidget);
      response.completeError(const ApiConnectionException('offline'));
      await tester.pumpAndSettle();
      expect(find.byKey(_loading), findsNothing);
      expect(find.text('다시 불러오기'), findsOneWidget);
    },
  );

  testWidgets(
    'image waits for first decoded frame, including time before download chunks',
    (tester) async {
      await tester.pumpWidget(
        CupertinoApp(
          home: CouponDetailScreen(
            family: _family,
            sessionToken: 'test',
            coupon: _coupon,
            apiClient: _DetailApi(Future.value(_coupon)),
          ),
        ),
      );
      await tester.pump();
      final image = tester.widget<Image>(find.byType(Image));
      final builder = image.frameBuilder!;
      const pixels = SizedBox(key: ValueKey('decoded-image'));
      Future<void> render(int? frame, bool synchronous) => tester.pumpWidget(
        CupertinoApp(
          home: Builder(
            builder: (context) => builder(context, pixels, frame, synchronous),
          ),
        ),
      );
      await render(null, false);
      expect(find.byKey(_loading), findsOneWidget);
      expect(find.byKey(const ValueKey('decoded-image')), findsNothing);
      await render(0, false);
      expect(find.byKey(_loading), findsNothing);
      expect(find.byKey(const ValueKey('decoded-image')), findsOneWidget);
      await render(null, true);
      expect(find.byKey(_loading), findsNothing);
    },
  );
}

class _DetailApi extends ApiClient {
  _DetailApi(this.response);
  final Future<Coupon> response;
  @override
  Future<Coupon> getCoupon(String token, String familyId, String id) =>
      response;
}
