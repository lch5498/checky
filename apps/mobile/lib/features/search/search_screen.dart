import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../core/api_client.dart';
import '../../core/coupon.dart';
import '../../core/search.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_radius.dart';
import '../../design_system/app_spacing.dart';
import '../../design_system/app_typography.dart';
import '../schedule/schedule_screen.dart';
import '../scrap/coupon_screen.dart';
import '../scrap/scrap_screen.dart';
import '../travel/travel_screen.dart';

/// Searches the selected group only. Group switching stays on the home screen.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.family,
    required this.sessionToken,
    this.apiClient,
    this.onOpenParkingTab,
    this.debounce = const Duration(milliseconds: 300),
    this.now = DateTime.now,
  });

  final AppFamily family;
  final String sessionToken;
  final ApiClient? apiClient;
  final VoidCallback? onOpenParkingTab;
  final Duration debounce;
  final DateTime Function() now;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final _api = widget.apiClient ?? ApiClient();
  final _controller = TextEditingController();
  Timer? _debounce;
  int _requestToken = 0;
  SearchResults? _results;
  bool _searching = false;
  bool _tooShort = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    if (text.trim().isEmpty) {
      _requestToken++;
      setState(() {
        _results = null;
        _error = null;
        _searching = false;
        _tooShort = false;
      });
      return;
    }
    _debounce = Timer(widget.debounce, () => _search(text));
  }

  void _onSubmitted(String text) {
    _debounce?.cancel();
    _search(text);
  }

  Future<void> _search(String raw) async {
    final query = normalizeSearchQuery(raw);
    final token = ++_requestToken;
    if (query.isEmpty) {
      setState(() {
        _tooShort = raw.trim().isNotEmpty;
        _searching = false;
        _error = null;
      });
      return;
    }
    if (_results?.query == query && _error == null && !_searching) {
      return;
    }
    setState(() {
      _tooShort = false;
      _searching = true;
      _error = null;
    });
    try {
      final results = await _api.searchFamily(
        widget.sessionToken,
        familyId: widget.family.id,
        query: query,
        scheduleAnchor: _endOfToday(widget.now()),
      );
      // A slower response for an older query must not replace newer results.
      if (!mounted || token != _requestToken) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (error) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _error = error is ApiConnectionException
            ? error.message
            : '검색에 실패했습니다.';
        _searching = false;
      });
    }
  }

  /// Schedules are ordered around the end of the user's local day: the next
  /// month, today and the past come first so far-future entries stay at the end.
  static DateTime _endOfToday(DateTime now) =>
      DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

  Future<void> _refreshAfterReturn() async {
    final query = _results?.query;
    if (!mounted || query == null || query.isEmpty) return;
    _results = null;
    await _search(query);
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(
      context,
    ).push<void>(CupertinoPageRoute<void>(builder: (_) => screen));
    await _refreshAfterReturn();
  }

  Future<void> _openSchedule(SearchScheduleResult schedule) => _push(
    ScheduleScreen(
      family: widget.family,
      families: [widget.family],
      sessionToken: widget.sessionToken,
      refreshToken: 0,
      todayRequestToken: 0,
      initialDate: schedule.startsAt,
      onSelectFamily: (_) async {},
    ),
  );

  Future<void> _openCoupon(Coupon coupon) => _push(
    CouponDetailScreen(
      family: widget.family,
      sessionToken: widget.sessionToken,
      coupon: coupon,
      apiClient: _api,
    ),
  );

  Future<void> _openScrap({
    required String channelId,
    required String channelName,
    required String postId,
  }) {
    final now = widget.now();
    return _push(
      ScrapChannelScreen(
        family: widget.family,
        sessionToken: widget.sessionToken,
        channel: ScrapChannel(
          id: channelId,
          familyId: widget.family.id,
          name: channelName,
          sortOrder: null,
          authorNickname: '알 수 없음',
          canEdit: false,
          canDelete: false,
          hasRecentPosts: false,
          createdAt: now,
          updatedAt: now,
        ),
        initialPostId: postId,
      ),
    );
  }

  Future<void> _openTravel(TravelTrip trip, {String? itineraryId}) => _push(
    TravelDetailScreen(
      family: widget.family,
      sessionToken: widget.sessionToken,
      trip: trip,
      initialItineraryId: itineraryId,
    ),
  );

  void _openParking() {
    final onOpenParkingTab = widget.onOpenParkingTab;
    if (onOpenParkingTab == null) return;
    Navigator.of(context).pop();
    onOpenParkingTab();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final results = _results;
    final now = widget.now();

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: const CupertinoNavigationBar(middle: Text('검색')),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.md,
                AppSpacing.page,
                AppSpacing.sm,
              ),
              child: CupertinoSearchTextField(
                key: const ValueKey('search-field'),
                controller: _controller,
                autofocus: true,
                placeholder: '일정, 쿠폰, 스크랩, 여행, 주차 검색',
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.textPrimary,
                ),
                onChanged: _onChanged,
                onSubmitted: _onSubmitted,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: Text(
                '${widget.family.name}에서 검색',
                style: AppTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.md,
                  AppSpacing.page,
                  AppSpacing.xxl,
                ),
                children: [
                  if (_searching)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Center(child: CupertinoActivityIndicator()),
                    ),
                  if (_tooShort)
                    _Notice(text: '두 글자 이상 입력해 주세요.')
                  else if (_error != null)
                    _Notice(
                      text: _error!,
                      actionLabel: '다시 시도',
                      onAction: () => _search(_controller.text),
                    ),
                  if (results != null && results.isEmpty && !_searching)
                    _Notice(
                      key: const ValueKey('search-empty'),
                      text: "'${results.query}'에 맞는 항목이 없어요.",
                    ),
                  if (results != null) ...[
                    _ResultSection<SearchScheduleResult>(
                      type: SearchResultType.schedule,
                      section: results.schedules,
                      icon: CupertinoIcons.calendar,
                      title: (item) => item.title,
                      meta: (item) => _scheduleMeta(item),
                      onPressed: _openSchedule,
                    ),
                    _ResultSection<SearchParkingResult>(
                      type: SearchResultType.parking,
                      section: results.parkingRecords,
                      icon: CupertinoIcons.car,
                      title: (item) => item.locationText,
                      meta: _parkingMeta,
                      onPressed: widget.onOpenParkingTab == null
                          ? null
                          : (_) => _openParking(),
                    ),
                    _ResultSection<SearchScrapPostResult>(
                      type: SearchResultType.scrapPost,
                      section: results.scrapPosts,
                      icon: CupertinoIcons.doc_text,
                      title: (item) => item.headline,
                      meta: (item) =>
                          '${item.channelName} · ${item.authorNickname} · ${_formatDate(item.createdAt)}',
                      onPressed: (item) => _openScrap(
                        channelId: item.channelId,
                        channelName: item.channelName,
                        postId: item.id,
                      ),
                    ),
                    _ResultSection<SearchScrapCommentResult>(
                      type: SearchResultType.scrapComment,
                      section: results.scrapComments,
                      icon: CupertinoIcons.chat_bubble,
                      title: (item) => item.content,
                      meta: (item) =>
                          '${item.channelName} · ${item.authorNickname} · ${_formatDate(item.createdAt)}',
                      onPressed: (item) => _openScrap(
                        channelId: item.channelId,
                        channelName: item.channelName,
                        postId: item.postId,
                      ),
                    ),
                    _ResultSection<Coupon>(
                      type: SearchResultType.coupon,
                      section: results.coupons,
                      icon: CupertinoIcons.ticket,
                      title: (item) => item.title,
                      meta: (item) => _couponMeta(item, now),
                      onPressed: _openCoupon,
                    ),
                    _ResultSection<TravelTrip>(
                      type: SearchResultType.travelTrip,
                      section: results.travelTrips,
                      icon: CupertinoIcons.airplane,
                      title: (item) => item.title,
                      meta: (item) =>
                          '${_formatDate(item.startsOn)} ~ ${_formatDate(item.endsOn)}',
                      onPressed: _openTravel,
                    ),
                    _ResultSection<SearchTravelItineraryResult>(
                      type: SearchResultType.travelItinerary,
                      section: results.travelItineraries,
                      icon: CupertinoIcons.map_pin,
                      title: (item) => item.title,
                      meta: (item) =>
                          '${item.trip.title} · ${_formatDate(item.itineraryDate)}',
                      onPressed: (item) =>
                          _openTravel(item.trip, itineraryId: item.id),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _scheduleMeta(SearchScheduleResult schedule) {
  final when = schedule.isAllDay
      ? '${_formatDate(schedule.startsAt)} 종일'
      : _formatDateTime(schedule.startsAt);
  final member = schedule.memberNickname?.trim();
  return member == null || member.isEmpty ? when : '$when · $member';
}

String _parkingMeta(SearchParkingResult record) {
  final parts = [
    record.vehicleNickname,
    if (record.plateNumber.trim().isNotEmpty) record.plateNumber.trim(),
    _formatDateTime(record.parkedAt),
  ];
  return parts.join(' · ');
}

String _couponMeta(Coupon coupon, DateTime now) {
  final expiry = coupon.expiresOn;
  final expiryText = expiry == null ? '만료일 없음' : '${_formatDate(expiry)} 만료';
  return '$expiryText · ${coupon.status(now)}';
}

String _two(int value) => value.toString().padLeft(2, '0');

String _formatDate(DateTime date) =>
    '${date.year}.${_two(date.month)}.${_two(date.day)}';

String _formatDateTime(DateTime date) =>
    '${_formatDate(date)} ${_two(date.hour)}:${_two(date.minute)}';

class _Notice extends StatelessWidget {
  const _Notice({
    super.key,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.textSecondary,
            ),
          ),
          if (onAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            CupertinoButton(
              color: colors.surfaceElevated,
              borderRadius: BorderRadius.circular(AppRadius.md),
              onPressed: onAction,
              child: Text(
                actionLabel ?? '다시 시도',
                style: AppTypography.label.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultSection<T> extends StatelessWidget {
  const _ResultSection({
    required this.type,
    required this.section,
    required this.icon,
    required this.title,
    required this.meta,
    required this.onPressed,
  });

  final SearchResultType type;
  final SearchSection<T> section;
  final IconData icon;
  final String Function(T item) title;
  final String Function(T item) meta;
  final void Function(T item)? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (section.items.isEmpty) return const SizedBox.shrink();

    return Padding(
      key: ValueKey('search-section-${type.apiValue}'),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                type.label,
                style: AppTypography.titleSmall.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                section.hasMore
                    ? '${section.items.length}+'
                    : '${section.items.length}',
                style: AppTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final item in section.items)
            _ResultTile(
              icon: icon,
              title: title(item),
              meta: meta(item),
              onPressed: onPressed == null ? null : () => onPressed!(item),
            ),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.icon,
    required this.title,
    required this.meta,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String meta;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: colors.primarySoft,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, color: colors.primary, size: 16),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.label.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (onPressed != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 16,
                color: colors.textMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
