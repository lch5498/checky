import 'package:flutter/cupertino.dart';

import '../../core/api_client.dart';
import '../../shared/member_filter.dart';

enum _CalendarMode { day, week, month }

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    required this.family,
    required this.families,
    required this.sessionToken,
    required this.refreshToken,
    required this.todayRequestToken,
    required this.onSelectFamily,
  });

  final AppFamily family;
  final List<AppFamily> families;
  final String sessionToken;
  final int refreshToken;
  final int todayRequestToken;
  final Future<void> Function(AppFamily family) onSelectFamily;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final _apiClient = ApiClient();

  late AppFamily _family;
  ScheduleDashboard? _dashboard;
  _CalendarMode _mode = _CalendarMode.week;
  DateTime _anchorDate = _dateOnly(DateTime.now());
  final Set<String> _hiddenMemberIds = <String>{};
  String? _message;
  bool _isLoading = true;

  DateTime get _rangeStart => _startOfRange(_anchorDate, _mode);
  DateTime get _rangeEnd => _endOfRange(_anchorDate, _mode);
  List<AppSchedule> get _filteredSchedules {
    final dashboard = _dashboard;

    if (dashboard == null) {
      return const [];
    }

    if (_hiddenMemberIds.isEmpty) {
      return dashboard.schedules;
    }

    return dashboard.schedules
        .where(
          (schedule) =>
              schedule.familyMemberId == null ||
              !_hiddenMemberIds.contains(schedule.familyMemberId),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _family = widget.family;
    if (widget.todayRequestToken > 0) {
      _setTodayDayViewState();
    }
    _loadSchedules();
  }

  @override
  void didUpdateWidget(covariant ScheduleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.family.id != widget.family.id) {
      _family = widget.family;
      _hiddenMemberIds.clear();
      _loadSchedules();
    } else if (oldWidget.todayRequestToken != widget.todayRequestToken) {
      setState(_setTodayDayViewState);
      _loadSchedules();
    } else if (oldWidget.refreshToken != widget.refreshToken) {
      _loadSchedules();
    }
  }

  void _setTodayDayViewState() {
    _mode = _CalendarMode.day;
    _anchorDate = _dateOnly(DateTime.now());
  }

  Future<void> _loadSchedules() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final dashboard = await _apiClient.getScheduleDashboard(
        widget.sessionToken,
        familyId: _family.id,
        rangeStart: _rangeStart,
        rangeEnd: _rangeEnd,
      );

      if (mounted) {
        setState(() {
          _dashboard = dashboard;
          _hiddenMemberIds.removeWhere(
            (memberId) =>
                !dashboard.members.any((member) => member.id == memberId),
          );
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

  void _toggleMemberFilter(String memberId) {
    setState(() {
      if (_hiddenMemberIds.contains(memberId)) {
        _hiddenMemberIds.remove(memberId);
      } else {
        _hiddenMemberIds.add(memberId);
      }
    });
  }

  Future<void> _switchFamily() async {
    if (widget.families.length < 2) {
      return;
    }

    final selectedFamilyId = await showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: const Text('가족 전환'),
        actions: widget.families
            .map(
              (family) => CupertinoActionSheetAction(
                isDefaultAction: family.id == _family.id,
                onPressed: () => Navigator.of(popupContext).pop(family.id),
                child: Text(family.name),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: const Text('취소'),
        ),
      ),
    );

    if (selectedFamilyId == null) {
      return;
    }

    final selectedFamily = widget.families.firstWhere(
      (family) => family.id == selectedFamilyId,
    );

    setState(() {
      _family = selectedFamily;
      _dashboard = null;
      _hiddenMemberIds.clear();
    });
    await widget.onSelectFamily(selectedFamily);
    await _loadSchedules();
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
          educationPrograms: dashboard.educationPrograms,
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
          familyId: _family.id,
          familyMemberId: input.familyMemberId,
          title: input.title,
          content: input.content,
          startsAt: input.startsAt,
          endsAt: input.endsAt,
          vehicleBoardingAt: input.vehicleBoardingAt,
          vehicleDropoffAt: input.vehicleDropoffAt,
          educationProgramId: input.educationProgramId,
        );
      } else {
        await _apiClient.updateSchedule(
          widget.sessionToken,
          familyId: _family.id,
          scheduleId: schedule.id,
          familyMemberId: input.familyMemberId,
          title: input.title,
          content: input.content,
          startsAt: input.startsAt,
          endsAt: input.endsAt,
          vehicleBoardingAt: input.vehicleBoardingAt,
          vehicleDropoffAt: input.vehicleDropoffAt,
          educationProgramId: input.educationProgramId,
        );
      }

      await _loadSchedules();
    });
  }

  Future<void> _deleteSchedule(AppSchedule schedule) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('일정 삭제'),
        content: Text('${schedule.title} 일정을 삭제할까요?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
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
        familyId: _family.id,
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
    final schedules = _filteredSchedules;
    final memberColors = _memberFilterColors(dashboard?.members ?? const []);

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      navigationBar: CupertinoNavigationBar(
        middle: _FeatureFamilyTitle(
          family: _family,
          featureName: '일정',
          canSwitch: widget.families.length > 1,
          onPressed: _switchFamily,
        ),
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
                mode: _mode,
                rangeLabel: _rangeLabel(_rangeStart, _rangeEnd, _mode),
                canManage: dashboard?.canManage ?? false,
                members: dashboard?.members ?? const [],
                hiddenMemberIds: _hiddenMemberIds,
                memberColors: memberColors,
                onToggleMemberFilter: _toggleMemberFilter,
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
                memberColors: memberColors,
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

class _FeatureFamilyTitle extends StatelessWidget {
  const _FeatureFamilyTitle({
    required this.family,
    required this.featureName,
    required this.canSwitch,
    required this.onPressed,
  });

  final AppFamily family;
  final String featureName;
  final bool canSwitch;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final title = '${family.name} $featureName';

    if (!canSwitch) {
      return Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          inherit: false,
          color: Color(0xFF111111),
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      );
    }

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 32),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                inherit: false,
                color: Color(0xFF111111),
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(CupertinoIcons.chevron_down, size: 15),
        ],
      ),
    );
  }
}

class _ScheduleHeader extends StatelessWidget {
  const _ScheduleHeader({
    required this.mode,
    required this.rangeLabel,
    required this.canManage,
    required this.members,
    required this.hiddenMemberIds,
    required this.memberColors,
    required this.onToggleMemberFilter,
    required this.onModeChanged,
    required this.onPrevious,
    required this.onNext,
  });

  final _CalendarMode mode;
  final String rangeLabel;
  final bool canManage;
  final List<FamilyMember> members;
  final Set<String> hiddenMemberIds;
  final Map<String, MemberFilterColor> memberColors;
  final ValueChanged<String> onToggleMemberFilter;
  final ValueChanged<_CalendarMode> onModeChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E5EA))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (members.isNotEmpty) ...[
            MemberFilterBar(
              members: members,
              hiddenMemberIds: hiddenMemberIds,
              memberColors: memberColors,
              onToggleMember: onToggleMemberFilter,
            ),
            const SizedBox(height: 16),
          ],
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
          const SizedBox(height: 12),
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
    required this.memberColors,
    required this.canManage,
    required this.onTapDate,
    required this.onTapSchedule,
  });

  final _CalendarMode mode;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final DateTime anchorDate;
  final List<AppSchedule> schedules;
  final Map<String, MemberFilterColor> memberColors;
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
          memberColors: memberColors,
          canManage: canManage,
          onTapDateTime: onTapDate,
          onTapSchedule: onTapSchedule,
        );
      case _CalendarMode.week:
        return _WeekCalendar(
          weekStart: rangeStart,
          schedules: schedules,
          memberColors: memberColors,
          canManage: canManage,
          onTapDate: onTapDate,
          onTapSchedule: onTapSchedule,
        );
      case _CalendarMode.month:
        return _MonthCalendar(
          monthStart: DateTime(anchorDate.year, anchorDate.month),
          schedules: schedules,
          memberColors: memberColors,
          canManage: canManage,
          onTapDate: onTapDate,
          onTapSchedule: onTapSchedule,
        );
    }
  }
}

const double _calendarHourRowHeight = 74.0;
const double _dayTimeColumnWidth = 54.0;
const double _weekTimeColumnWidth = 32.0;
const String _educationProgramNoneValue = '__none__';

class _DayCalendar extends StatefulWidget {
  const _DayCalendar({
    required this.date,
    required this.schedules,
    required this.memberColors,
    required this.canManage,
    required this.onTapDateTime,
    required this.onTapSchedule,
  });

  final DateTime date;
  final List<AppSchedule> schedules;
  final Map<String, MemberFilterColor> memberColors;
  final bool canManage;
  final ValueChanged<DateTime> onTapDateTime;
  final ValueChanged<AppSchedule> onTapSchedule;

  @override
  State<_DayCalendar> createState() => _DayCalendarState();
}

class _DayCalendarState extends State<_DayCalendar> {
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

    return (targetHour * _calendarHourRowHeight).clamp(
      0,
      23 * _calendarHourRowHeight,
    );
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
              child: SizedBox(
                height: _calendarHourRowHeight * 24,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _TimeAxis(width: _dayTimeColumnWidth),
                    Expanded(
                      child: _TimedDayColumn(
                        date: widget.date,
                        schedules: widget.schedules,
                        memberColors: widget.memberColors,
                        canManage: widget.canManage,
                        onTapDateTime: widget.onTapDateTime,
                        onTapSchedule: widget.onTapSchedule,
                        showLeftBorder: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekCalendar extends StatefulWidget {
  const _WeekCalendar({
    required this.weekStart,
    required this.schedules,
    required this.memberColors,
    required this.canManage,
    required this.onTapDate,
    required this.onTapSchedule,
  });

  final DateTime weekStart;
  final List<AppSchedule> schedules;
  final Map<String, MemberFilterColor> memberColors;
  final bool canManage;
  final ValueChanged<DateTime> onTapDate;
  final ValueChanged<AppSchedule> onTapSchedule;

  @override
  State<_WeekCalendar> createState() => _WeekCalendarState();
}

class _WeekCalendarState extends State<_WeekCalendar> {
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

    return (targetHour * _calendarHourRowHeight).clamp(
      0,
      23 * _calendarHourRowHeight,
    );
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
                width: _weekTimeColumnWidth,
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
              child: SizedBox(
                height: _calendarHourRowHeight * 24,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _TimeAxis(width: _weekTimeColumnWidth),
                    ...days.map(
                      (day) => Expanded(
                        child: _TimedDayColumn(
                          date: day,
                          schedules: widget.schedules,
                          memberColors: widget.memberColors,
                          canManage: widget.canManage,
                          onTapDateTime: widget.onTapDate,
                          onTapSchedule: widget.onTapSchedule,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeAxis extends StatelessWidget {
  const _TimeAxis({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: _calendarHourRowHeight * 24,
      child: Stack(
        children: [
          for (var hour = 0; hour <= 23; hour++)
            Positioned(
              top: hour * _calendarHourRowHeight,
              left: 0,
              right: 0,
              height: _calendarHourRowHeight,
              child: Container(
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
            ),
        ],
      ),
    );
  }
}

class _TimedDayColumn extends StatelessWidget {
  const _TimedDayColumn({
    required this.date,
    required this.schedules,
    required this.memberColors,
    required this.canManage,
    required this.onTapDateTime,
    required this.onTapSchedule,
    this.showLeftBorder = false,
  });

  final DateTime date;
  final List<AppSchedule> schedules;
  final Map<String, MemberFilterColor> memberColors;
  final bool canManage;
  final ValueChanged<DateTime> onTapDateTime;
  final ValueChanged<AppSchedule> onTapSchedule;
  final bool showLeftBorder;

  @override
  Widget build(BuildContext context) {
    final layouts = _buildTimedScheduleLayouts(schedules, date);

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = constraints.maxWidth;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var hour = 0; hour <= 23; hour++)
              Positioned(
                top: hour * _calendarHourRowHeight,
                left: 0,
                right: 0,
                height: _calendarHourRowHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: canManage
                      ? () => onTapDateTime(
                          DateTime(date.year, date.month, date.day, hour),
                        )
                      : null,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        top: const BorderSide(color: Color(0xFFE5E5EA)),
                        right: const BorderSide(color: Color(0xFFE5E5EA)),
                        left: showLeftBorder
                            ? const BorderSide(color: Color(0xFFE5E5EA))
                            : BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
            ...layouts.map((layout) {
              final left = (layout.leftFraction * columnWidth) + 3;
              final width = (layout.widthFraction * columnWidth - 6)
                  .clamp(12.0, columnWidth)
                  .toDouble();
              final height = (layout.height - 4)
                  .clamp(24.0, layout.height)
                  .toDouble();

              return Positioned(
                top: layout.top + 2,
                left: left,
                width: width,
                height: height,
                child: _TimedScheduleBlock(
                  schedule: layout.schedule,
                  color: _scheduleMemberColor(layout.schedule, memberColors),
                  onTap: () => onTapSchedule(layout.schedule),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _TimedScheduleBlock extends StatelessWidget {
  const _TimedScheduleBlock({
    required this.schedule,
    required this.color,
    required this.onTap,
  });

  final AppSchedule schedule;
  final MemberFilterColor color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = MemberFilterColorStyle.from(color);

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onTap,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: style.background,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: style.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxHeight = constraints.maxHeight;
            final isNarrow = constraints.maxWidth < 38;
            final showMember = maxHeight >= 46 && !isNarrow;
            final titleLines = _timedScheduleTitleLines(
              height: maxHeight,
              showMember: showMember,
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _calendarTitleLabel(schedule.title),
                    maxLines: titleLines,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    style: TextStyle(
                      color: style.foreground,
                      fontSize: 9,
                      height: 1.08,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                if (showMember) ...[
                  const SizedBox(height: 2),
                  Text(
                    schedule.memberNickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: style.foreground,
                      fontSize: 8,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

int _timedScheduleTitleLines({
  required double height,
  required bool showMember,
}) {
  final usableHeight = showMember ? height - 18 : height - 8;
  final lineCount = (usableHeight / 10).floor();

  return lineCount.clamp(1, 6).toInt();
}

class _TimedScheduleLayout {
  const _TimedScheduleLayout({
    required this.schedule,
    required this.top,
    required this.height,
    required this.leftFraction,
    required this.widthFraction,
  });

  final AppSchedule schedule;
  final double top;
  final double height;
  final double leftFraction;
  final double widthFraction;
}

List<_TimedScheduleLayout> _buildTimedScheduleLayouts(
  List<AppSchedule> schedules,
  DateTime day,
) {
  final dayStart = _dateOnly(day);
  final dayEnd = dayStart.add(const Duration(days: 1));
  final daySchedules =
      schedules
          .where(
            (schedule) =>
                schedule.startsAt.isBefore(dayEnd) &&
                schedule.endsAt.isAfter(dayStart),
          )
          .toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  final layouts = <_TimedScheduleLayout>[];

  for (var index = 0; index < daySchedules.length;) {
    final group = <AppSchedule>[];
    var groupEnd = _scheduleEndInDay(daySchedules[index], dayEnd);

    while (index < daySchedules.length) {
      final schedule = daySchedules[index];
      final scheduleStart = _scheduleStartInDay(schedule, dayStart);

      if (group.isNotEmpty && !scheduleStart.isBefore(groupEnd)) {
        break;
      }

      group.add(schedule);
      final scheduleEnd = _scheduleEndInDay(schedule, dayEnd);
      if (scheduleEnd.isAfter(groupEnd)) {
        groupEnd = scheduleEnd;
      }
      index += 1;
    }

    layouts.addAll(_buildTimedScheduleGroupLayouts(group, dayStart, dayEnd));
  }

  return layouts;
}

List<_TimedScheduleLayout> _buildTimedScheduleGroupLayouts(
  List<AppSchedule> group,
  DateTime dayStart,
  DateTime dayEnd,
) {
  final columns = <DateTime>[];
  final columnBySchedule = <AppSchedule, int>{};

  for (final schedule in group) {
    final start = _scheduleStartInDay(schedule, dayStart);
    final end = _scheduleEndInDay(schedule, dayEnd);
    var columnIndex = columns.indexWhere(
      (columnEnd) => !start.isBefore(columnEnd),
    );

    if (columnIndex == -1) {
      columnIndex = columns.length;
      columns.add(end);
    } else {
      columns[columnIndex] = end;
    }

    columnBySchedule[schedule] = columnIndex;
  }

  final columnCount = columns.length.clamp(1, group.length).toInt();
  final widthFraction = 1 / columnCount;

  return group.map((schedule) {
    final start = _scheduleStartInDay(schedule, dayStart);
    final end = _scheduleEndInDay(schedule, dayEnd);
    final startMinutes = start.difference(dayStart).inMinutes;
    final durationMinutes = end
        .difference(start)
        .inMinutes
        .clamp(15, 24 * 60)
        .toInt();
    final columnIndex = columnBySchedule[schedule] ?? 0;

    return _TimedScheduleLayout(
      schedule: schedule,
      top: startMinutes / 60 * _calendarHourRowHeight,
      height: (durationMinutes / 60 * _calendarHourRowHeight)
          .clamp(28, _calendarHourRowHeight * 24)
          .toDouble(),
      leftFraction: columnIndex * widthFraction,
      widthFraction: widthFraction,
    );
  }).toList();
}

DateTime _scheduleStartInDay(AppSchedule schedule, DateTime dayStart) {
  if (schedule.startsAt.isBefore(dayStart)) {
    return dayStart;
  }

  return schedule.startsAt;
}

DateTime _scheduleEndInDay(AppSchedule schedule, DateTime dayEnd) {
  if (schedule.endsAt.isAfter(dayEnd)) {
    return dayEnd;
  }

  return schedule.endsAt;
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.monthStart,
    required this.schedules,
    required this.memberColors,
    required this.canManage,
    required this.onTapDate,
    required this.onTapSchedule,
  });

  final DateTime monthStart;
  final List<AppSchedule> schedules;
  final Map<String, MemberFilterColor> memberColors;
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
                memberColors: memberColors,
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
    required this.memberColors,
    required this.canManage,
    required this.isInCurrentMonth,
    required this.maxVisibleSchedules,
    required this.minHeight,
    required this.onTapDate,
    required this.onTapSchedule,
  });

  final DateTime date;
  final List<AppSchedule> schedules;
  final Map<String, MemberFilterColor> memberColors;
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
                  color: _scheduleMemberColor(schedule, memberColors),
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
    required this.color,
    required this.canManage,
    required this.onTap,
  });

  final AppSchedule schedule;
  final MemberFilterColor color;
  final bool canManage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = MemberFilterColorStyle.from(color);

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: canManage ? onTap : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: style.background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: style.border),
        ),
        child: Text(
          _calendarTitleLabel(schedule.title),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
          style: TextStyle(
            color: style.foreground,
            fontSize: 9,
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
                  icon: CupertinoIcons.building_2_fill,
                  label: '학교/학원',
                  value: schedule.educationProgramName ?? '선택 안 함',
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
    required this.educationPrograms,
    required this.initialDate,
    this.schedule,
  });

  final List<FamilyMember> members;
  final List<EducationProgram> educationPrograms;
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
  String? _educationProgramId;
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
    _educationProgramId = schedule?.educationProgramId;
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
      builder: (popupContext) => CupertinoActionSheet(
        title: const Text('가족 구성원'),
        actions: widget.members
            .map(
              (member) => CupertinoActionSheetAction(
                isDefaultAction: member.id == _familyMemberId,
                onPressed: () => Navigator.of(popupContext).pop(member.id),
                child: Text(member.userNickname),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: const Text('취소'),
        ),
      ),
    );

    if (selectedId != null) {
      setState(() {
        _familyMemberId = selectedId;
        if (!_educationProgramBelongsToMember(
          _educationProgramId,
          selectedId,
        )) {
          _educationProgramId = null;
        }
      });
    }
  }

  Future<void> _pickEducationProgram() async {
    final educationPrograms = _educationProgramsForSelectedMember();

    final selectedId = await showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: const Text('학교/학원 템플릿'),
        actions: [
          CupertinoActionSheetAction(
            isDefaultAction: _educationProgramId == null,
            onPressed: () =>
                Navigator.of(popupContext).pop(_educationProgramNoneValue),
            child: const Text('선택 안 함'),
          ),
          ...educationPrograms.map(
            (program) => CupertinoActionSheetAction(
              isDefaultAction: program.id == _educationProgramId,
              onPressed: () => Navigator.of(popupContext).pop(program.id),
              child: Text(program.name),
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: const Text('취소'),
        ),
      ),
    );

    if (!mounted || selectedId == null) {
      return;
    }

    setState(() {
      _educationProgramId = selectedId == _educationProgramNoneValue
          ? null
          : selectedId;
    });
  }

  List<EducationProgram> _educationProgramsForSelectedMember() {
    return widget.educationPrograms
        .where((program) => program.familyMemberId == _familyMemberId)
        .toList();
  }

  bool _educationProgramBelongsToMember(
    String? educationProgramId,
    String familyMemberId,
  ) {
    if (educationProgramId == null) {
      return true;
    }

    return widget.educationPrograms.any((program) {
      return program.id == educationProgramId &&
          program.familyMemberId == familyMemberId;
    });
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
      builder: (popupContext) => Container(
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
                      onPressed: () => Navigator.of(popupContext).pop(),
                      child: const Text('취소'),
                    ),
                    CupertinoButton(
                      onPressed: () => Navigator.of(popupContext).pop(selected),
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
        educationProgramId: _educationProgramId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedMember = widget.members.firstWhere(
      (member) => member.id == _familyMemberId,
      orElse: () => widget.members.first,
    );
    final selectedMemberEducationPrograms =
        _educationProgramsForSelectedMember();
    EducationProgram? selectedEducationProgram;
    for (final program in selectedMemberEducationPrograms) {
      if (program.id == _educationProgramId) {
        selectedEducationProgram = program;
        break;
      }
    }

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
                if (selectedMemberEducationPrograms.isNotEmpty) ...[
                  _FormDivider(),
                  _PickerRow(
                    label: '학교/학원',
                    value: selectedEducationProgram?.name ?? '선택 안 함',
                    onPressed: _pickEducationProgram,
                  ),
                ],
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
    required this.educationProgramId,
  });

  final String familyMemberId;
  final String title;
  final String? content;
  final DateTime startsAt;
  final DateTime endsAt;
  final DateTime? vehicleBoardingAt;
  final DateTime? vehicleDropoffAt;
  final String? educationProgramId;
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

Map<String, MemberFilterColor> _memberFilterColors(List<FamilyMember> members) {
  return {
    for (var index = 0; index < members.length; index++)
      members[index].id:
          MemberFilterColor.values[index % MemberFilterColor.values.length],
  };
}

MemberFilterColor _scheduleMemberColor(
  AppSchedule schedule,
  Map<String, MemberFilterColor> memberColors,
) {
  final familyMemberId = schedule.familyMemberId;

  if (familyMemberId == null) {
    return MemberFilterColor.gray;
  }

  return memberColors[familyMemberId] ?? MemberFilterColor.gray;
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
