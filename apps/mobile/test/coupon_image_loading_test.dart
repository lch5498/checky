import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:favis_mobile/core/api_client.dart';
import 'package:favis_mobile/core/coupon.dart';
import 'package:favis_mobile/core/coupon_image_saver.dart';
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
  testWidgets('edit screen loads the saved coupon image with its session', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: CouponEditorScreen(
          family: _family,
          sessionToken: 'test',
          existing: _coupon,
        ),
      ),
    );
    final image = tester.widget<Image>(
      find.byKey(const ValueKey('coupon-editor-existing-image')),
    );
    final source = image.image as NetworkImage;
    expect(source.url, contains('/families/group/coupons/coupon/image'));
    expect(source.headers?['Authorization'], 'Bearer test');
    expect(find.text('쿠폰 이미지'), findsOneWidget);
    expect(find.text('이미지 업로드'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

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

  testWidgets('saves coupon image and confirms completion', (tester) async {
    final api = _SavingApi();
    final saver = _RecordingSaver();
    await tester.pumpWidget(
      CupertinoApp(
        home: CouponDetailScreen(
          family: _family,
          sessionToken: 'test',
          coupon: _coupon,
          apiClient: api,
          imageSaver: saver,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('이미지 저장'));
    await tester.pumpAndSettle();
    expect(api.downloadedWith, ('test', 'group', 'coupon'));
    expect(saver.saved?.mimeType, 'image/png');
    expect(find.text('사진 앱에 저장했어요.'), findsOneWidget);
  });

  testWidgets('explains denied photo permission', (tester) async {
    final saver = _RecordingSaver()
      ..failure = PlatformException(code: 'permission_denied');
    await tester.pumpWidget(
      CupertinoApp(
        home: CouponDetailScreen(
          family: _family,
          sessionToken: 'test',
          coupon: _coupon,
          apiClient: _SavingApi(),
          imageSaver: saver,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('이미지 저장'));
    await tester.pumpAndSettle();
    expect(find.text('사진 저장 권한이 없어요. 기기 설정에서 허용해 주세요.'), findsOneWidget);
  });
}

class _DetailApi extends ApiClient {
  _DetailApi(this.response);
  final Future<Coupon> response;
  @override
  Future<Coupon> getCoupon(String token, String familyId, String id) =>
      response;
}

class _SavingApi extends _DetailApi {
  _SavingApi() : super(Future.value(_coupon));
  (String, String, String)? downloadedWith;

  @override
  Future<CouponImageData> downloadCouponImage(
    String token,
    String familyId,
    String couponId,
  ) async {
    downloadedWith = (token, familyId, couponId);
    return CouponImageData(Uint8List.fromList([1, 2, 3]), 'image/png');
  }
}

class _RecordingSaver extends CouponImageSaver {
  CouponImageData? saved;
  Object? failure;

  @override
  Future<void> save(CouponImageData image) async {
    saved = image;
    if (failure != null) throw failure!;
  }
}
