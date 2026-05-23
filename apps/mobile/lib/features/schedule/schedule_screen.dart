import 'package:flutter/cupertino.dart';

import '../../core/api_client.dart';

enum _CalendarMode { day, week, month }

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    required this.family,
    required this.sessionToken,
  });

  final AppFamily family;
  final String sessionToken;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final _apiClient = ApiClient();

  ScheduleDashboard? _dashboard;
  _CalendarMode _mode = _CalendarMode.week;
  DateTime _anchorDate = _dateOnly(DateTime.now());
  String? _message;
  bool _isLoading = true;

  DateTime get _rangeStart => _startOfRange(_anchorDate, _mode);
  DateTime get _rangeEnd => _endOfRange(_anchorDate, _mode);

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final dashboard = await _apiClient.getScheduleDashboard(
        widget.sessionToken,
        familyId: widget.family.id,
        rangeStart: _rangeStart,
        rangeEnd: _rangeEnd,
      );

      if (mounted) {
        setState(() {
          _dashboard = dashboard;
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

  Future<void> _runTask(Future<void> Function() task) async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      await task();
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

  void _setMode(_CalendarMode mode) {
    setState(() {
      _mode = mode;
      _anchorDate = _dateOnly(_anchorDate);
    });
    _loadSchedules();
  }

  void _moveRange(int direction) {
    setState(() {
      switch (_mode) {
        case _CalendarMode.day:
          _anchorDate = _anchorDate.add(Duration(days: direction));
        case _CalendarMode.week:
          _anchorDate = _anchorDate.add(Duration(days: 7 * direction));
        case _CalendarMode.month:
          _anchorDate = DateTime(
            _anchorDate.year,
            _anchorDate.month + direction,
            1,
          );
      }
    });
    _loadSchedules();
  }

  Future<void> _openScheduleForm({
    AppSchedule? schedule,
    DateTime? initialDate,
  }) async {
    final dashboard = _dashboard;

    if (dashboard == null || dashboard.members.isEmpty) {
      setState(() {
        _message = '일정을 등록할 가족 구성원이 필요합니다.';
      });
      return;
    }

    final input = await Navigator.of(context).push<_ScheduleInput>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ScheduleFormScreen(
          members: dashboard.members,
          schedule: schedule,
          initialDate: initialDate ?? schedule?.startsAt ?? _anchorDate,
        ),
      ),
    );

    if (input == null) {
      return;
    }

    await _runTask(() async {
      if (schedule == null) {
        await _apiClient.createSchedule(
          widget.sessionToken,
          familyId: widget.family.id,
          familyMemberId: input.familyMemberId,
          title: input.title,
          content: input.content,
          startsAt: input.startsAt,
          endsAt: input.endsAt,
          vehicleBoardingAt: input.vehicleBoardingAt,
          vehicleDropoffAt: input.vehicleDropoffAt,
        );
      } else {
        await _apiClient.updateSchedule(
          widget.sessionToken,
          familyId: widget.family.id,
          scheduleId: schedule.id,
          familyMemberId: input.familyMemberId,
          title: input.title,
          content: input.content,
          startsAt: input.startsAt,
          endsAt: input.endsAt,
          vehicleBoardingAt: input.vehicleBoardingAt,
          vehicleDropoffAt: input.vehicleDropoffAt,
        );
      }

      await _loadSchedules();
    });
  }

  Future<void> _deleteSchedule(AppSchedule schedule) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('일정 삭제'),
        content: Text('${schedule.title} 일정을 삭제할까요?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await _runTask(() async {
      await _apiClient.deleteSchedule(
        widget.sessionToken,
        familyId: widget.family.id,
        scheduleId: schedule.id,
      );
      await _loadSchedules();
    });
  }

  Future<void> _openScheduleDetail(AppSchedule schedule) async {
    final dashboard = _dashboard;
    final action = await Navigator.of(context).push<String>(
      CupertinoPageRoute(
        builder: (_) => _ScheduleDetailScreen(
          schedule: schedule,
          canManage: dashboard?.canManage ?? false,
        ),
      ),
    );

    if (action == 'edit') {
      await _openScheduleForm(schedule: schedule);
    } else if (action == 'delete') {
      await _deleteSchedule(schedule);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = _dashboard;
    final schedules = dashboard?.schedules ?? const <AppSchedule>[];

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      navigationBar: CupertinoNavigationBar(
        middle: const Text('일정 관리'),
        trailing: dashboard?.canManage == true
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(32, 32),
                onPressed: _isLoading ? null : () => _openScheduleForm(),
                child: const Icon(CupertinoIcons.plus),
              )
            : null,
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 18, 0, 32),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _ScheduleHeader(
                familyName: widget.family.name,
                mode: _mode,
                rangeLabel: _rangeLabel(_rangeStart, _rangeEnd, _mode),
                canManage: dashboard?.canManage ?? false,
                onModeChanged: _setMode,
                onPrevious: () => _moveRange(-1),
                onNext: () => _moveRange(1),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _InlineMessage(message: _message!),
              ),
            ],
            const SizedBox(height: 18),
            if (_isLoading && dashboard == null)
              const Padding(
                padding: EdgeInsets.only(top: 72),
                child: Center(child: CupertinoActivityIndicator()),
              )
            else if (dashboard == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _EmptyState(
                  icon: CupertinoIcons.calendar,
                  title: '일정을 불러오지 못했습니다.',
                  subtitle: '잠시 후 다시 시도해 주세요.',
                  actionLabel: '다시 불러오기',
                  onPressed: _loadSchedules,
                ),
              )
            else if (dashboard.members.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _EmptyState(
                  icon: CupertinoIcons.person_2,
                  title: '가족 구성원이 없습니다.',
                  subtitle: '가족 구성원이 있어야 누구 일정인지 지정할 수 있습니다.',
                  actionLabel: '다시 불러오기',
                  onPressed: _loadSchedules,
                ),
              )
            else
              _CalendarBoard(
                mode: _mode,
                rangeStart: _rangeStart,
                rangeEnd: _rangeEnd,
                anchorDate: _anchorDate,
                schedules: schedules,
                canManage: dashboard.canManage,
                onTapDate: (date) => _openScheduleForm(initialDate: date),
                onTapSchedule: _openScheduleDetail,
              ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleHeader extends StatelessWidget {
  const _ScheduleHeader({
    required this.familyName,
    required this.mode,
    required this.rangeLabel,
    required this.canManage,
    required this.onModeChanged,
    required this.onPrevious,
    required this.onNext,
  });

  final String familyName;
  final _CalendarMode mode;
  final String rangeLabel;
  final bool canManage;
  final ValueChanged<_CalendarMode> onModeChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            familyName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF111111),
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 16),
          CupertinoSlidingSegmentedControl<_CalendarMode>(
            groupValue: mode,
            children: const {
              _CalendarMode.day: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('일'),
              ),
              _CalendarMode.week: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('주'),
              ),
              _CalendarMode.month: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('월'),
              ),
            },
            onValueChanged: (value) {
              if (value != null) {
                onModeChanged(value);
              }
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(36, 36),
                onPressed: onPrevious,
                child: const Icon(CupertinoIcons.chevron_left, size: 20),
              ),
              Expanded(
                child: Text(
                  rangeLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF111111),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(36, 36),
                onPressed: onNext,
                child: const Icon(CupertinoIcons.chevron_right, size: 20),
              ),
            ],
          ),
          if (!canManage) ...[
            const SizedBox(height: 10),
            const Text(
              '구성원 권한은 조회만 가능합니다.',
              style: TextStyle(
                color: Color(0xFF6E6E73),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CalendarBoard extends StatelessWidget {
  const _CalendarBoard({
    required this.mode,
    required this.rangeStart,
    required this.rangeEnd,
    required this.anchorDate,
    required this.schedules,
    required this.canManage,
    required this.onTapDate,
    required this.onTapSchedule,
  });

  final _CalendarMode mode;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final DateTime anchorDate;
  final List<AppSchedule> schedules;
  final bool canManage;
  final ValueChanged<DateTime> onTapDate;
  final ValueChanged<AppSchedule> onTapSchedule;

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case _CalendarMode.day:
        return _DayCalendar(
          date: rangeStart,
          schedules: schedules,
          canManage: canManage,
          onTapDateTime: onTapDate,
          onTapSchedule: onTapSchedule,
        );
      case _CalendarMode.week:
        return _WeekCalendar(
          weekStart: rangeStart,
          schedules: schedules,
          canManage: canManage,
          onTapDate: onTapDate,
          onTapSchedule: onTapSchedule,
        );
      case _CalendarMode.month:
        return _MonthCalendar(
          monthStart: DateTime(anchorDate.year, anchorDate.month),
          schedules: schedules,
          canManage: canManage,
          onTapDate: onTapDate,
          onTapSchedule: onTapSchedule,
        );
    }
  }
}

class _DayCalendar extends StatefulWidget {
  const _DayCalendar({
    required this.date,
    required this.schedules,
    required this.canManage,
    required this.onTapDateTime,
    required this.onTapSchedule,
  });

  final DateTime date;
  final List<AppSchedule> schedules;
  final bool canManage;
  final ValueChanged<DateTime> onTapDateTime;
  final ValueChanged<AppSchedule> onTapSchedule;

  @override
  State<_DayCalendar> createState() => _DayCalendarState();
}

class _DayCalendarState extends State<_DayCalendar> {
  static const _hourRowHeight = 74.0;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset: _initialScrollOffset(),
    );
  }

  @override
  void didUpdateWidget(covariant _DayCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.date != widget.date ||
        oldWidget.schedules != widget.schedules) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_initialScrollOffset());
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  double _initialScrollOffset() {
    final targetHour = _initialDayHour(widget.date, widget.schedules);

    return (targetHour * _hourRowHeight).clamp(0, 23 * _hourRowHeight);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _calendarDecoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _CalendarTitleBar(title: _dayLabel(widget.date)),
          SizedBox(
            height: 620,
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                children: [
                  for (var hour = 0; hour <= 23; hour++)
                    _HourRow(
                      hour: hour,
                      schedules: widget.schedules
                          .where(
                            (schedule) =>
                                _startsInHour(schedule, widget.date, hour),
                          )
                          .toList(),
                      canManage: widget.canManage,
                      onTapEmpty: () => widget.onTapDateTime(
                        DateTime(
                          widget.date.year,
                          widget.date.month,
                          widget.date.day,
                          hour,
                        ),
                      ),
                      onTapSchedule: widget.onTapSchedule,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HourRow extends StatelessWidget {
  const _HourRow({
    required this.hour,
    required this.schedules,
    required this.canManage,
    required this.onTapEmpty,
    required this.onTapSchedule,
  });

  final int hour;
  final List<AppSchedule> schedules;
  final bool canManage;
  final VoidCallback onTapEmpty;
  final ValueChanged<AppSchedule> onTapSchedule;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 74,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE5E5EA))),
        ),
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: canManage ? onTapEmpty : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    _hourLabel(hour),
                    style: const TextStyle(
                      color: Color(0xFF8E8E93),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: schedules.isEmpty
                      ? const SizedBox(height: 38)
                      : Column(
                          children: schedules
                              .map(
                                (schedule) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _CompactSchedulePill(
                                    schedule: schedule,
                                    canManage: canManage,
                                    onTap: () => onTapSchedule(schedule),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeekCalendar extends StatefulWidget {
  const _WeekCalendar({
    required this.weekStart,
    required this.schedules,
    required this.canManage,
    required this.onTapDate,
    required this.onTapSchedule,
  });

  final DateTime weekStart;
  final List<AppSchedule> schedules;
  final bool canManage;
  final ValueChanged<DateTime> onTapDate;
  final ValueChanged<AppSchedule> onTapSchedule;

  @override
  State<_WeekCalendar> createState() => _WeekCalendarState();
}

class _WeekCalendarState extends State<_WeekCalendar> {
  static const _hourRowHeight = 74.0;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset: _initialScrollOffset(),
    );
  }

  @override
  void didUpdateWidget(covariant _WeekCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.weekStart != widget.weekStart ||
        oldWidget.schedules != widget.schedules) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_initialScrollOffset());
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  double _initialScrollOffset() {
    final targetHour = _initialWeekHour(widget.weekStart, widget.schedules);

    return (targetHour * _hourRowHeight).clamp(0, 23 * _hourRowHeight);
  }

  @override
  Widget build(BuildContext context) {
    final days = List.generate(7, (index) {
      return widget.weekStart.add(Duration(days: index));
    });

    return Container(
      decoration: _calendarDecoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 58,
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: Color(0xFFE5E5EA))),
                ),
              ),
              ...days.map((day) => Expanded(child: _WeekDayHeader(date: day))),
            ],
          ),
          Container(height: 1, color: const Color(0xFFE5E5EA)),
          SizedBox(
            height: 620,
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                children: [
                  for (var hour = 0; hour <= 23; hour++)
                    _WeekHourRow(
                      hour: hour,
                      days: days,
                      schedules: widget.schedules,
                      canManage: widget.canManage,
                      onTapDateTime: widget.onTapDate,
                      onTapSchedule: widget.onTapSchedule,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekHourRow extends StatelessWidget {
  const _WeekHourRow({
    required this.hour,
    required this.days,
    required this.schedules,
    required this.canManage,
    required this.onTapDateTime,
    required this.onTapSchedule,
  });

  final int hour;
  final List<DateTime> days;
  final List<AppSchedule> schedules;
  final bool canManage;
  final ValueChanged<DateTime> onTapDateTime;
  final ValueChanged<AppSchedule> onTapSchedule;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 74,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 32,
            padding: const EdgeInsets.only(top: 8, right: 4),
            alignment: Alignment.topRight,
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0xFFE5E5EA)),
                right: BorderSide(color: Color(0xFFE5E5EA)),
              ),
            ),
            child: Text(
              _hourLabel(hour),
              style: const TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          ...days.map(
            (day) => Expanded(
              child: _WeekHourCell(
                dateTime: DateTime(day.year, day.month, day.day, hour),
                schedules: schedules
                    .where((schedule) => _startsInHour(schedule, day, hour))
                    .toList(),
                canManage: canManage,
                onTapDateTime: onTapDateTime,
                onTapSchedule: onTapSchedule,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekHourCell extends StatelessWidget {
  const _WeekHourCell({
    required this.dateTime,
    required this.schedules,
    required this.canManage,
    required this.onTapDateTime,
    required this.onTapSchedule,
  });

  final DateTime dateTime;
  final List<AppSchedule> schedules;
  final bool canManage;
  final ValueChanged<DateTime> onTapDateTime;
  final ValueChanged<AppSchedule> onTapSchedule;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canManage ? () => onTapDateTime(dateTime) : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(5, 6, 5, 5),
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Color(0xFFE5E5EA)),
            right: BorderSide(color: Color(0xFFE5E5EA)),
          ),
        ),
        child: Column(
          children: schedules
              .take(2)
              .map(
                (schedule) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _MiniScheduleChip(
                    schedule: schedule,
                    canManage: canManage,
                    onTap: () => onTapSchedule(schedule),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.monthStart,
    required this.schedules,
    required this.canManage,
    required this.onTapDate,
    required this.onTapSchedule,
  });

  final DateTime monthStart;
  final List<AppSchedule> schedules;
  final bool canManage;
  final ValueChanged<DateTime> onTapDate;
  final ValueChanged<AppSchedule> onTapSchedule;

  @override
  Widget build(BuildContext context) {
    final gridStart = monthStart.subtract(
      Duration(days: monthStart.weekday % 7),
    );
    final days = List.generate(
      42,
      (index) => gridStart.add(Duration(days: index)),
    );

    return Container(
      decoration: _calendarDecoration,
      child: Column(
        children: [
          Row(
            children: List.generate(
              7,
              (index) => Expanded(
                child: _MonthWeekdayHeader(label: _calendarWeekdayLabel(index)),
              ),
            ),
          ),
          Container(height: 1, color: const Color(0xFFE5E5EA)),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 112,
            ),
            itemCount: days.length,
            itemBuilder: (context, index) {
              final day = days[index];

              return _DateCell(
                date: day,
                schedules: _schedulesForDay(schedules, day),
                canManage: canManage,
                isInCurrentMonth: day.month == monthStart.month,
                maxVisibleSchedules: 2,
                minHeight: 112,
                onTapDate: () => onTapDate(day),
                onTapSchedule: onTapSchedule,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CalendarTitleBar extends StatelessWidget {
  const _CalendarTitleBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.calendar,
            color: CupertinoColors.systemTeal,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF111111),
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekDayHeader extends StatelessWidget {
  const _WeekDayHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final isToday = _dateOnly(date) == _dateOnly(DateTime.now());

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xFFE5E5EA))),
      ),
      child: Column(
        children: [
          Text(
            _weekdayLabel(date.weekday),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isToday
                  ? CupertinoColors.systemTeal
                  : const Color(0xFF6E6E73),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 26,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isToday ? CupertinoColors.systemTeal : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${date.day}',
              style: TextStyle(
                color: isToday
                    ? CupertinoColors.white
                    : const Color(0xFF111111),
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthWeekdayHeader extends StatelessWidget {
  const _MonthWeekdayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF6E6E73),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _DateCell extends StatelessWidget {
  const _DateCell({
    required this.date,
    required this.schedules,
    required this.canManage,
    required this.isInCurrentMonth,
    required this.maxVisibleSchedules,
    required this.minHeight,
    required this.onTapDate,
    required this.onTapSchedule,
  });

  final DateTime date;
  final List<AppSchedule> schedules;
  final bool canManage;
  final bool isInCurrentMonth;
  final int maxVisibleSchedules;
  final double minHeight;
  final VoidCallback onTapDate;
  final ValueChanged<AppSchedule> onTapSchedule;

  @override
  Widget build(BuildContext context) {
    final isToday = _dateOnly(date) == _dateOnly(DateTime.now());
    final visibleSchedules = schedules.take(maxVisibleSchedules).toList();
    final hiddenCount = schedules.length - visibleSchedules.length;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: canManage ? onTapDate : null,
      child: Container(
        constraints: BoxConstraints(minHeight: minHeight),
        padding: const EdgeInsets.fromLTRB(5, 7, 5, 7),
        decoration: const BoxDecoration(
          border: Border(
            right: BorderSide(color: Color(0xFFE5E5EA)),
            bottom: BorderSide(color: Color(0xFFE5E5EA)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 24,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isToday ? CupertinoColors.systemTeal : null,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    color: isToday
                        ? CupertinoColors.white
                        : isInCurrentMonth
                        ? const Color(0xFF111111)
                        : const Color(0xFFC7C7CC),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            ...visibleSchedules.map(
              (schedule) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _MiniScheduleChip(
                  schedule: schedule,
                  canManage: canManage,
                  onTap: () => onTapSchedule(schedule),
                ),
              ),
            ),
            if (hiddenCount > 0)
              Text(
                '+$hiddenCount',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF6E6E73),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniScheduleChip extends StatelessWidget {
  const _MiniScheduleChip({
    required this.schedule,
    required this.canManage,
    required this.onTap,
  });

  final AppSchedule schedule;
  final bool canManage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: canManage ? onTap : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFE6F3F1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          _calendarTitleLabel(schedule.title),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
          style: const TextStyle(
            color: Color(0xFF006D68),
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _CompactSchedulePill extends StatelessWidget {
  const _CompactSchedulePill({
    required this.schedule,
    required this.canManage,
    required this.onTap,
  });

  final AppSchedule schedule;
  final bool canManage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: canManage ? onTap : null,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFE6F3F1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFD2E8E5)),
        ),
        child: Text(
          _calendarTitleLabel(schedule.title),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
          style: const TextStyle(
            color: Color(0xFF006D68),
            fontSize: 12,
            height: 1.15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _ScheduleDetailScreen extends StatelessWidget {
  const _ScheduleDetailScreen({
    required this.schedule,
    required this.canManage,
  });

  final AppSchedule schedule;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      navigationBar: CupertinoNavigationBar(
        middle: const Text('일정 상세'),
        trailing: canManage
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).pop('edit'),
                child: const Text('수정'),
              )
            : null,
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: CupertinoColors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E5EA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    schedule.memberNickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CupertinoColors.systemTeal,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    schedule.title,
                    style: const TextStyle(
                      color: Color(0xFF111111),
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.12,
                      letterSpacing: 0,
                    ),
                  ),
                  if (schedule.content != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      schedule.content!,
                      style: const TextStyle(
                        color: Color(0xFF3A3A3C),
                        fontSize: 16,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            _DetailSection(
              children: [
                _DetailRow(
                  icon: CupertinoIcons.person_crop_circle,
                  label: '구성원',
                  value: schedule.memberNickname,
                ),
                _DetailDivider(),
                _DetailRow(
                  icon: CupertinoIcons.calendar,
                  label: 'From',
                  value: _fullDateTimeLabel(schedule.startsAt),
                ),
                _DetailDivider(),
                _DetailRow(
                  icon: CupertinoIcons.clock,
                  label: 'To',
                  value: _fullDateTimeLabel(schedule.endsAt),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _DetailSection(
              children: [
                _DetailRow(
                  icon: CupertinoIcons.car_detailed,
                  label: '차량승차시각',
                  value: schedule.vehicleBoardingAt == null
                      ? '선택 안 함'
                      : _fullDateTimeLabel(schedule.vehicleBoardingAt!),
                ),
                _DetailDivider(),
                _DetailRow(
                  icon: CupertinoIcons.location,
                  label: '하차시각',
                  value: schedule.vehicleDropoffAt == null
                      ? '선택 안 함'
                      : _fullDateTimeLabel(schedule.vehicleDropoffAt!),
                ),
              ],
            ),
            if (canManage) ...[
              const SizedBox(height: 18),
              SizedBox(
                height: 50,
                child: CupertinoButton(
                  color: const Color(0xFFFFE8E8),
                  borderRadius: BorderRadius.circular(14),
                  onPressed: () => Navigator.of(context).pop('delete'),
                  child: const Text(
                    '일정 삭제',
                    style: TextStyle(
                      color: CupertinoColors.destructiveRed,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Column(children: children),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: CupertinoColors.systemTeal, size: 19),
          const SizedBox(width: 10),
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6E6E73),
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF111111),
                fontSize: 15,
                height: 1.35,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: const Color(0xFFE5E5EA));
  }
}

class _ScheduleFormScreen extends StatefulWidget {
  const _ScheduleFormScreen({
    required this.members,
    required this.initialDate,
    this.schedule,
  });

  final List<FamilyMember> members;
  final DateTime initialDate;
  final AppSchedule? schedule;

  @override
  State<_ScheduleFormScreen> createState() => _ScheduleFormScreenState();
}

class _ScheduleFormScreenState extends State<_ScheduleFormScreen> {
  late String _familyMemberId;
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late DateTime _startsAt;
  late DateTime _endsAt;
  DateTime? _vehicleBoardingAt;
  DateTime? _vehicleDropoffAt;
  String? _message;

  @override
  void initState() {
    super.initState();
    final schedule = widget.schedule;
    _familyMemberId = schedule?.familyMemberId ?? widget.members.first.id;
    _titleController = TextEditingController(text: schedule?.title);
    _contentController = TextEditingController(text: schedule?.content);
    _startsAt = schedule?.startsAt ?? _defaultStartAt(widget.initialDate);
    _endsAt = schedule?.endsAt ?? _startsAt.add(const Duration(hours: 1));
    _vehicleBoardingAt = schedule?.vehicleBoardingAt;
    _vehicleDropoffAt = schedule?.vehicleDropoffAt;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickMember() async {
    final selectedId = await showCupertinoModalPopup<String>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('가족 구성원'),
        actions: widget.members
            .map(
              (member) => CupertinoActionSheetAction(
                isDefaultAction: member.id == _familyMemberId,
                onPressed: () => Navigator.of(context).pop(member.id),
                child: Text(member.userNickname),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
      ),
    );

    if (selectedId != null) {
      setState(() {
        _familyMemberId = selectedId;
      });
    }
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final initial = isStart ? _startsAt : _endsAt;
    final picked = await _showDateTimePicker(initial);

    if (picked == null) {
      return;
    }

    setState(() {
      if (isStart) {
        final previousDuration = _endsAt.difference(_startsAt);
        _startsAt = picked;
        _endsAt = picked.add(
          previousDuration.isNegative || previousDuration.inMinutes == 0
              ? const Duration(hours: 1)
              : previousDuration,
        );
      } else {
        _endsAt = picked;
      }
    });
  }

  Future<void> _pickOptionalDateTime({required bool isBoarding}) async {
    final current = isBoarding ? _vehicleBoardingAt : _vehicleDropoffAt;
    final picked = await _showDateTimePicker(current ?? _startsAt);

    if (picked == null) {
      return;
    }

    setState(() {
      if (isBoarding) {
        _vehicleBoardingAt = picked;
      } else {
        _vehicleDropoffAt = picked;
      }
    });
  }

  Future<DateTime?> _showDateTimePicker(DateTime initial) async {
    DateTime selected = initial;

    return showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (_) => Container(
        height: 320,
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              SizedBox(
                height: 52,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('취소'),
                    ),
                    CupertinoButton(
                      onPressed: () => Navigator.of(context).pop(selected),
                      child: const Text('완료'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  initialDateTime: initial,
                  mode: CupertinoDatePickerMode.dateAndTime,
                  minuteInterval: 5,
                  use24hFormat: true,
                  onDateTimeChanged: (value) {
                    selected = value;
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty) {
      setState(() {
        _message = '제목을 입력해 주세요.';
      });
      return;
    }

    if (_endsAt.isBefore(_startsAt)) {
      setState(() {
        _message = '종료 시각은 시작 시각 이후여야 합니다.';
      });
      return;
    }

    Navigator.of(context).pop(
      _ScheduleInput(
        familyMemberId: _familyMemberId,
        title: title,
        content: content.isEmpty ? null : content,
        startsAt: _startsAt,
        endsAt: _endsAt,
        vehicleBoardingAt: _vehicleBoardingAt,
        vehicleDropoffAt: _vehicleDropoffAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedMember = widget.members.firstWhere(
      (member) => member.id == _familyMemberId,
      orElse: () => widget.members.first,
    );

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.schedule == null ? '일정 등록' : '일정 수정'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _submit,
          child: const Text('저장'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            _FormSection(
              children: [
                _PickerRow(
                  label: '구성원',
                  value: selectedMember.userNickname,
                  onPressed: _pickMember,
                ),
                _FormDivider(),
                CupertinoTextField.borderless(
                  controller: _titleController,
                  placeholder: '제목',
                  maxLength: 80,
                  style: const TextStyle(fontSize: 17, letterSpacing: 0),
                ),
                _FormDivider(),
                CupertinoTextField.borderless(
                  controller: _contentController,
                  placeholder: '내용',
                  maxLines: 4,
                  maxLength: 1000,
                  style: const TextStyle(fontSize: 16, letterSpacing: 0),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _FormSection(
              children: [
                _PickerRow(
                  label: 'From',
                  value: _dateTimeLabel(_startsAt),
                  onPressed: () => _pickDateTime(isStart: true),
                ),
                _FormDivider(),
                _PickerRow(
                  label: 'To',
                  value: _dateTimeLabel(_endsAt),
                  onPressed: () => _pickDateTime(isStart: false),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _FormSection(
              children: [
                _OptionalTimeRow(
                  label: '차량승차시각',
                  value: _vehicleBoardingAt,
                  onPick: () => _pickOptionalDateTime(isBoarding: true),
                  onClear: () => setState(() => _vehicleBoardingAt = null),
                ),
                _FormDivider(),
                _OptionalTimeRow(
                  label: '하차시각',
                  value: _vehicleDropoffAt,
                  onPick: () => _pickOptionalDateTime(isBoarding: false),
                  onClear: () => setState(() => _vehicleDropoffAt = null),
                ),
              ],
            ),
            if (_message != null) ...[
              const SizedBox(height: 14),
              _InlineMessage(message: _message!),
            ],
          ],
        ),
      ),
    );
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Column(children: children),
    );
  }
}

class _FormDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: const Color(0xFFE5E5EA));
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final String label;
  final String value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF111111),
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Color(0xFF6E6E73),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              CupertinoIcons.chevron_right,
              color: CupertinoColors.systemGrey,
              size: 17,
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionalTimeRow extends StatelessWidget {
  const _OptionalTimeRow({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          Expanded(
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onPick,
              child: Row(
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF111111),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      value == null ? '선택 안 함' : _dateTimeLabel(value!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Color(0xFF6E6E73),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (value != null)
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(34, 34),
              onPressed: onClear,
              child: const Icon(
                CupertinoIcons.xmark_circle_fill,
                color: CupertinoColors.systemGrey,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Column(
        children: [
          Icon(icon, color: CupertinoColors.systemGrey, size: 34),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF111111),
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF6E6E73),
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
          if (onPressed != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 46,
              child: CupertinoButton.filled(
                borderRadius: BorderRadius.circular(12),
                onPressed: onPressed,
                child: Text(
                  actionLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          message,
          style: const TextStyle(
            color: Color(0xFFB42318),
            fontSize: 14,
            height: 1.35,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _ScheduleInput {
  const _ScheduleInput({
    required this.familyMemberId,
    required this.title,
    required this.content,
    required this.startsAt,
    required this.endsAt,
    required this.vehicleBoardingAt,
    required this.vehicleDropoffAt,
  });

  final String familyMemberId;
  final String title;
  final String? content;
  final DateTime startsAt;
  final DateTime endsAt;
  final DateTime? vehicleBoardingAt;
  final DateTime? vehicleDropoffAt;
}

DateTime _startOfRange(DateTime date, _CalendarMode mode) {
  final day = _dateOnly(date);

  switch (mode) {
    case _CalendarMode.day:
      return day;
    case _CalendarMode.week:
      return day.subtract(Duration(days: day.weekday % 7));
    case _CalendarMode.month:
      return DateTime(day.year, day.month);
  }
}

DateTime _endOfRange(DateTime date, _CalendarMode mode) {
  switch (mode) {
    case _CalendarMode.day:
      return _startOfRange(date, mode).add(const Duration(days: 1));
    case _CalendarMode.week:
      return _startOfRange(date, mode).add(const Duration(days: 7));
    case _CalendarMode.month:
      final start = _startOfRange(date, mode);
      return DateTime(start.year, start.month + 1);
  }
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime _defaultStartAt(DateTime initialDate) {
  if (initialDate.hour == 0 && initialDate.minute == 0) {
    return DateTime(initialDate.year, initialDate.month, initialDate.day, 15);
  }

  return initialDate;
}

BoxDecoration get _calendarDecoration => BoxDecoration(
  color: CupertinoColors.white,
  border: const Border(
    top: BorderSide(color: Color(0xFFE5E5EA)),
    bottom: BorderSide(color: Color(0xFFE5E5EA)),
  ),
);

List<AppSchedule> _schedulesForDay(List<AppSchedule> schedules, DateTime day) {
  return schedules
      .where((schedule) => _dateOnly(schedule.startsAt) == _dateOnly(day))
      .toList();
}

bool _startsInHour(AppSchedule schedule, DateTime day, int hour) {
  return _dateOnly(schedule.startsAt) == _dateOnly(day) &&
      schedule.startsAt.hour == hour;
}

int _initialDayHour(DateTime date, List<AppSchedule> schedules) {
  final daySchedules =
      schedules
          .where((schedule) => _dateOnly(schedule.startsAt) == _dateOnly(date))
          .toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  if (daySchedules.isEmpty) {
    return 8;
  }

  return daySchedules.first.startsAt.hour;
}

int _initialWeekHour(DateTime weekStart, List<AppSchedule> schedules) {
  final today = _dateOnly(DateTime.now());
  final weekEnd = weekStart.add(const Duration(days: 7));

  if (today.isBefore(weekStart) || !today.isBefore(weekEnd)) {
    return 8;
  }

  final todaySchedules =
      schedules
          .where((schedule) => _dateOnly(schedule.startsAt) == today)
          .toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  if (todaySchedules.isEmpty) {
    return 8;
  }

  return todaySchedules.first.startsAt.hour;
}

String _rangeLabel(DateTime start, DateTime end, _CalendarMode mode) {
  switch (mode) {
    case _CalendarMode.day:
      return _dateLabel(start);
    case _CalendarMode.week:
      final lastDay = end.subtract(const Duration(days: 1));
      return '${_monthDayLabel(start)} - ${_monthDayLabel(lastDay)}';
    case _CalendarMode.month:
      return '${start.year}년 ${start.month}월';
  }
}

String _dayLabel(DateTime date) =>
    '${_dateLabel(date)} ${_weekdayLabel(date.weekday)}';

String _dateLabel(DateTime date) =>
    '${date.year}.${_two(date.month)}.${_two(date.day)}';

String _monthDayLabel(DateTime date) => '${date.month}.${date.day}';

String _weekdayLabel(int weekday) {
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  return weekdays[weekday - 1];
}

String _calendarWeekdayLabel(int index) {
  const weekdays = ['일', '월', '화', '수', '목', '금', '토'];

  return weekdays[index];
}

String _dateTimeLabel(DateTime date) {
  return '${date.month}.${date.day} ${_timeLabel(date)}';
}

String _fullDateTimeLabel(DateTime date) {
  return '${_dateLabel(date)} ${_weekdayLabel(date.weekday)} ${_timeLabel(date)}';
}

String _calendarTitleLabel(String title) {
  final characters = title.runes.toList();

  if (characters.length <= 8) {
    return title;
  }

  return '${String.fromCharCodes(characters.take(8))}...';
}

String _timeLabel(DateTime date) => '${_two(date.hour)}:${_two(date.minute)}';

String _hourLabel(int hour) => '$hour시';

String _two(int value) => value.toString().padLeft(2, '0');
