import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:favis_mobile/core/api_client.dart';
import 'package:favis_mobile/core/search.dart';
import 'package:favis_mobile/design_system/app_theme.dart';
import 'package:favis_mobile/design_system/app_theme_preset.dart';
import 'package:favis_mobile/features/search/search_screen.dart';

const _family = AppFamily(
  id: 'family',
  name: '우리 그룹',
  createdAt: '',
  updatedAt: '',
);
final _now = DateTime(2026, 11, 14, 10);

Map<String, Object?> _section(
  List<Map<String, Object?>> items, {
  bool hasMore = false,
}) => {'items': items, 'has_more': hasMore};

Map<String, Object?> _response(
  String query, {
  List<Map<String, Object?>> schedules = const [],
  List<Map<String, Object?>> coupons = const [],
  List<Map<String, Object?>> scrapPosts = const [],
  List<Map<String, Object?>> scrapComments = const [],
  List<Map<String, Object?>> trips = const [],
  List<Map<String, Object?>> itineraries = const [],
  List<Map<String, Object?>> parking = const [],
  bool scheduleHasMore = false,
}) => {
  'query': query,
  'results': {
    'schedule': _section(schedules, hasMore: scheduleHasMore),
    'coupon': _section(coupons),
    'scrap_post': _section(scrapPosts),
    'scrap_comment': _section(scrapComments),
    'travel_trip': _section(trips),
    'travel_itinerary': _section(itineraries),
    'parking': _section(parking),
  },
};

Map<String, Object?> _schedule(String title) => {
  'id': 'schedule-$title',
  'title': title,
  'content': null,
  'starts_at': '2026-11-20T06:00:00.000Z',
  'ends_at': '2026-11-20T07:00:00.000Z',
  'is_all_day': false,
  'member_nickname': '민준',
};

Map<String, Object?> _coupon(String title) => {
  'id': 'coupon-$title',
  'title': title,
  'memo': '',
  'coupon_number': '',
  'expires_on': '2026-11-20',
  'used_at': null,
  'created_at': '2026-11-01T00:00:00.000Z',
  'version': 1,
  'can_manage': true,
};

Map<String, Object?> _post(String content, {String? linkTitle}) => {
  'id': 'post-$content',
  'channel_id': 'channel',
  'channel_name': '맛집',
  'content': content,
  'link_title': linkTitle,
  'author_nickname': '엄마',
  'created_at': '2026-11-10T03:00:00.000Z',
};

Map<String, Object?> _trip(String title) => {
  'id': 'trip-$title',
  'family_id': 'family',
  'title': title,
  'starts_on': '2026-12-01',
  'ends_on': '2026-12-05',
  'created_at': '2026-11-01T00:00:00.000Z',
  'updated_at': '2026-11-01T00:00:00.000Z',
};

Map<String, Object?> _parking(String location) => {
  'id': 'parking-$location',
  'vehicle_id': 'vehicle',
  'vehicle_nickname': '아빠차',
  'plate_number': '12가 3456',
  'location_text': location,
  'parked_at': '2026-11-13T09:20:00.000Z',
};

class _SearchApi extends ApiClient {
  final queries = <String>[];
  Map<String, Object?> Function(String query)? respond;
  Completer<Map<String, Object?>>? pending;
  bool fail = false;

  @override
  Future<SearchResults> searchFamily(
    String sessionToken, {
    required String familyId,
    required String query,
    DateTime? scheduleAnchor,
  }) async {
    expect(sessionToken, 'test-session');
    expect(familyId, 'family');
    expect(scheduleAnchor, DateTime(2026, 11, 14, 23, 59, 59, 999));
    queries.add(query);
    if (fail) throw const ApiConnectionException('offline');
    final pending = this.pending;
    if (pending != null) return SearchResults.fromJson(await pending.future);
    return SearchResults.fromJson(respond?.call(query) ?? _response(query));
  }
}

Widget _host(_SearchApi api, {VoidCallback? onOpenParkingTab}) {
  const preset = AppThemePreset.mint;
  const brightness = Brightness.light;
  return CupertinoApp(
    theme: AppTheme.cupertinoTheme(brightness, preset.colors(brightness)),
    builder: (context, child) =>
        material.Theme(data: AppTheme.theme(brightness, preset), child: child!),
    home: SearchScreen(
      family: _family,
      sessionToken: 'test-session',
      apiClient: api,
      onOpenParkingTab: onOpenParkingTab,
      debounce: const Duration(milliseconds: 300),
      now: () => _now,
    ),
  );
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('search-field')), text);
  await tester.pump();
}

void main() {
  group('normalizeSearchQuery', () {
    test('trims, collapses whitespace and rejects short queries', () {
      expect(normalizeSearchQuery('  치과   예약 '), '치과 예약');
      expect(normalizeSearchQuery('치'), '');
      expect(normalizeSearchQuery(' 치 '), '');
      expect(normalizeSearchQuery('치과'), '치과');
    });

    test('caps the query length', () {
      final long = List.filled(60, '가나').join();
      expect(normalizeSearchQuery(long).length, searchMaxQueryLength);
    });
  });

  test('SearchResults parses every section and reports emptiness', () {
    final parsed = SearchResults.fromJson(
      _response(
        '치과',
        schedules: [_schedule('치과')],
        coupons: [_coupon('치과 쿠폰')],
        scrapPosts: [_post('치과 추천', linkTitle: '강남 치과')],
        trips: [_trip('치과 여행')],
        itineraries: [
          {
            'id': 'itinerary',
            'trip_id': 'trip-치과 여행',
            'title': '치과 들르기',
            'content': null,
            'itinerary_date': '2026-12-02',
            'trip': _trip('치과 여행'),
          },
        ],
        parking: [_parking('지하 2층 치과 앞')],
        scheduleHasMore: true,
      ),
    );
    expect(parsed.isEmpty, isFalse);
    expect(parsed.schedules.hasMore, isTrue);
    expect(parsed.schedules.items.single.memberNickname, '민준');
    expect(parsed.scrapPosts.items.single.headline, '강남 치과');
    expect(parsed.travelItineraries.items.single.trip.title, '치과 여행');
    expect(parsed.parkingRecords.items.single.vehicleNickname, '아빠차');
    expect(parsed.parkingRecords.items.single.plateNumber, '12가 3456');
    expect(SearchResults.fromJson(_response('없음')).isEmpty, isTrue);
  });

  test('scrap post headline falls back to the first non-empty body line', () {
    final post = SearchScrapPostResult.fromJson(_post('\n  \n둘째 줄\n셋째 줄'));
    expect(post.headline, '둘째 줄');
  });

  testWidgets('debounces typing and shows grouped results with counts', (
    tester,
  ) async {
    final api = _SearchApi()
      ..respond = (query) => _response(
        query,
        schedules: [_schedule('치과 예약')],
        coupons: [_coupon('치과 할인')],
        scrapPosts: [_post('치과 후기')],
        parking: [_parking('지하 3층 치과 쪽')],
        scheduleHasMore: true,
      );
    await tester.pumpWidget(_host(api));
    await _type(tester, '치');
    await _type(tester, '치과');
    await tester.pump(const Duration(milliseconds: 200));
    expect(api.queries, isEmpty);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(api.queries, ['치과']);
    expect(find.text('일정'), findsOneWidget);
    expect(find.text('1+'), findsOneWidget);
    expect(find.text('치과 예약'), findsOneWidget);
    expect(find.text('2026.11.20 15:00 · 민준'), findsOneWidget);
    expect(find.text('쿠폰'), findsOneWidget);
    expect(find.text('2026.11.20 만료 · 사용 가능'), findsOneWidget);
    expect(find.text('스크랩 글'), findsOneWidget);
    expect(find.text('맛집 · 엄마 · 2026.11.10'), findsOneWidget);
    expect(find.text('주차 위치'), findsOneWidget);
    expect(find.text('아빠차 · 12가 3456 · 2026.11.13 18:20'), findsOneWidget);
    expect(find.text('스크랩 댓글'), findsNothing);
    expect(find.text('여행'), findsNothing);
    expect(find.text('여행 일정'), findsNothing);
  });

  testWidgets(
    'sections follow schedule, parking, scrap, coupon, travel order',
    (tester) async {
      final api = _SearchApi()
        ..respond = (query) => _response(
          query,
          schedules: [_schedule('치과 예약')],
          coupons: [_coupon('치과 할인')],
          scrapPosts: [_post('치과 후기')],
          scrapComments: [
            {
              'id': 'comment',
              'post_id': 'post-치과 후기',
              'channel_id': 'channel',
              'channel_name': '맛집',
              'content': '치과 댓글',
              'author_nickname': '아빠',
              'created_at': '2026-11-10T04:00:00.000Z',
            },
          ],
          trips: [_trip('치과 여행')],
          itineraries: [
            {
              'id': 'itinerary',
              'trip_id': 'trip-치과 여행',
              'title': '치과 들르기',
              'content': null,
              'itinerary_date': '2026-12-02',
              'trip': _trip('치과 여행'),
            },
          ],
          parking: [_parking('지하 3층 치과 쪽')],
        );
      // Tall viewport so the lazy list builds every section at once.
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_host(api));
      await _type(tester, '치과');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      double top(String apiValue) => tester
          .getTopLeft(find.byKey(ValueKey('search-section-$apiValue')))
          .dy;
      final tops = [
        for (final type in SearchResultType.values) top(type.apiValue),
      ];
      expect(tops, orderedEquals([...tops]..sort()));
      expect(SearchResultType.values.map((type) => type.apiValue), [
        'schedule',
        'parking',
        'scrap_post',
        'scrap_comment',
        'coupon',
        'travel_trip',
        'travel_itinerary',
      ]);
    },
  );

  testWidgets('short queries show guidance without calling the server', (
    tester,
  ) async {
    final api = _SearchApi();
    await tester.pumpWidget(_host(api));
    await _type(tester, '치');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('두 글자 이상 입력해 주세요.'), findsOneWidget);
    expect(api.queries, isEmpty);

    await _type(tester, '');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('두 글자 이상 입력해 주세요.'), findsNothing);
    expect(api.queries, isEmpty);
  });

  testWidgets('submit searches immediately and empty results show a notice', (
    tester,
  ) async {
    final api = _SearchApi();
    await tester.pumpWidget(_host(api));
    await _type(tester, '없는 항목');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(api.queries, ['없는 항목']);
    expect(find.byKey(const ValueKey('search-empty')), findsOneWidget);
    expect(find.text("'없는 항목'에 맞는 항목이 없어요."), findsOneWidget);
  });

  testWidgets('a slow older response never replaces newer results', (
    tester,
  ) async {
    final api = _SearchApi();
    final slow = Completer<Map<String, Object?>>();
    api.pending = slow;
    await tester.pumpWidget(_host(api));
    await _type(tester, '치과');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    api.pending = null;
    api.respond = (query) => _response(query, coupons: [_coupon('최신 쿠폰')]);
    await _type(tester, '쿠폰');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('최신 쿠폰'), findsOneWidget);

    slow.complete(_response('치과', schedules: [_schedule('오래된 일정')]));
    await tester.pumpAndSettle();
    expect(find.text('최신 쿠폰'), findsOneWidget);
    expect(find.text('오래된 일정'), findsNothing);
    expect(api.queries, ['치과', '쿠폰']);
  });

  testWidgets('network failure keeps the last results and offers retry', (
    tester,
  ) async {
    final api = _SearchApi()
      ..respond = (query) => _response(query, coupons: [_coupon('기존 쿠폰')]);
    await tester.pumpWidget(_host(api));
    await _type(tester, '쿠폰');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('기존 쿠폰'), findsOneWidget);

    api.fail = true;
    await _type(tester, '쿠폰 추가');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('offline'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.text('기존 쿠폰'), findsOneWidget);

    api.fail = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('offline'), findsNothing);
    expect(api.queries, ['쿠폰', '쿠폰 추가', '쿠폰 추가']);
  });

  testWidgets('parking results pop the screen and open the parking tab', (
    tester,
  ) async {
    var opened = 0;
    final api = _SearchApi()
      ..respond = (query) => _response(query, parking: [_parking('지하 2층 B구역')]);
    await tester.pumpWidget(_host(api, onOpenParkingTab: () => opened++));
    await _type(tester, '지하');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.text('지하 2층 B구역'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });
}
