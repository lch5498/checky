import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:favis_mobile/core/api_client.dart';
import 'package:favis_mobile/core/coupon.dart';
import 'package:favis_mobile/core/group_refresh.dart';
import 'package:favis_mobile/design_system/app_font_preset.dart';
import 'package:favis_mobile/design_system/app_theme.dart';
import 'package:favis_mobile/design_system/app_theme_preset.dart';
import 'package:favis_mobile/features/home/expiring_coupons_section.dart';
import 'package:favis_mobile/features/scrap/coupon_screen.dart';

const _family = AppFamily(
  id: 'family',
  name: '우리 그룹',
  createdAt: '',
  updatedAt: '',
);
const _otherFamily = AppFamily(
  id: 'other-family',
  name: '다른 그룹',
  createdAt: '',
  updatedAt: '',
);
final _today = DateTime(2026, 10, 21, 23, 59);

Coupon _coupon(String id, {int? days = 1, bool used = false}) => Coupon(
  id: id,
  title: id,
  memo: '',
  expiresOn: days == null
      ? null
      : DateTime(_today.year, _today.month, _today.day + days),
  usedAt: used ? _today : null,
  createdAt: _today,
  version: 1,
  canManage: true,
);

Widget _host(
  _CouponsApi api, {
  AppFamily family = _family,
  int refresh = 0,
  DateTime Function()? now,
  AppThemePreset preset = AppThemePreset.mint,
  Brightness brightness = Brightness.light,
  AppFontPreset font = AppFontPreset.system,
  double textScale = 1,
}) => CupertinoApp(
  theme: AppTheme.cupertinoTheme(
    brightness,
    preset.colors(brightness),
    font: font,
  ),
  builder: (context, child) => material.Theme(
    data: AppTheme.theme(brightness, preset, font: font),
    child: MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
  ),
  home: CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('홈')),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ExpiringCouponsSection(
          family: family,
          sessionToken: 'test-session',
          refreshToken: refresh,
          apiClient: api,
          now: now ?? () => _today,
        ),
      ),
    ),
  ),
);

void main() {
  test(
    'home eligibility is inclusive D-Day through D-7, excludes used/expired/undated, and sorts by expiry',
    () {
      final items = [
        _coupon('D7', days: 7),
        _coupon('used', used: true),
        _coupon('D1'),
        _coupon('D8', days: 8),
        _coupon('expired', days: -1),
        _coupon('today', days: 0),
        _coupon('undated', days: null),
      ];
      expect(expiringCoupons(items, _today).map((coupon) => coupon.id), [
        'today',
        'D1',
        'D7',
      ]);
      expect(items.first.id, 'D7');
    },
  );

  testWidgets('shows siren, dates and countdown in expiry order', (
    tester,
  ) async {
    final api = _CouponsApi([
      _coupon('나중 쿠폰', days: 7),
      _coupon('오늘 쿠폰', days: 0),
      _coupon('내일 쿠폰'),
    ]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    expect(find.text('🚨'), findsOneWidget);
    expect(find.text('만료 예정 쿠폰'), findsOneWidget);
    expect(find.text('D-Day'), findsOneWidget);
    expect(find.text('D-1'), findsOneWidget);
    expect(find.text('D-7'), findsOneWidget);
    expect(find.text('2026.10.21 만료'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('오늘 쿠폰')).dy,
      lessThan(tester.getTopLeft(find.text('내일 쿠폰')).dy),
    );
    expect(
      tester.getTopLeft(find.text('내일 쿠폰')).dy,
      lessThan(tester.getTopLeft(find.text('나중 쿠폰')).dy),
    );
    expect(api.requestedFamilies, ['family']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'no eligible coupons hides the entire section without empty-state padding',
    (tester) async {
      final api = _CouponsApi([
        _coupon('used', used: true),
        _coupon('old', days: -1),
        _coupon('later', days: 8),
        _coupon('no-date', days: null),
      ]);
      await tester.pumpWidget(_host(api));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-expiring-coupons')), findsNothing);
      expect(find.text('만료 예정 쿠폰'), findsNothing);
      expect(tester.getSize(find.byType(ExpiringCouponsSection)).height, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'group event and home refresh reload coupons without another group leaking in',
    (tester) async {
      final api = _CouponsApi([_coupon('첫 쿠폰')]);
      await tester.pumpWidget(_host(api));
      await tester.pumpAndSettle();
      api.items = [];
      GroupRefresh.notify('other-family');
      await tester.pumpAndSettle();
      expect(find.text('첫 쿠폰'), findsOneWidget);
      GroupRefresh.notify('family');
      await tester.pumpAndSettle();
      expect(find.text('만료 예정 쿠폰'), findsNothing);
      api.items = [_coupon('새 쿠폰')];
      await tester.pumpWidget(_host(api, refresh: 1));
      await tester.pumpAndSettle();
      expect(find.text('새 쿠폰'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('old group response cannot replace a new group briefing', (
    tester,
  ) async {
    final pending = Completer<List<Coupon>>();
    final api = _CouponsApi([])
      ..onLoad = (family) => family == 'family'
          ? pending.future
          : Future.value([_coupon('다른 그룹 쿠폰')]);
    await tester.pumpWidget(_host(api));
    await tester.pump();
    await tester.pumpWidget(_host(api, family: _otherFamily));
    await tester.pumpAndSettle();
    pending.complete([_coupon('이전 그룹 쿠폰')]);
    await tester.pumpAndSettle();
    expect(find.text('다른 그룹 쿠폰'), findsOneWidget);
    expect(find.text('이전 그룹 쿠폰'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'network failures hide an unloaded section and preserve a same-group result',
    (tester) async {
      final api = _CouponsApi([])..fail = true;
      await tester.pumpWidget(_host(api));
      await tester.pumpAndSettle();
      expect(find.text('만료 예정 쿠폰'), findsNothing);
      api.fail = false;
      api.items = [_coupon('기존 쿠폰')];
      await tester.pumpWidget(_host(api, refresh: 1));
      await tester.pumpAndSettle();
      api.fail = true;
      await tester.pumpWidget(_host(api, refresh: 2));
      await tester.pumpAndSettle();
      expect(find.text('기존 쿠폰'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'midnight removes expired coupons and includes new D-7 coupons without a network call',
    (tester) async {
      var now = _today;
      final api = _CouponsApi([
        _coupon('오늘까지', days: 0),
        _coupon('내일부터 D7', days: 8),
      ]);
      await tester.pumpWidget(_host(api, now: () => now));
      await tester.pumpAndSettle();
      expect(find.text('오늘까지'), findsOneWidget);
      expect(find.text('내일부터 D7'), findsNothing);
      now = DateTime(2026, 10, 22);
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('오늘까지'), findsNothing);
      expect(find.text('내일부터 D7'), findsOneWidget);
      expect(api.requestedFamilies.length, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'coupon opens detail and marking used removes it from home on return',
    (tester) async {
      final api = _CouponsApi([_coupon('커피 쿠폰')]);
      await tester.pumpWidget(_host(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('커피 쿠폰'));
      await tester.pumpAndSettle();
      expect(find.byType(CouponDetailScreen), findsOneWidget);
      await tester.ensureVisible(find.text('사용 완료'));
      await tester.tap(find.text('사용 완료'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(api.usedIds, ['커피 쿠폰']);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('만료 예정 쿠폰'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final preset in AppThemePreset.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '${preset.name}/${brightness.name} supports narrow screens, large text and inherited fonts',
        (tester) async {
          tester.view.physicalSize = const Size(320, 680);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final api = _CouponsApi([
            _coupon('아주 긴 한글 쿠폰 제목 English 123 길게 표시해도 넘치지 않아요', days: 7),
          ]);
          await tester.pumpWidget(
            _host(
              api,
              preset: preset,
              brightness: brightness,
              textScale: 1.3,
              font: AppFontPreset
                  .values[preset.index % AppFontPreset.values.length],
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('만료 예정 쿠폰'), findsOneWidget);
          expect(find.text('D-7'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}

class _CouponsApi extends ApiClient {
  _CouponsApi(this.items);
  List<Coupon> items;
  final requestedFamilies = <String>[];
  final usedIds = <String>[];
  Future<List<Coupon>> Function(String family)? onLoad;
  bool fail = false;

  @override
  Future<List<Coupon>> getCoupons(String token, String familyId) async {
    expect(token, 'test-session');
    requestedFamilies.add(familyId);
    if (fail) throw const ApiConnectionException('offline');
    return onLoad == null ? List.of(items) : onLoad!(familyId);
  }

  @override
  Future<Coupon> getCoupon(String token, String familyId, String id) async =>
      items.firstWhere((coupon) => coupon.id == id);

  @override
  Future<Coupon> setCouponUsed(
    String token,
    String familyId,
    Coupon coupon,
    bool used,
  ) async {
    usedIds.add(coupon.id);
    final updated = _coupon(coupon.id, used: used);
    items = [
      for (final item in items)
        if (item.id == coupon.id) updated else item,
    ];
    return updated;
  }
}
