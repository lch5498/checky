import 'package:flutter/cupertino.dart';

import '../../core/api_client.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_radius.dart';
import '../../design_system/app_spacing.dart';
import '../../design_system/app_typography.dart';
import '../../shared/refreshable_scroll_view.dart';
import '../../shared/schedule_section_switcher.dart';
import '../travel/travel_screen.dart';

enum _HolidaySubsection { holidays, longWeekends, bridgeDays }

class HolidayScreen extends StatefulWidget {
  const HolidayScreen({
    super.key,
    required this.family,
    required this.sessionToken,
    required this.onOpenCalendarAt,
    this.selectedScheduleSection,
    this.onScheduleSectionChanged,
  });

  final AppFamily family;
  final String sessionToken;
  final ValueChanged<DateTime> onOpenCalendarAt;
  final ScheduleSection? selectedScheduleSection;
  final ValueChanged<ScheduleSection>? onScheduleSectionChanged;

  @override
  State<HolidayScreen> createState() => _HolidayScreenState();
}

class _HolidayScreenState extends State<HolidayScreen> {
  final _apiClient = ApiClient();

  List<KoreanHoliday>? _holidays;
  List<TravelTrip>? _trips;
  _HolidaySubsection _subsection = _HolidaySubsection.holidays;
  String? _message;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHolidays();
  }

  @override
  void didUpdateWidget(covariant HolidayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.family.id != widget.family.id) {
      _holidays = null;
      _trips = null;
      _loadHolidays();
    }
  }

  Future<void> _loadHolidays() async {
    final now = _dayOnly(DateTime.now());
    final rangeEnd = DateTime(now.year + 2, 1, 1);

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final results = await Future.wait([
        _apiClient.getKoreanHolidays(
          widget.sessionToken,
          familyId: widget.family.id,
          rangeStart: now,
          rangeEnd: rangeEnd,
        ),
        _apiClient.getTravelDashboard(
          widget.sessionToken,
          familyId: widget.family.id,
        ),
      ]);
      final holidays = results[0] as List<KoreanHoliday>;
      final travelDashboard = results[1] as TravelDashboard;

      if (mounted) {
        setState(() {
          _holidays = holidays;
          _trips = travelDashboard.trips;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openTravelForRange(DateTime start, DateTime end) async {
    final trips = _overlappingTrips(_trips ?? const <TravelTrip>[], start, end);

    if (trips.isEmpty) {
      final result = await Navigator.of(context).push<TravelTripFormResult>(
        CupertinoPageRoute(
          fullscreenDialog: true,
          builder: (context) => TravelTripFormScreen(
            familyId: widget.family.id,
            sessionToken: widget.sessionToken,
            initialStartsOn: start,
            initialEndsOn: end,
          ),
        ),
      );
      final created = result?.trip;
      if (created == null || !mounted) {
        return;
      }

      await _loadHolidays();
      if (mounted) {
        await _openTrip(created);
      }
      return;
    }

    if (trips.length == 1) {
      await _openTrip(trips.single);
      return;
    }

    final selected = await showCupertinoModalPopup<TravelTrip>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('겹치는 여행'),
        message: const Text('열어 볼 여행을 선택해 주세요.'),
        actions: trips
            .map(
              (trip) => CupertinoActionSheetAction(
                onPressed: () => Navigator.of(context).pop(trip),
                child: Text('${trip.title} (${_travelRangeLabel(trip)})'),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
      ),
    );

    if (selected != null && mounted) {
      await _openTrip(selected);
    }
  }

  Future<void> _openTrip(TravelTrip trip) async {
    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (context) => TravelDetailScreen(
          family: widget.family,
          sessionToken: widget.sessionToken,
          trip: trip,
        ),
      ),
    );

    if (mounted) {
      await _loadHolidays();
    }
  }

  @override
  Widget build(BuildContext context) {
    AppColors.of(context);
    final holidays = _holidays ?? const <KoreanHoliday>[];
    final trips = _trips ?? const <TravelTrip>[];
    final now = _dayOnly(DateTime.now());
    final rangeEnd = DateTime(now.year + 2, 1, 1);
    final longWeekends = _longWeekends(holidays, now, rangeEnd);
    final bridgeDays = _bridgeDays(holidays, now, rangeEnd);

    return CupertinoPageScaffold(
      backgroundColor: AppColors.background,
      navigationBar: const CupertinoNavigationBar(middle: Text('공휴일')),
      child: SafeArea(
        child: RefreshableScrollView(
          onRefresh: _loadHolidays,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            18,
            AppSpacing.page,
            AppSpacing.xxl,
          ),
          children: [
            if (widget.selectedScheduleSection != null &&
                widget.onScheduleSectionChanged != null) ...[
              ScheduleSectionSwitcher(
                selectedSection: widget.selectedScheduleSection!,
                onSectionChanged: widget.onScheduleSectionChanged!,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            _HolidaySubsectionSwitcher(
              value: _subsection,
              onChanged: (value) {
                setState(() {
                  _subsection = value;
                });
              },
            ),
            const SizedBox(height: 18),
            if (_message != null) ...[
              _HolidayMessage(message: _message!),
              const SizedBox(height: 14),
            ],
            if (_isLoading && _holidays == null)
              const Padding(
                padding: EdgeInsets.only(top: 72),
                child: Center(child: CupertinoActivityIndicator()),
              )
            else
              ...switch (_subsection) {
                _HolidaySubsection.holidays => [
                  _HolidayDescription(text: '다가오는 대한민국 공휴일을 보여줍니다.'),
                  const SizedBox(height: 10),
                  if (holidays.isEmpty)
                    const _HolidayEmptyState(text: '다가오는 공휴일이 없습니다.')
                  else
                    for (final holiday in holidays)
                      _HolidayTile(
                        date: holiday.date,
                        title: holiday.name,
                        subtitle: _holidayDateLabel(holiday.date),
                        icon: CupertinoIcons.calendar,
                        onPressed: () => widget.onOpenCalendarAt(holiday.date),
                      ),
                ],
                _HolidaySubsection.longWeekends => [
                  const _HolidayDescription(
                    text: '공휴일과 주말을 합쳐 3일 이상 쉬는 연휴입니다.',
                  ),
                  const SizedBox(height: 10),
                  if (longWeekends.isEmpty)
                    const _HolidayEmptyState(text: '다가오는 3일 이상 연휴가 없습니다.')
                  else
                    for (final holiday in longWeekends)
                      _HolidayTile(
                        date: holiday.start,
                        title: '${holiday.length}일 연휴',
                        subtitle: _holidayRangeSubtitle(
                          holiday,
                          _overlappingTrips(trips, holiday.start, holiday.end),
                        ),
                        icon: CupertinoIcons.sun_max,
                        showTravelRegisterAction: _overlappingTrips(
                          trips,
                          holiday.start,
                          holiday.end,
                        ).isEmpty,
                        onPressed: () => widget.onOpenCalendarAt(holiday.start),
                        onTravelPressed: () =>
                            _openTravelForRange(holiday.start, holiday.end),
                      ),
                ],
                _HolidaySubsection.bridgeDays => [
                  const _HolidayDescription(
                    text: '하루 휴가를 더하면 3일 이상 연속으로 쉴 수 있는 평일입니다.',
                  ),
                  const SizedBox(height: 10),
                  if (bridgeDays.isEmpty)
                    const _HolidayEmptyState(text: '다가오는 징검다리 휴일이 없습니다.')
                  else
                    for (final bridgeDay in bridgeDays)
                      _HolidayTile(
                        date: bridgeDay.date,
                        title: '${bridgeDay.length}일 연휴',
                        subtitle: _bridgeDaySubtitle(
                          bridgeDay,
                          _overlappingTrips(
                            trips,
                            bridgeDay.start,
                            bridgeDay.end,
                          ),
                        ),
                        icon: CupertinoIcons.square_stack_3d_up,
                        showTravelRegisterAction: _overlappingTrips(
                          trips,
                          bridgeDay.start,
                          bridgeDay.end,
                        ).isEmpty,
                        onPressed: () =>
                            widget.onOpenCalendarAt(bridgeDay.date),
                        onTravelPressed: () =>
                            _openTravelForRange(bridgeDay.start, bridgeDay.end),
                      ),
                ],
              },
          ],
        ),
      ),
    );
  }
}

class _HolidaySubsectionSwitcher extends StatelessWidget {
  const _HolidaySubsectionSwitcher({
    required this.value,
    required this.onChanged,
  });

  final _HolidaySubsection value;
  final ValueChanged<_HolidaySubsection> onChanged;

  @override
  Widget build(BuildContext context) {
    AppColors.of(context);
    return CupertinoSlidingSegmentedControl<_HolidaySubsection>(
      groupValue: value,
      backgroundColor: AppColors.surfaceElevated,
      thumbColor: AppColors.primary,
      padding: const EdgeInsets.all(3),
      children: {
        _HolidaySubsection.holidays: _HolidaySubsectionLabel(
          label: '다가오는 공휴일',
          isSelected: value == _HolidaySubsection.holidays,
        ),
        _HolidaySubsection.longWeekends: _HolidaySubsectionLabel(
          label: '연휴',
          isSelected: value == _HolidaySubsection.longWeekends,
        ),
        _HolidaySubsection.bridgeDays: _HolidaySubsectionLabel(
          label: '징검다리',
          isSelected: value == _HolidaySubsection.bridgeDays,
        ),
      },
      onValueChanged: (next) {
        if (next != null) {
          onChanged(next);
        }
      },
    );
  }
}

class _HolidaySubsectionLabel extends StatelessWidget {
  const _HolidaySubsectionLabel({
    required this.label,
    required this.isSelected,
  });

  final String label;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 7,
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(
          color: isSelected ? AppColors.onPrimary : AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _HolidayDescription extends StatelessWidget {
  const _HolidayDescription({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    AppColors.of(context);
    return Text(
      text,
      style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary),
    );
  }
}

class _HolidayTile extends StatelessWidget {
  const _HolidayTile({
    required this.date,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onPressed,
    this.showTravelRegisterAction = false,
    this.onTravelPressed,
  });

  final DateTime date;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onPressed;
  final bool showTravelRegisterAction;
  final VoidCallback? onTravelPressed;

  @override
  Widget build(BuildContext context) {
    AppColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: CupertinoColors.systemRed.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, color: CupertinoColors.systemRed, size: 19),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.label.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (showTravelRegisterAction) ...[
                        const SizedBox(width: AppSpacing.sm),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(46, 30),
                          onPressed: onTravelPressed,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('✈️', style: AppTypography.bodyMedium),
                              const SizedBox(width: AppSpacing.xs),
                              Icon(
                                CupertinoIcons.plus_circle_fill,
                                color: AppColors.primary,
                                size: 19,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HolidayMessage extends StatelessWidget {
  const _HolidayMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        message,
        style: AppTypography.labelSmall.copyWith(color: AppColors.danger),
      ),
    );
  }
}

class _HolidayEmptyState extends StatelessWidget {
  const _HolidayEmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 52),
      child: Center(
        child: Text(
          text,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _HolidayBreak {
  const _HolidayBreak({
    required this.start,
    required this.end,
    required this.names,
  });

  final DateTime start;
  final DateTime end;
  final List<String> names;

  int get length => end.difference(start).inDays + 1;
}

class _BridgeDay {
  const _BridgeDay({
    required this.date,
    required this.start,
    required this.end,
  });

  final DateTime date;
  final DateTime start;
  final DateTime end;

  int get length => end.difference(start).inDays + 1;
}

List<TravelTrip> _overlappingTrips(
  List<TravelTrip> trips,
  DateTime rangeStart,
  DateTime rangeEnd,
) {
  return trips
      .where(
        (trip) =>
            !trip.startsOn.isAfter(rangeEnd) &&
            !trip.endsOn.isBefore(rangeStart),
      )
      .toList();
}

String _holidayRangeSubtitle(
  _HolidayBreak holiday,
  List<TravelTrip> overlappingTrips,
) {
  final holidaySummary =
      '${_rangeDateLabel(holiday.start, holiday.end)} · ${holiday.names.join(' · ')}';
  final travelSummary = _travelSummary(overlappingTrips);
  return travelSummary == null
      ? holidaySummary
      : '$holidaySummary\n$travelSummary';
}

String _bridgeDaySubtitle(
  _BridgeDay bridgeDay,
  List<TravelTrip> overlappingTrips,
) {
  final bridgeSummary =
      '${_holidayDateLabel(bridgeDay.date)} 휴가 - ${_rangeDateLabel(bridgeDay.start, bridgeDay.end)}';
  final travelSummary = _travelSummary(overlappingTrips);
  return travelSummary == null
      ? bridgeSummary
      : '$bridgeSummary\n$travelSummary';
}

String? _travelSummary(List<TravelTrip> trips) {
  if (trips.isEmpty) {
    return null;
  }

  final first = trips.first;
  final suffix = trips.length > 1 ? ' 외 ${trips.length - 1}개' : '';
  return '${first.title} - ${_travelRangeLabel(first)}$suffix';
}

String _travelRangeLabel(TravelTrip trip) {
  return _rangeDateLabel(trip.startsOn, trip.endsOn);
}

List<_HolidayBreak> _longWeekends(
  List<KoreanHoliday> holidays,
  DateTime rangeStart,
  DateTime rangeEnd,
) {
  final holidaysByDate = _holidaysByDate(holidays);
  final results = <_HolidayBreak>[];
  var day = rangeStart;

  while (day.isBefore(rangeEnd)) {
    if (!_isDayOff(day, holidaysByDate)) {
      day = day.add(const Duration(days: 1));
      continue;
    }

    final start = day;
    final names = <String>[];
    while (day.isBefore(rangeEnd) && _isDayOff(day, holidaysByDate)) {
      final holiday = holidaysByDate[_holidayDateKey(day)];
      if (holiday != null) {
        names.add(holiday.name);
      }
      day = day.add(const Duration(days: 1));
    }

    final end = day.subtract(const Duration(days: 1));
    final length = end.difference(start).inDays + 1;
    if (length >= 3 && names.isNotEmpty) {
      results.add(_HolidayBreak(start: start, end: end, names: names));
    }
  }

  return results;
}

List<_BridgeDay> _bridgeDays(
  List<KoreanHoliday> holidays,
  DateTime rangeStart,
  DateTime rangeEnd,
) {
  final holidaysByDate = _holidaysByDate(holidays);
  final results = <_BridgeDay>[];

  for (
    var day = rangeStart;
    day.isBefore(rangeEnd);
    day = day.add(const Duration(days: 1))
  ) {
    if (_isDayOff(day, holidaysByDate)) {
      continue;
    }

    var start = day.subtract(const Duration(days: 1));
    var hasDayOffBefore = false;
    while (!start.isBefore(rangeStart) && _isDayOff(start, holidaysByDate)) {
      hasDayOffBefore = true;
      start = start.subtract(const Duration(days: 1));
    }

    var end = day.add(const Duration(days: 1));
    var hasDayOffAfter = false;
    while (end.isBefore(rangeEnd) && _isDayOff(end, holidaysByDate)) {
      hasDayOffAfter = true;
      end = end.add(const Duration(days: 1));
    }

    if (hasDayOffBefore && hasDayOffAfter) {
      results.add(
        _BridgeDay(
          date: day,
          start: start.add(const Duration(days: 1)),
          end: end.subtract(const Duration(days: 1)),
        ),
      );
    }
  }

  return results;
}

Map<String, KoreanHoliday> _holidaysByDate(List<KoreanHoliday> holidays) {
  return {
    for (final holiday in holidays) _holidayDateKey(holiday.date): holiday,
  };
}

bool _isDayOff(DateTime day, Map<String, KoreanHoliday> holidaysByDate) {
  return day.weekday == DateTime.saturday ||
      day.weekday == DateTime.sunday ||
      holidaysByDate.containsKey(_holidayDateKey(day));
}

DateTime _dayOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _holidayDateKey(DateTime date) {
  final day = _dayOnly(date);
  return '${day.year}-${_two(day.month)}-${_two(day.day)}';
}

String _holidayDateLabel(DateTime date) {
  return '${date.year}.${_two(date.month)}.${_two(date.day)} ${_weekdayLabel(date.weekday)}';
}

String _rangeDateLabel(DateTime start, DateTime end) {
  if (start.year == end.year) {
    return '${start.year}.${_two(start.month)}.${_two(start.day)} - ${_two(end.month)}.${_two(end.day)}';
  }

  return '${start.year}.${_two(start.month)}.${_two(start.day)} - ${end.year}.${_two(end.month)}.${_two(end.day)}';
}

String _two(int value) => value.toString().padLeft(2, '0');

String _weekdayLabel(int weekday) {
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  return weekdays[weekday - 1];
}
