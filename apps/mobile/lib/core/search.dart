import 'api_client.dart';
import 'coupon.dart';

const searchMinQueryLength = 2;
const searchMaxQueryLength = 100;

/// Normalizes a raw query the same way the server does; empty means "do not search".
String normalizeSearchQuery(String raw) {
  final query = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (query.length < searchMinQueryLength) return '';
  return query.length > searchMaxQueryLength
      ? query.substring(0, searchMaxQueryLength).trim()
      : query;
}

/// Declared in display order: schedules, parking, scraps (posts, comments,
/// coupons), then travel.
enum SearchResultType {
  schedule('schedule', '일정'),
  parking('parking', '주차 위치'),
  scrapPost('scrap_post', '스크랩 글'),
  scrapComment('scrap_comment', '스크랩 댓글'),
  coupon('coupon', '쿠폰'),
  travelTrip('travel_trip', '여행'),
  travelItinerary('travel_itinerary', '여행 일정');

  const SearchResultType(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

class SearchSection<T> {
  const SearchSection({required this.items, required this.hasMore});
  final List<T> items;
  final bool hasMore;

  static SearchSection<T> parse<T>(
    Object? json,
    T Function(Map<String, Object?> item) fromJson,
  ) {
    final section = json as Map<String, Object?>? ?? const {};
    return SearchSection(
      items: (section['items'] as List<Object?>? ?? const [])
          .map((item) => fromJson(item as Map<String, Object?>))
          .toList(),
      hasMore: section['has_more'] as bool? ?? false,
    );
  }
}

class SearchResults {
  const SearchResults({
    required this.query,
    required this.schedules,
    required this.coupons,
    required this.scrapPosts,
    required this.scrapComments,
    required this.travelTrips,
    required this.travelItineraries,
    required this.parkingRecords,
  });

  final String query;
  final SearchSection<SearchScheduleResult> schedules;
  final SearchSection<Coupon> coupons;
  final SearchSection<SearchScrapPostResult> scrapPosts;
  final SearchSection<SearchScrapCommentResult> scrapComments;
  final SearchSection<TravelTrip> travelTrips;
  final SearchSection<SearchTravelItineraryResult> travelItineraries;
  final SearchSection<SearchParkingResult> parkingRecords;

  bool get isEmpty =>
      schedules.items.isEmpty &&
      coupons.items.isEmpty &&
      scrapPosts.items.isEmpty &&
      scrapComments.items.isEmpty &&
      travelTrips.items.isEmpty &&
      travelItineraries.items.isEmpty &&
      parkingRecords.items.isEmpty;

  factory SearchResults.fromJson(Map<String, Object?> json) {
    final results = json['results'] as Map<String, Object?>? ?? const {};
    return SearchResults(
      query: json['query'] as String? ?? '',
      schedules: SearchSection.parse(
        results['schedule'],
        SearchScheduleResult.fromJson,
      ),
      coupons: SearchSection.parse(results['coupon'], Coupon.fromJson),
      scrapPosts: SearchSection.parse(
        results['scrap_post'],
        SearchScrapPostResult.fromJson,
      ),
      scrapComments: SearchSection.parse(
        results['scrap_comment'],
        SearchScrapCommentResult.fromJson,
      ),
      travelTrips: SearchSection.parse(
        results['travel_trip'],
        TravelTrip.fromJson,
      ),
      travelItineraries: SearchSection.parse(
        results['travel_itinerary'],
        SearchTravelItineraryResult.fromJson,
      ),
      parkingRecords: SearchSection.parse(
        results['parking'],
        SearchParkingResult.fromJson,
      ),
    );
  }
}

class SearchScheduleResult {
  const SearchScheduleResult({
    required this.id,
    required this.title,
    required this.content,
    required this.startsAt,
    required this.endsAt,
    required this.isAllDay,
    required this.memberNickname,
  });

  final String id;
  final String title;
  final String? content;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isAllDay;
  final String? memberNickname;

  factory SearchScheduleResult.fromJson(Map<String, Object?> json) =>
      SearchScheduleResult(
        id: json['id'] as String,
        title: json['title'] as String,
        content: json['content'] as String?,
        startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
        endsAt: DateTime.parse(json['ends_at'] as String).toLocal(),
        isAllDay: json['is_all_day'] as bool? ?? false,
        memberNickname: json['member_nickname'] as String?,
      );
}

class SearchScrapPostResult {
  const SearchScrapPostResult({
    required this.id,
    required this.channelId,
    required this.channelName,
    required this.content,
    required this.linkTitle,
    required this.authorNickname,
    required this.createdAt,
  });

  final String id;
  final String channelId;
  final String channelName;
  final String content;
  final String? linkTitle;
  final String authorNickname;
  final DateTime createdAt;

  /// Link title when saved, otherwise the first non-empty line of the body.
  String get headline {
    final title = linkTitle?.trim();
    if (title != null && title.isNotEmpty) return title;
    for (final line in content.split('\n')) {
      if (line.trim().isNotEmpty) return line.trim();
    }
    return content.trim();
  }

  factory SearchScrapPostResult.fromJson(Map<String, Object?> json) =>
      SearchScrapPostResult(
        id: json['id'] as String,
        channelId: json['channel_id'] as String,
        channelName: json['channel_name'] as String,
        content: json['content'] as String? ?? '',
        linkTitle: json['link_title'] as String?,
        authorNickname: json['author_nickname'] as String? ?? '알 수 없음',
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );
}

class SearchScrapCommentResult {
  const SearchScrapCommentResult({
    required this.id,
    required this.postId,
    required this.channelId,
    required this.channelName,
    required this.content,
    required this.authorNickname,
    required this.createdAt,
  });

  final String id;
  final String postId;
  final String channelId;
  final String channelName;
  final String content;
  final String authorNickname;
  final DateTime createdAt;

  factory SearchScrapCommentResult.fromJson(Map<String, Object?> json) =>
      SearchScrapCommentResult(
        id: json['id'] as String,
        postId: json['post_id'] as String,
        channelId: json['channel_id'] as String,
        channelName: json['channel_name'] as String,
        content: json['content'] as String? ?? '',
        authorNickname: json['author_nickname'] as String? ?? '알 수 없음',
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );
}

class SearchTravelItineraryResult {
  const SearchTravelItineraryResult({
    required this.id,
    required this.title,
    required this.content,
    required this.itineraryDate,
    required this.trip,
  });

  final String id;
  final String title;
  final String? content;
  final DateTime itineraryDate;
  final TravelTrip trip;

  factory SearchTravelItineraryResult.fromJson(Map<String, Object?> json) =>
      SearchTravelItineraryResult(
        id: json['id'] as String,
        title: json['title'] as String,
        content: json['content'] as String?,
        itineraryDate: DateTime.parse(json['itinerary_date'] as String),
        trip: TravelTrip.fromJson(json['trip'] as Map<String, Object?>),
      );
}

class SearchParkingResult {
  const SearchParkingResult({
    required this.id,
    required this.vehicleId,
    required this.vehicleNickname,
    required this.plateNumber,
    required this.locationText,
    required this.parkedAt,
  });

  final String id;
  final String vehicleId;
  final String vehicleNickname;
  final String plateNumber;
  final String locationText;
  final DateTime parkedAt;

  factory SearchParkingResult.fromJson(Map<String, Object?> json) =>
      SearchParkingResult(
        id: json['id'] as String,
        vehicleId: json['vehicle_id'] as String,
        vehicleNickname: json['vehicle_nickname'] as String? ?? '차량',
        plateNumber: json['plate_number'] as String? ?? '',
        locationText: json['location_text'] as String? ?? '',
        parkedAt: DateTime.parse(json['parked_at'] as String).toLocal(),
      );
}
