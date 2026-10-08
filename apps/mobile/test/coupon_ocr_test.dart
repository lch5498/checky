import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:favis_mobile/core/api_client.dart';
import 'package:favis_mobile/core/coupon_ocr.dart';
import 'package:favis_mobile/features/scrap/coupon_screen.dart';

List<CouponOcrLine> lines(List<String> values) => [
  for (var i = 0; i < values.length; i++)
    CouponOcrLine(values[i], top: i * 0.05, height: 0.02),
];

void main() {
  test('extracts explicitly labeled name and expiry only', () {
    final result = parseCouponText(
      lines([
        '쿠폰 정보',
        '상품명: 아이스 아메리카노',
        '발급일 2026.10.01',
        '유효기간',
        '2026.10.01 ~ 2026.12.31',
        '사용처: 체키카페',
        '유의사항',
        '일부 매장 사용 불가',
        '쿠폰번호 1234567890',
      ]),
    );
    expect(result.title, '아이스 아메리카노');
    expect(result.expiresOn, DateTime(2026, 12, 31));
  });
  test(
    'supports Korean, compact and wrapped range dates; validates calendar date',
    () {
      for (final date in ['2028년 2월 29일', '2028/02/29', '20280229']) {
        expect(
          parseCouponText(lines(['사용기한 $date'])).expiresOn,
          DateTime(2028, 2, 29),
        );
      }
      expect(
        parseCouponText(lines(['유효기간 2026.10.01 ~', '2026.12.31'])).expiresOn,
        DateTime(2026, 12, 31),
      );
      expect(parseCouponText(lines(['유효기간 2026.02.29'])).expiresOn, isNull);
      expect(parseCouponText(lines(['발급일 2026.12.31'])).expiresOn, isNull);
      expect(
        parseCouponText(lines(['유효기간', '발급일 2026.12.31'])).expiresOn,
        isNull,
      );
      expect(parseCouponText(lines(['유효기간: 구매 후 30일'])).expiresOn, isNull);
      expect(
        parseCouponText(lines(['유효기간 2026.11.01', '만료일 2026.12.31'])).expiresOn,
        isNull,
      );
    },
  );
  test(
    'unlabeled name favors prominent product text over chrome and fine print',
    () {
      final result = parseCouponText([
        const CouponOcrLine('선물하기', top: 0.1, height: 0.1),
        const CouponOcrLine('카페', top: 0.2, height: 0.03),
        const CouponOcrLine('아메리카노 Tall', top: 0.4, height: 0.06),
        const CouponOcrLine('1234 5678 9012', top: 0.6, height: 0.08),
        const CouponOcrLine('유효기간 2026.12.31', top: 0.7, height: 0.06),
      ]);
      expect(result.title, '아메리카노 Tall');
      expect(result.expiresOn, DateTime(2026, 12, 31));
    },
  );
  test('empty OCR and usage notes do not produce suggestions', () {
    expect(parseCouponText([]).isEmpty, true);
    expect(parseCouponText(lines(['유의사항'])).isEmpty, true);
  });

  testWidgets(
    'OCR suggestions preserve name typed while recognition is pending',
    (tester) async {
      final completer = Completer<CouponSuggestions>();
      await _showEditor(tester, FakeOcr(completer.future));
      await tester.enterText(find.byType(CupertinoTextField).first, '내가 정한 이름');
      completer.complete(
        CouponSuggestions(title: '자동 이름', expiresOn: DateTime(2026, 12, 31)),
      );
      await tester.pumpAndSettle();
      final fields = tester
          .widgetList<CupertinoTextField>(find.byType(CupertinoTextField))
          .toList();
      expect(fields[0].controller!.text, '내가 정한 이름');
      expect(fields[1].controller!.text, isEmpty);
      expect(fields[2].controller!.text, isEmpty);
      expect(find.text('2026-12-31'), findsOneWidget);
      expect(find.textContaining('꼭 확인'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('다른 이미지 선택')).dy,
        lessThan(tester.getTopLeft(find.text('쿠폰 이름')).dy),
      );
      expect(
        tester.getTopLeft(find.text('쿠폰 이름')).dy,
        lessThan(tester.getTopLeft(find.text('만료일')).dy),
      );
      expect(
        tester.getTopLeft(find.text('만료일')).dy,
        lessThan(tester.getTopLeft(find.text('쿠폰 번호 (선택)')).dy),
      );
      expect(
        tester.getTopLeft(find.text('쿠폰 번호 (선택)')).dy,
        lessThan(tester.getTopLeft(find.text('메모')).dy),
      );
      expect(find.textContaining('QR·바코드가 선명한'), findsNothing);
      expect(find.textContaining('그룹당 최대 100장'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'unsupported OCR preserves selected image and manual registration',
    (tester) async {
      final completer = Completer<CouponSuggestions>();
      await _showEditor(tester, FakeOcr(completer.future));
      completer.completeError(PlatformException(code: 'ocr_unsupported'));
      await tester.pumpAndSettle();
      expect(find.textContaining('자동 입력을 지원하지'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      await tester.enterText(find.byType(CupertinoTextField).first, '수동 쿠폰');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('manual input cancels late suggestions', (tester) async {
    final completer = Completer<CouponSuggestions>();
    await _showEditor(tester, FakeOcr(completer.future));
    await tester.ensureVisible(find.text('직접 입력'));
    await tester.tap(find.text('직접 입력'));
    completer.complete(const CouponSuggestions(title: '늦게 도착한 값'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CupertinoTextField>(find.byType(CupertinoTextField).first)
          .controller!
          .text,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
  });
}

Future<void> _showEditor(WidgetTester tester, CouponOcr ocr) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final image = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j5e0AAAAASUVORK5CYII=',
  );
  await tester.pumpWidget(
    CupertinoApp(
      home: CouponEditorScreen(
        family: const AppFamily(
          id: 'group',
          name: '우리 그룹',
          createdAt: '',
          updatedAt: '',
        ),
        sessionToken: 'test',
        recoveredImage: XFile.fromData(image, name: 'coupon.png'),
        ocr: ocr,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

class FakeOcr extends CouponOcr {
  FakeOcr(this.result);
  final Future<CouponSuggestions> result;
  @override
  Future<CouponSuggestions> recognize(Uint8List bytes) => result;
}
