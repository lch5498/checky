import 'package:flutter/cupertino.dart';

import '../../core/api_client.dart';
import '../../design_system/app_colors.dart';
import '../../shared/member_filter.dart';
import '../../shared/refreshable_scroll_view.dart';

const _weekdayLabels = ['일', '월', '화', '수', '목', '금', '토'];
const _weekdayPickerOrder = [1, 2, 3, 4, 5, 6, 0];
const _weekOfMonthLabels = {1: '첫째주', 2: '둘째주', 3: '셋째주', 4: '넷째주'};

class EducationScreen extends StatefulWidget {
  const EducationScreen({
    super.key,
    required this.family,
    required this.families,
    required this.sessionToken,
    required this.onSelectFamily,
  });

  final AppFamily family;
  final List<AppFamily> families;
  final String sessionToken;
  final Future<void> Function(AppFamily family) onSelectFamily;

  @override
  State<EducationScreen> createState() => _EducationScreenState();
}

class _EducationScreenState extends State<EducationScreen> {
  final _apiClient = ApiClient();

  late AppFamily _family;
  EducationProgramDashboard? _dashboard;
  final Set<String> _hiddenMemberIds = <String>{};
  String? _message;
  bool _isLoading = true;
  bool _isApplyingCalendarChanges = false;

  List<EducationProgram> get _filteredPrograms {
    final dashboard = _dashboard;

    if (dashboard == null) {
      return const [];
    }

    if (_hiddenMemberIds.isEmpty) {
      return dashboard.programs;
    }

    return dashboard.programs
        .where(
          (program) =>
              program.familyMemberId == null ||
              !_hiddenMemberIds.contains(program.familyMemberId),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _family = widget.family;
    _loadPrograms();
  }

  @override
  void didUpdateWidget(covariant EducationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.family.id != widget.family.id) {
      _family = widget.family;
      _hiddenMemberIds.clear();
      _loadPrograms();
    }
  }

  Future<void> _loadPrograms() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final dashboard = await _apiClient.getEducationProgramDashboard(
        widget.sessionToken,
        familyId: _family.id,
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

  void _toggleMemberFilter(String memberId) {
    setState(() {
      if (_hiddenMemberIds.contains(memberId)) {
        _hiddenMemberIds.remove(memberId);
      } else {
        _hiddenMemberIds.add(memberId);
      }
    });
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
    await _loadPrograms();
  }

  Future<void> _openProgramForm({EducationProgram? program}) async {
    final dashboard = _dashboard;

    if (dashboard == null || dashboard.members.isEmpty) {
      setState(() {
        _message = '학교/학원 일정을 등록할 가족 구성원이 필요합니다.';
      });
      return;
    }

    final formResult = await Navigator.of(context)
        .push<_EducationProgramFormResult>(
          CupertinoPageRoute(
            fullscreenDialog: true,
            builder: (_) => _EducationProgramFormScreen(
              members: dashboard.members,
              program: program,
            ),
          ),
        );

    if (formResult == null) {
      return;
    }

    if (formResult.shouldDelete) {
      if (program != null) {
        await _deleteProgram(
          program,
          calendarApplyScope: formResult.calendarApplyScope,
          confirmBeforeDelete: false,
        );
      }
      return;
    }

    final input = formResult.input;

    if (input == null) {
      return;
    }

    await _runTask(() async {
      final shouldShowCalendarOverlay = program != null;

      if (shouldShowCalendarOverlay && mounted) {
        setState(() {
          _isApplyingCalendarChanges = true;
        });
      }

      try {
        final result = program == null
            ? await _apiClient.createEducationProgram(
                widget.sessionToken,
                familyId: _family.id,
                input: input,
                calendarApplyScope: formResult.calendarApplyScope,
              )
            : await _apiClient.updateEducationProgram(
                widget.sessionToken,
                familyId: _family.id,
                programId: program.id,
                input: input,
                calendarApplyScope: formResult.calendarApplyScope,
              );

        await _loadPrograms();

        if (mounted) {
          setState(() {
            _message = '${result.generatedScheduleCount}개 일정이 캘린더에 반영되었습니다.';
          });
        }
      } finally {
        if (shouldShowCalendarOverlay && mounted) {
          setState(() {
            _isApplyingCalendarChanges = false;
          });
        }
      }
    });
  }

  Future<void> _deleteProgram(
    EducationProgram program, {
    required CalendarApplyScope calendarApplyScope,
    bool confirmBeforeDelete = true,
  }) async {
    if (confirmBeforeDelete) {
      final confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('학교/학원 삭제'),
          content: Text('${program.name}와 연결된 캘린더 일정을 삭제할까요?'),
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
    }

    await _runTask(() async {
      await _apiClient.deleteEducationProgram(
        widget.sessionToken,
        familyId: _family.id,
        programId: program.id,
        calendarApplyScope: calendarApplyScope,
      );
      await _loadPrograms();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = _dashboard;
    final programs = _filteredPrograms;
    final memberColors = _memberFilterColors(dashboard?.members ?? const []);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: _FeatureFamilyTitle(
          family: _family,
          canSwitch: widget.families.length > 1,
          onPressed: _switchFamily,
        ),
        trailing: dashboard?.canManage == true
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(32, 32),
                onPressed: _isLoading ? null : () => _openProgramForm(),
                child: const Icon(CupertinoIcons.plus),
              )
            : null,
      ),
      child: Stack(
        children: [
          SafeArea(
            child: RefreshableScrollView(
              onRefresh: _loadPrograms,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                if (_message != null) ...[
                  _InlineMessage(message: _message!),
                  const SizedBox(height: 12),
                ],
                if (_isLoading && dashboard == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(child: CupertinoActivityIndicator()),
                  )
                else if (dashboard != null && dashboard.members.isNotEmpty) ...[
                  _EducationFilterCard(
                    members: dashboard.members,
                    hiddenMemberIds: _hiddenMemberIds,
                    memberColors: memberColors,
                    onToggleMember: _toggleMemberFilter,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_isLoading && dashboard == null)
                  const SizedBox.shrink()
                else if ((dashboard?.programs ?? const []).isEmpty)
                  _EmptyPrograms(canManage: dashboard?.canManage ?? false)
                else if (programs.isEmpty)
                  const _EmptyFilteredPrograms()
                else
                  ...programs.map(
                    (program) => _EducationProgramCard(
                      program: program,
                      memberColor: _programMemberColor(program, memberColors),
                      canManage: dashboard?.canManage ?? false,
                      onEdit: () => _openProgramForm(program: program),
                    ),
                  ),
              ],
            ),
          ),
          if (_isApplyingCalendarChanges)
            const _FullScreenProgressOverlay(message: '캘린더에 반영 중입니다'),
        ],
      ),
    );
  }
}

class _FullScreenProgressOverlay extends StatelessWidget {
  const _FullScreenProgressOverlay({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: CupertinoColors.systemBackground
                .resolveFrom(context)
                .withValues(alpha: 0.78),
          ),
          child: Center(
            child: Container(
              width: 210,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
              decoration: BoxDecoration(
                color: CupertinoColors.secondarySystemBackground.resolveFrom(
                  context,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: CupertinoColors.separator.resolveFrom(context),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CupertinoActivityIndicator(radius: 15),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.darkTextPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EducationProgramCard extends StatelessWidget {
  const _EducationProgramCard({
    required this.program,
    required this.memberColor,
    required this.canManage,
    required this.onEdit,
  });

  final EducationProgram program;
  final MemberFilterColor memberColor;
  final bool canManage;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheduleSummaries = _educationScheduleSummaries(program);

    final content = Container(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.darkBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MemberNameIcon(name: program.memberNickname, color: memberColor),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(
                    program.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.darkTextPrimary,
                      fontSize: 18,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _EducationScheduleGroup(
            dateText:
                '${_dateText(program.startsOn)} - ${_dateText(program.endsOn)}',
            scheduleSummaries: scheduleSummaries,
          ),
        ],
      ),
    );

    if (!canManage) {
      return content;
    }

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onEdit,
      child: content,
    );
  }
}

class _MemberNameIcon extends StatelessWidget {
  const _MemberNameIcon({required this.name, required this.color});

  final String name;
  final MemberFilterColor color;

  @override
  Widget build(BuildContext context) {
    final style = MemberFilterColorStyle.from(color);

    return Container(
      width: 42,
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: style.border),
      ),
      child: Center(
        child: Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: style.foreground,
            fontSize: 11,
            height: 1.05,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _EducationScheduleGroup extends StatelessWidget {
  const _EducationScheduleGroup({
    required this.dateText,
    required this.scheduleSummaries,
  });

  final String dateText;
  final List<_EducationScheduleSummary> scheduleSummaries;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dateText,
            textAlign: TextAlign.left,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.darkTextPrimary,
              fontSize: 13,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final summary in scheduleSummaries)
                _EducationScheduleChip(summary: summary),
            ],
          ),
        ],
      ),
    );
  }
}

class _EducationScheduleChip extends StatelessWidget {
  const _EducationScheduleChip({required this.summary});

  final _EducationScheduleSummary summary;

  @override
  Widget build(BuildContext context) {
    final vehicleText = summary.vehicleText;

    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            summary.title,
            style: const TextStyle(
              color: AppColors.darkTextPrimary,
              fontSize: 13,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          if (vehicleText != null) ...[
            const SizedBox(height: 4),
            Text(
              vehicleText,
              style: const TextStyle(
                color: AppColors.darkTextSecondary,
                fontSize: 12,
                height: 1.15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EducationFilterCard extends StatelessWidget {
  const _EducationFilterCard({
    required this.members,
    required this.hiddenMemberIds,
    required this.memberColors,
    required this.onToggleMember,
  });

  final List<FamilyMember> members;
  final Set<String> hiddenMemberIds;
  final Map<String, MemberFilterColor> memberColors;
  final ValueChanged<String> onToggleMember;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.darkBorder)),
      ),
      child: MemberFilterBar(
        members: members,
        hiddenMemberIds: hiddenMemberIds,
        memberColors: memberColors,
        onToggleMember: onToggleMember,
      ),
    );
  }
}

class _EducationProgramFormResult {
  const _EducationProgramFormResult._({
    this.input,
    required this.calendarApplyScope,
    this.shouldDelete = false,
  });

  const _EducationProgramFormResult.save(
    EducationProgramInput input,
    CalendarApplyScope calendarApplyScope,
  ) : this._(input: input, calendarApplyScope: calendarApplyScope);

  const _EducationProgramFormResult.delete(
    CalendarApplyScope calendarApplyScope,
  ) : this._(shouldDelete: true, calendarApplyScope: calendarApplyScope);

  final EducationProgramInput? input;
  final CalendarApplyScope calendarApplyScope;
  final bool shouldDelete;
}

class _EducationProgramFormScreen extends StatefulWidget {
  const _EducationProgramFormScreen({
    required this.members,
    required this.program,
  });

  final List<FamilyMember> members;
  final EducationProgram? program;

  @override
  State<_EducationProgramFormScreen> createState() =>
      _EducationProgramFormScreenState();
}

class _EducationProgramFormScreenState
    extends State<_EducationProgramFormScreen> {
  late String _familyMemberId;
  late final TextEditingController _nameController;
  late DateTime _startsOn;
  late DateTime _endsOn;
  late EducationRecurrenceType _recurrenceType;
  late final Map<int, _DayRule> _dayRules;
  late final Map<int, _MonthlyRule> _monthlyRules;
  String? _message;

  @override
  void initState() {
    super.initState();
    final program = widget.program;
    final now = DateTime.now();
    _familyMemberId = program?.familyMemberId ?? widget.members.first.id;
    _nameController = TextEditingController(text: program?.name);
    _startsOn = _dateOnly(program?.startsOn ?? now);
    _endsOn = _dateOnly(program?.endsOn ?? now.add(const Duration(days: 30)));
    _recurrenceType = program?.recurrenceType ?? EducationRecurrenceType.weekly;
    _dayRules = {
      for (var weekday = 0; weekday < 7; weekday++)
        weekday: _DayRule(
          enabled: false,
          startsAt: const TimeOfDayValue(hour: 15, minute: 0),
          endsAt: const TimeOfDayValue(hour: 16, minute: 0),
          vehicleBoardingTime: null,
          vehicleDropoffTime: null,
        ),
    };
    _monthlyRules = {
      for (var weekOfMonth = 1; weekOfMonth <= 4; weekOfMonth++)
        weekOfMonth: _MonthlyRule(
          enabled: false,
          weekday: 1,
          startsAt: const TimeOfDayValue(hour: 15, minute: 0),
          endsAt: const TimeOfDayValue(hour: 16, minute: 0),
          vehicleBoardingTime: null,
          vehicleDropoffTime: null,
        ),
    };

    for (final schedule in program?.weeklySchedules ?? const []) {
      _dayRules[schedule.weekday] = _DayRule(
        enabled: true,
        startsAt: schedule.startsAt,
        endsAt: schedule.endsAt,
        vehicleBoardingTime: schedule.vehicleBoardingTime,
        vehicleDropoffTime: schedule.vehicleDropoffTime,
      );
    }

    for (final schedule in program?.monthlySchedules ?? const []) {
      _monthlyRules[schedule.weekOfMonth] = _MonthlyRule(
        enabled: true,
        weekday: schedule.weekday,
        startsAt: schedule.startsAt,
        endsAt: schedule.endsAt,
        vehicleBoardingTime: schedule.vehicleBoardingTime,
        vehicleDropoffTime: schedule.vehicleDropoffTime,
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
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
      });
    }
  }

  Future<void> _pickMonthlyWeekday(int weekOfMonth) async {
    final rule = _monthlyRules[weekOfMonth]!;
    final selectedWeekday = await showCupertinoModalPopup<int>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text(_weekOfMonthLabels[weekOfMonth] ?? '$weekOfMonth주차'),
        actions: _weekdayPickerOrder
            .map(
              (weekday) => CupertinoActionSheetAction(
                isDefaultAction: weekday == rule.weekday,
                onPressed: () => Navigator.of(popupContext).pop(weekday),
                child: Text('${_weekdayLabels[weekday]}요일'),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: const Text('취소'),
        ),
      ),
    );

    if (selectedWeekday == null) {
      return;
    }

    setState(() {
      _monthlyRules[weekOfMonth] = rule.copyWith(weekday: selectedWeekday);
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await _showDatePicker(isStart ? _startsOn : _endsOn);

    if (picked == null) {
      return;
    }

    setState(() {
      if (isStart) {
        _startsOn = picked;

        if (_endsOn.isBefore(_startsOn)) {
          _endsOn = _startsOn;
        }
      } else {
        _endsOn = picked;
      }
    });
  }

  Future<void> _pickRuleTime(int weekday, {required bool isStart}) async {
    final rule = _dayRules[weekday]!;
    final picked = await _showTimePicker(isStart ? rule.startsAt : rule.endsAt);

    if (picked == null) {
      return;
    }

    setState(() {
      _dayRules[weekday] = rule.copyWith(
        startsAt: isStart ? picked : rule.startsAt,
        endsAt: isStart ? rule.endsAt : picked,
      );
    });
  }

  Future<void> _pickRuleVehicleTime(
    int weekday, {
    required bool isBoarding,
  }) async {
    final rule = _dayRules[weekday]!;
    final current = isBoarding
        ? rule.vehicleBoardingTime
        : rule.vehicleDropoffTime;
    final picked = await _showTimePicker(
      current ?? const TimeOfDayValue(hour: 8, minute: 0),
    );

    if (picked == null) {
      return;
    }

    setState(() {
      final currentRule = _dayRules[weekday]!;
      if (isBoarding) {
        _dayRules[weekday] = currentRule.copyWith(
          vehicleBoardingTime: _OptionalTimeUpdate(picked),
        );
      } else {
        _dayRules[weekday] = currentRule.copyWith(
          vehicleDropoffTime: _OptionalTimeUpdate(picked),
        );
      }
    });
  }

  void _clearRuleVehicleTime(int weekday, {required bool isBoarding}) {
    setState(() {
      final rule = _dayRules[weekday]!;
      _dayRules[weekday] = isBoarding
          ? rule.copyWith(vehicleBoardingTime: const _OptionalTimeUpdate(null))
          : rule.copyWith(vehicleDropoffTime: const _OptionalTimeUpdate(null));
    });
  }

  Future<void> _pickMonthlyRuleTime(
    int weekOfMonth, {
    required bool isStart,
  }) async {
    final rule = _monthlyRules[weekOfMonth]!;
    final picked = await _showTimePicker(isStart ? rule.startsAt : rule.endsAt);

    if (picked == null) {
      return;
    }

    setState(() {
      _monthlyRules[weekOfMonth] = rule.copyWith(
        startsAt: isStart ? picked : rule.startsAt,
        endsAt: isStart ? rule.endsAt : picked,
      );
    });
  }

  Future<void> _pickMonthlyRuleVehicleTime(
    int weekOfMonth, {
    required bool isBoarding,
  }) async {
    final rule = _monthlyRules[weekOfMonth]!;
    final current = isBoarding
        ? rule.vehicleBoardingTime
        : rule.vehicleDropoffTime;
    final picked = await _showTimePicker(
      current ?? const TimeOfDayValue(hour: 8, minute: 0),
    );

    if (picked == null) {
      return;
    }

    setState(() {
      final currentRule = _monthlyRules[weekOfMonth]!;
      if (isBoarding) {
        _monthlyRules[weekOfMonth] = currentRule.copyWith(
          vehicleBoardingTime: _OptionalTimeUpdate(picked),
        );
      } else {
        _monthlyRules[weekOfMonth] = currentRule.copyWith(
          vehicleDropoffTime: _OptionalTimeUpdate(picked),
        );
      }
    });
  }

  void _clearMonthlyRuleVehicleTime(
    int weekOfMonth, {
    required bool isBoarding,
  }) {
    setState(() {
      final rule = _monthlyRules[weekOfMonth]!;
      _monthlyRules[weekOfMonth] = isBoarding
          ? rule.copyWith(vehicleBoardingTime: const _OptionalTimeUpdate(null))
          : rule.copyWith(vehicleDropoffTime: const _OptionalTimeUpdate(null));
    });
  }

  void _copyPreviousEnabledRule(int weekday) {
    final sourceWeekday = _previousEnabledWeekday(weekday);

    if (sourceWeekday == null) {
      return;
    }

    setState(() {
      final source = _dayRules[sourceWeekday]!;
      _dayRules[weekday] = source.copyWith(enabled: true);
    });
  }

  String? _copyPreviousLabel(int weekday) {
    final sourceWeekday = _previousEnabledWeekday(weekday);

    if (sourceWeekday == null) {
      return null;
    }

    return '${_weekdayLabels[sourceWeekday]}요일 일정 복사';
  }

  int? _previousEnabledWeekday(int weekday) {
    for (var index = weekday - 1; index >= 0; index--) {
      if (_dayRules[index]?.enabled == true) {
        return index;
      }
    }

    return null;
  }

  Future<DateTime?> _showDatePicker(DateTime initial) {
    final minimumDate = _minimumEducationProgramDate();
    final maximumDate = _maximumEducationProgramDate();
    var selected = _clampDate(initial, minimumDate, maximumDate);

    return showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (popupContext) => _PickerSheet(
        onCancel: () => Navigator.of(popupContext).pop(),
        onDone: () => Navigator.of(popupContext).pop(_dateOnly(selected)),
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.date,
          minimumDate: minimumDate,
          maximumDate: maximumDate,
          initialDateTime: selected,
          onDateTimeChanged: (value) {
            selected = value;
          },
        ),
      ),
    );
  }

  Future<TimeOfDayValue?> _showTimePicker(TimeOfDayValue initial) {
    var selected = initial;

    return showCupertinoModalPopup<TimeOfDayValue>(
      context: context,
      builder: (popupContext) => _PickerSheet(
        onCancel: () => Navigator.of(popupContext).pop(),
        onDone: () => Navigator.of(popupContext).pop(selected),
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.time,
          initialDateTime: DateTime(2026, 1, 1, initial.hour, initial.minute),
          onDateTimeChanged: (value) {
            selected = TimeOfDayValue(hour: value.hour, minute: value.minute);
          },
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final weeklySchedules = _dayRules.entries
        .where((entry) => entry.value.enabled)
        .map(
          (entry) => EducationWeeklySchedule(
            weekday: entry.key,
            startsAt: entry.value.startsAt,
            endsAt: entry.value.endsAt,
            vehicleBoardingTime: entry.value.vehicleBoardingTime,
            vehicleDropoffTime: entry.value.vehicleDropoffTime,
          ),
        )
        .toList();
    final monthlySchedules = _monthlyRules.entries
        .where((entry) => entry.value.enabled)
        .map(
          (entry) => EducationMonthlySchedule(
            weekOfMonth: entry.key,
            weekday: entry.value.weekday,
            startsAt: entry.value.startsAt,
            endsAt: entry.value.endsAt,
            vehicleBoardingTime: entry.value.vehicleBoardingTime,
            vehicleDropoffTime: entry.value.vehicleDropoffTime,
          ),
        )
        .toList();

    if (name.isEmpty) {
      setState(() {
        _message = '이름을 입력해 주세요.';
      });
      return;
    }

    if (_endsOn.isBefore(_startsOn)) {
      setState(() {
        _message = '종료 날짜는 시작 날짜 이후여야 합니다.';
      });
      return;
    }

    if (!_isInEducationProgramDateRange(_startsOn) ||
        !_isInEducationProgramDateRange(_endsOn)) {
      setState(() {
        _message = '시작일과 종료일은 오늘 기준 1년 전부터 1년 후까지만 선택할 수 있습니다.';
      });
      return;
    }

    if (_recurrenceType == EducationRecurrenceType.weekly &&
        weeklySchedules.isEmpty) {
      setState(() {
        _message = '하나 이상의 요일 일정을 선택해 주세요.';
      });
      return;
    }

    if (_recurrenceType == EducationRecurrenceType.monthly &&
        monthlySchedules.isEmpty) {
      setState(() {
        _message = '하나 이상의 월간 일정을 선택해 주세요.';
      });
      return;
    }

    final ruleTimes = [
      if (_recurrenceType == EducationRecurrenceType.weekly)
        ...weeklySchedules.map(
          (schedule) => _RuleTimeCheck(
            label: '${_weekdayLabels[schedule.weekday]}요일',
            startsAt: schedule.startsAt,
            endsAt: schedule.endsAt,
          ),
        ),
      if (_recurrenceType == EducationRecurrenceType.monthly)
        ...monthlySchedules.map(
          (schedule) => _RuleTimeCheck(
            label:
                '${_weekOfMonthLabels[schedule.weekOfMonth]} ${_weekdayLabels[schedule.weekday]}요일',
            startsAt: schedule.startsAt,
            endsAt: schedule.endsAt,
          ),
        ),
    ];

    for (final schedule in ruleTimes) {
      if (_minutes(schedule.endsAt) < _minutes(schedule.startsAt)) {
        setState(() {
          _message = '${schedule.label} 종료 시각을 확인해 주세요.';
        });
        return;
      }
    }

    final calendarApplyScope = await _pickCalendarApplyScope(
      title: '캘린더 반영 범위',
      message: '학교/학원 일정을 캘린더에 어느 범위로 반영할까요?',
      allLabel: '전체 기간에 반영',
      futureLabel: '오늘 이후 일정에 반영',
    );

    if (!mounted || calendarApplyScope == null) {
      return;
    }

    Navigator.of(context).pop(
      _EducationProgramFormResult.save(
        EducationProgramInput(
          familyMemberId: _familyMemberId,
          name: name,
          startsOn: _startsOn,
          endsOn: _endsOn,
          recurrenceType: _recurrenceType,
          weeklySchedules: _recurrenceType == EducationRecurrenceType.weekly
              ? weeklySchedules
              : const [],
          monthlySchedules: _recurrenceType == EducationRecurrenceType.monthly
              ? monthlySchedules
              : const [],
        ),
        calendarApplyScope,
      ),
    );
  }

  Future<CalendarApplyScope?> _pickCalendarApplyScope({
    required String title,
    required String message,
    required String allLabel,
    required String futureLabel,
  }) {
    return showCupertinoModalPopup<CalendarApplyScope>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text(title),
        message: Text(message),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.of(popupContext).pop(CalendarApplyScope.all),
            child: Text(allLabel),
          ),
          CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () =>
                Navigator.of(popupContext).pop(CalendarApplyScope.future),
            child: Text(futureLabel),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: const Text('취소'),
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final program = widget.program;

    if (program == null) {
      return;
    }

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('학교/학원 삭제'),
        content: Text('${program.name}와 연결된 캘린더 일정을 삭제할까요?'),
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

    if (!mounted || confirmed != true) {
      return;
    }

    final calendarApplyScope = await _pickCalendarApplyScope(
      title: '캘린더 삭제 범위',
      message: '연결된 캘린더 일정을 어느 범위로 삭제할까요?',
      allLabel: '전체 기간 일정 삭제',
      futureLabel: '오늘 이후 일정 삭제',
    );

    if (!mounted || calendarApplyScope == null) {
      return;
    }

    Navigator.of(
      context,
    ).pop(_EducationProgramFormResult.delete(calendarApplyScope));
  }

  @override
  Widget build(BuildContext context) {
    final selectedMember = widget.members.firstWhere(
      (member) => member.id == _familyMemberId,
      orElse: () => widget.members.first,
    );

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.program == null ? '학교/학원 등록' : '학교/학원 수정'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 32),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 32),
          onPressed: _submit,
          child: const Text('저장'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
          children: [
            if (_message != null) ...[
              _InlineMessage(message: _message!),
              const SizedBox(height: 12),
            ],
            _FormSection(
              children: [
                _TextFieldRow(
                  label: '이름',
                  controller: _nameController,
                  placeholder: '예: 영어학원',
                ),
                _PickerRow(
                  label: '구성원',
                  value: selectedMember.userNickname,
                  onPressed: _pickMember,
                ),
                _PickerRow(
                  label: '시작 날짜',
                  value: _dateText(_startsOn),
                  onPressed: () => _pickDate(isStart: true),
                ),
                _PickerRow(
                  label: '종료 날짜',
                  value: _dateText(_endsOn),
                  onPressed: () => _pickDate(isStart: false),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _FormSection(
              children: [
                _RecurrenceTypeRow(
                  value: _recurrenceType,
                  onChanged: (value) {
                    setState(() {
                      _recurrenceType = value;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_recurrenceType == EducationRecurrenceType.weekly)
              _FormSection(
                children: [
                  for (var weekday = 0; weekday < 7; weekday++)
                    _WeekdayRuleRow(
                      weekday: weekday,
                      rule: _dayRules[weekday]!,
                      copyLabel: _copyPreviousLabel(weekday),
                      onToggle: (value) {
                        setState(() {
                          _dayRules[weekday] = _dayRules[weekday]!.copyWith(
                            enabled: value,
                          );
                        });
                      },
                      onPickStart: () => _pickRuleTime(weekday, isStart: true),
                      onPickEnd: () => _pickRuleTime(weekday, isStart: false),
                      onPickBoarding: () =>
                          _pickRuleVehicleTime(weekday, isBoarding: true),
                      onPickDropoff: () =>
                          _pickRuleVehicleTime(weekday, isBoarding: false),
                      onClearBoarding: () =>
                          _clearRuleVehicleTime(weekday, isBoarding: true),
                      onClearDropoff: () =>
                          _clearRuleVehicleTime(weekday, isBoarding: false),
                      onCopyPrevious: () => _copyPreviousEnabledRule(weekday),
                    ),
                ],
              )
            else
              _FormSection(
                children: [
                  for (var weekOfMonth = 1; weekOfMonth <= 4; weekOfMonth++)
                    _MonthlyRuleRow(
                      weekOfMonth: weekOfMonth,
                      rule: _monthlyRules[weekOfMonth]!,
                      onToggle: (value) {
                        setState(() {
                          _monthlyRules[weekOfMonth] =
                              _monthlyRules[weekOfMonth]!.copyWith(
                                enabled: value,
                              );
                        });
                      },
                      onPickWeekday: () => _pickMonthlyWeekday(weekOfMonth),
                      onPickStart: () =>
                          _pickMonthlyRuleTime(weekOfMonth, isStart: true),
                      onPickEnd: () =>
                          _pickMonthlyRuleTime(weekOfMonth, isStart: false),
                      onPickBoarding: () => _pickMonthlyRuleVehicleTime(
                        weekOfMonth,
                        isBoarding: true,
                      ),
                      onPickDropoff: () => _pickMonthlyRuleVehicleTime(
                        weekOfMonth,
                        isBoarding: false,
                      ),
                      onClearBoarding: () => _clearMonthlyRuleVehicleTime(
                        weekOfMonth,
                        isBoarding: true,
                      ),
                      onClearDropoff: () => _clearMonthlyRuleVehicleTime(
                        weekOfMonth,
                        isBoarding: false,
                      ),
                    ),
                ],
              ),
            if (widget.program != null) ...[
              const SizedBox(height: 18),
              _DeleteProgramButton(onPressed: _confirmDelete),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeleteProgramButton extends StatelessWidget {
  const _DeleteProgramButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        color: AppColors.darkSurfaceElevated,
        borderRadius: BorderRadius.circular(12),
        onPressed: onPressed,
        child: const Text(
          '학교/학원 삭제',
          style: TextStyle(
            color: CupertinoColors.destructiveRed,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _PickerSheet extends StatelessWidget {
  const _PickerSheet({
    required this.onCancel,
    required this.onDone,
    required this.child,
  });

  final VoidCallback onCancel;
  final VoidCallback onDone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
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
                  CupertinoButton(onPressed: onCancel, child: const Text('취소')),
                  CupertinoButton(onPressed: onDone, child: const Text('완료')),
                ],
              ),
            ),
            Expanded(child: child),
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
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(children: children),
    );
  }
}

class _TextFieldRow extends StatelessWidget {
  const _TextFieldRow({
    required this.label,
    required this.controller,
    required this.placeholder,
  });

  final String label;
  final TextEditingController controller;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          Expanded(
            child: CupertinoTextField(
              controller: controller,
              placeholder: placeholder,
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
              decoration: const BoxDecoration(),
              style: const TextStyle(fontSize: 16, letterSpacing: 0),
            ),
          ),
        ],
      ),
    );
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
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      onPressed: onPressed,
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: CupertinoColors.systemBlue,
                fontSize: 15,
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

class _RecurrenceTypeRow extends StatelessWidget {
  const _RecurrenceTypeRow({required this.value, required this.onChanged});

  final EducationRecurrenceType value;
  final ValueChanged<EducationRecurrenceType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          const SizedBox(
            width: 82,
            child: Text(
              '반복',
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          Expanded(
            child: CupertinoSlidingSegmentedControl<EducationRecurrenceType>(
              groupValue: value,
              children: const {
                EducationRecurrenceType.weekly: Padding(
                  padding: EdgeInsets.symmetric(vertical: 7),
                  child: Text('주'),
                ),
                EducationRecurrenceType.monthly: Padding(
                  padding: EdgeInsets.symmetric(vertical: 7),
                  child: Text('월'),
                ),
              },
              onValueChanged: (nextValue) {
                if (nextValue != null) {
                  onChanged(nextValue);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekdayRuleRow extends StatelessWidget {
  const _WeekdayRuleRow({
    required this.weekday,
    required this.rule,
    required this.copyLabel,
    required this.onToggle,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onPickBoarding,
    required this.onPickDropoff,
    required this.onClearBoarding,
    required this.onClearDropoff,
    required this.onCopyPrevious,
  });

  final int weekday;
  final _DayRule rule;
  final String? copyLabel;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onPickBoarding;
  final VoidCallback onPickDropoff;
  final VoidCallback onClearBoarding;
  final VoidCallback onClearDropoff;
  final VoidCallback onCopyPrevious;

  @override
  Widget build(BuildContext context) {
    final canCopy = rule.enabled && copyLabel != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  _weekdayLabels[weekday],
                  style: const TextStyle(
                    color: AppColors.darkTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              CupertinoSwitch(value: rule.enabled, onChanged: onToggle),
              const Spacer(),
              if (copyLabel != null)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: canCopy ? onCopyPrevious : null,
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: canCopy
                          ? AppColors.darkPrimarySoft
                          : AppColors.darkSurfaceElevated,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: canCopy
                            ? AppColors.darkBorder
                            : AppColors.darkBorder,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.arrow_down_doc,
                          size: 15,
                          color: canCopy
                              ? CupertinoColors.systemBlue
                              : CupertinoColors.systemGrey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          copyLabel!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: canCopy
                                ? CupertinoColors.systemBlue
                                : CupertinoColors.systemGrey,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _RuleTimeLine(
            label: '일정',
            startValue: rule.startsAt.toApiString(),
            endValue: rule.endsAt.toApiString(),
            onPickStart: rule.enabled ? onPickStart : null,
            onPickEnd: rule.enabled ? onPickEnd : null,
          ),
          const SizedBox(height: 6),
          _RuleTimeLine(
            label: '차량',
            startValue: rule.vehicleBoardingTime?.toApiString() ?? '탑승',
            endValue: rule.vehicleDropoffTime?.toApiString() ?? '하차',
            onPickStart: rule.enabled ? onPickBoarding : null,
            onPickEnd: rule.enabled ? onPickDropoff : null,
            onClearStart: rule.vehicleBoardingTime != null
                ? onClearBoarding
                : null,
            onClearEnd: rule.vehicleDropoffTime != null ? onClearDropoff : null,
          ),
        ],
      ),
    );
  }
}

class _MonthlyRuleRow extends StatelessWidget {
  const _MonthlyRuleRow({
    required this.weekOfMonth,
    required this.rule,
    required this.onToggle,
    required this.onPickWeekday,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onPickBoarding,
    required this.onPickDropoff,
    required this.onClearBoarding,
    required this.onClearDropoff,
  });

  final int weekOfMonth;
  final _MonthlyRule rule;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickWeekday;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onPickBoarding;
  final VoidCallback onPickDropoff;
  final VoidCallback onClearBoarding;
  final VoidCallback onClearDropoff;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 58,
                child: Text(
                  _weekOfMonthLabels[weekOfMonth] ?? '$weekOfMonth주',
                  style: const TextStyle(
                    color: AppColors.darkTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              CupertinoSwitch(value: rule.enabled, onChanged: onToggle),
              const Spacer(),
              SizedBox(
                height: 34,
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  color: AppColors.darkSurfaceElevated,
                  borderRadius: BorderRadius.circular(9),
                  onPressed: rule.enabled ? onPickWeekday : null,
                  child: Text(
                    '${_weekdayLabels[rule.weekday]}요일',
                    style: TextStyle(
                      color: rule.enabled
                          ? CupertinoColors.systemBlue
                          : CupertinoColors.systemGrey,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _RuleTimeLine(
            label: '일정',
            startValue: rule.startsAt.toApiString(),
            endValue: rule.endsAt.toApiString(),
            onPickStart: rule.enabled ? onPickStart : null,
            onPickEnd: rule.enabled ? onPickEnd : null,
          ),
          const SizedBox(height: 6),
          _RuleTimeLine(
            label: '차량',
            startValue: rule.vehicleBoardingTime?.toApiString() ?? '탑승',
            endValue: rule.vehicleDropoffTime?.toApiString() ?? '하차',
            onPickStart: rule.enabled ? onPickBoarding : null,
            onPickEnd: rule.enabled ? onPickDropoff : null,
            onClearStart: rule.vehicleBoardingTime != null
                ? onClearBoarding
                : null,
            onClearEnd: rule.vehicleDropoffTime != null ? onClearDropoff : null,
          ),
        ],
      ),
    );
  }
}

class _RuleTimeLine extends StatelessWidget {
  const _RuleTimeLine({
    required this.label,
    required this.startValue,
    required this.endValue,
    required this.onPickStart,
    required this.onPickEnd,
    this.onClearStart,
    this.onClearEnd,
  });

  final String label;
  final String startValue;
  final String endValue;
  final VoidCallback? onPickStart;
  final VoidCallback? onPickEnd;
  final VoidCallback? onClearStart;
  final VoidCallback? onClearEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.darkTextSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
        _SmallTimeButton(value: startValue, onPressed: onPickStart),
        if (onClearStart != null)
          _ClearTimeButton(onPressed: onClearStart!)
        else
          const SizedBox(width: 6),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '-',
            style: TextStyle(color: AppColors.darkTextSecondary),
          ),
        ),
        _SmallTimeButton(value: endValue, onPressed: onPickEnd),
        if (onClearEnd != null)
          _ClearTimeButton(onPressed: onClearEnd!)
        else
          const SizedBox(width: 6),
      ],
    );
  }
}

class _ClearTimeButton extends StatelessWidget {
  const _ClearTimeButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(28, 28),
      onPressed: onPressed,
      child: const Icon(CupertinoIcons.xmark_circle_fill, size: 16),
    );
  }
}

class _SmallTimeButton extends StatelessWidget {
  const _SmallTimeButton({required this.value, required this.onPressed});

  final String value;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        color: AppColors.darkSurfaceElevated,
        borderRadius: BorderRadius.circular(9),
        onPressed: onPressed,
        child: Text(
          value,
          style: TextStyle(
            color: onPressed == null
                ? CupertinoColors.systemGrey
                : CupertinoColors.systemBlue,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _DayRule {
  const _DayRule({
    required this.enabled,
    required this.startsAt,
    required this.endsAt,
    required this.vehicleBoardingTime,
    required this.vehicleDropoffTime,
  });

  final bool enabled;
  final TimeOfDayValue startsAt;
  final TimeOfDayValue endsAt;
  final TimeOfDayValue? vehicleBoardingTime;
  final TimeOfDayValue? vehicleDropoffTime;

  _DayRule copyWith({
    bool? enabled,
    TimeOfDayValue? startsAt,
    TimeOfDayValue? endsAt,
    _OptionalTimeUpdate? vehicleBoardingTime,
    _OptionalTimeUpdate? vehicleDropoffTime,
  }) {
    return _DayRule(
      enabled: enabled ?? this.enabled,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      vehicleBoardingTime: vehicleBoardingTime == null
          ? this.vehicleBoardingTime
          : vehicleBoardingTime.value,
      vehicleDropoffTime: vehicleDropoffTime == null
          ? this.vehicleDropoffTime
          : vehicleDropoffTime.value,
    );
  }
}

class _MonthlyRule {
  const _MonthlyRule({
    required this.enabled,
    required this.weekday,
    required this.startsAt,
    required this.endsAt,
    required this.vehicleBoardingTime,
    required this.vehicleDropoffTime,
  });

  final bool enabled;
  final int weekday;
  final TimeOfDayValue startsAt;
  final TimeOfDayValue endsAt;
  final TimeOfDayValue? vehicleBoardingTime;
  final TimeOfDayValue? vehicleDropoffTime;

  _MonthlyRule copyWith({
    bool? enabled,
    int? weekday,
    TimeOfDayValue? startsAt,
    TimeOfDayValue? endsAt,
    _OptionalTimeUpdate? vehicleBoardingTime,
    _OptionalTimeUpdate? vehicleDropoffTime,
  }) {
    return _MonthlyRule(
      enabled: enabled ?? this.enabled,
      weekday: weekday ?? this.weekday,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      vehicleBoardingTime: vehicleBoardingTime == null
          ? this.vehicleBoardingTime
          : vehicleBoardingTime.value,
      vehicleDropoffTime: vehicleDropoffTime == null
          ? this.vehicleDropoffTime
          : vehicleDropoffTime.value,
    );
  }
}

class _RuleTimeCheck {
  const _RuleTimeCheck({
    required this.label,
    required this.startsAt,
    required this.endsAt,
  });

  final String label;
  final TimeOfDayValue startsAt;
  final TimeOfDayValue endsAt;
}

class _OptionalTimeUpdate {
  const _OptionalTimeUpdate(this.value);

  final TimeOfDayValue? value;
}

class _FeatureFamilyTitle extends StatelessWidget {
  const _FeatureFamilyTitle({
    required this.family,
    required this.canSwitch,
    required this.onPressed,
  });

  final AppFamily family;
  final bool canSwitch;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (!canSwitch) {
      return Text(
        family.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          inherit: false,
          color: AppColors.darkTextPrimary,
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
              family.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                inherit: false,
                color: AppColors.darkTextPrimary,
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

class _EmptyPrograms extends StatelessWidget {
  const _EmptyPrograms({required this.canManage});

  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Text(
        canManage ? '등록된 학교/학원이 없습니다. + 버튼으로 추가해 주세요.' : '등록된 학교/학원이 없습니다.',
        style: const TextStyle(
          color: AppColors.darkTextSecondary,
          fontSize: 15,
          height: 1.35,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _EmptyFilteredPrograms extends StatelessWidget {
  const _EmptyFilteredPrograms();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: const Text(
        '선택한 구성원의 학교/학원이 없습니다.',
        style: TextStyle(
          color: AppColors.darkTextSecondary,
          fontSize: 15,
          height: 1.35,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: AppColors.darkDanger,
          fontSize: 14,
          height: 1.35,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _minimumEducationProgramDate() {
  final today = _dateOnly(DateTime.now());

  return DateTime(today.year - 1, today.month, today.day);
}

DateTime _maximumEducationProgramDate() {
  final today = _dateOnly(DateTime.now());

  return DateTime(today.year + 1, today.month, today.day);
}

bool _isInEducationProgramDateRange(DateTime value) {
  final date = _dateOnly(value);
  final minimumDate = _minimumEducationProgramDate();
  final maximumDate = _maximumEducationProgramDate();

  return !date.isBefore(minimumDate) && !date.isAfter(maximumDate);
}

DateTime _clampDate(
  DateTime value,
  DateTime minimumDate,
  DateTime maximumDate,
) {
  final date = _dateOnly(value);

  if (date.isBefore(minimumDate)) {
    return minimumDate;
  }

  if (date.isAfter(maximumDate)) {
    return maximumDate;
  }

  return date;
}

String _dateText(DateTime value) {
  return '${value.year}.${_twoDigits(value.month)}.${_twoDigits(value.day)}';
}

Map<String, MemberFilterColor> _memberFilterColors(List<FamilyMember> members) {
  return {
    for (var index = 0; index < members.length; index++)
      members[index].id:
          MemberFilterColor.values[index % MemberFilterColor.values.length],
  };
}

MemberFilterColor _programMemberColor(
  EducationProgram program,
  Map<String, MemberFilterColor> memberColors,
) {
  final familyMemberId = program.familyMemberId;

  if (familyMemberId == null) {
    return MemberFilterColor.gray;
  }

  return memberColors[familyMemberId] ?? MemberFilterColor.gray;
}

List<_EducationScheduleSummary> _educationScheduleSummaries(
  EducationProgram program,
) {
  return switch (program.recurrenceType) {
    EducationRecurrenceType.monthly => _monthlyScheduleSummaries(
      program.monthlySchedules,
    ),
    EducationRecurrenceType.weekly => _weeklyScheduleSummaries(
      program.weeklySchedules,
    ),
  };
}

List<_EducationScheduleSummary> _weeklyScheduleSummaries(
  List<EducationWeeklySchedule> schedules,
) {
  final sorted = [...schedules]..sort((a, b) => a.weekday.compareTo(b.weekday));
  final groupedSchedules = <String, List<EducationWeeklySchedule>>{};
  final groupOrder = <String>[];

  for (final schedule in sorted) {
    final key = _scheduleTimeKey(schedule);
    groupedSchedules
        .putIfAbsent(key, () {
          groupOrder.add(key);
          return [];
        })
        .add(schedule);
  }

  return groupOrder.map((key) {
    final group = groupedSchedules[key]!;

    return _EducationScheduleSummary.fromWeeklySchedules(
      weekdays: group.map((schedule) => schedule.weekday).toList(),
      schedule: group.first,
    );
  }).toList();
}

List<_EducationScheduleSummary> _monthlyScheduleSummaries(
  List<EducationMonthlySchedule> schedules,
) {
  final sorted = [...schedules]
    ..sort((a, b) => a.weekOfMonth.compareTo(b.weekOfMonth));
  final groupedSchedules = <String, List<EducationMonthlySchedule>>{};
  final groupOrder = <String>[];

  for (final schedule in sorted) {
    final key = _monthlyScheduleTimeKey(schedule);
    groupedSchedules
        .putIfAbsent(key, () {
          groupOrder.add(key);
          return [];
        })
        .add(schedule);
  }

  return groupOrder.map((key) {
    final group = groupedSchedules[key]!;

    return _EducationScheduleSummary.fromMonthlySchedules(
      schedules: group,
      schedule: group.first,
    );
  }).toList();
}

String _scheduleTimeKey(EducationWeeklySchedule schedule) {
  return [
    schedule.startsAt.toApiString(),
    schedule.endsAt.toApiString(),
    schedule.vehicleBoardingTime?.toApiString() ?? '',
    schedule.vehicleDropoffTime?.toApiString() ?? '',
  ].join('|');
}

String _monthlyScheduleTimeKey(EducationMonthlySchedule schedule) {
  return [
    schedule.startsAt.toApiString(),
    schedule.endsAt.toApiString(),
    schedule.vehicleBoardingTime?.toApiString() ?? '',
    schedule.vehicleDropoffTime?.toApiString() ?? '',
  ].join('|');
}

String _weekdayGroupText(List<int> weekdays) {
  final sorted = [...weekdays]..sort();
  final parts = <String>[];

  for (var index = 0; index < sorted.length;) {
    final start = sorted[index];
    var end = start;

    while (index + 1 < sorted.length && sorted[index + 1] == end + 1) {
      index += 1;
      end = sorted[index];
    }

    parts.add(
      start == end
          ? _weekdayLabels[start]
          : '${_weekdayLabels[start]}~${_weekdayLabels[end]}',
    );
    index += 1;
  }

  return parts.join(',');
}

class _EducationScheduleSummary {
  const _EducationScheduleSummary({
    required this.title,
    required this.vehicleText,
  });

  final String title;
  final String? vehicleText;

  factory _EducationScheduleSummary.fromWeeklySchedules({
    required List<int> weekdays,
    required EducationWeeklySchedule schedule,
  }) {
    final boardingTime = schedule.vehicleBoardingTime?.toApiString();
    final dropoffTime = schedule.vehicleDropoffTime?.toApiString();
    final vehicleParts = [
      if (boardingTime != null) '승차 $boardingTime',
      if (dropoffTime != null) '하차 $dropoffTime',
    ];

    return _EducationScheduleSummary(
      title:
          '${_weekdayGroupText(weekdays)} ${schedule.startsAt.toApiString()}-${schedule.endsAt.toApiString()}',
      vehicleText: vehicleParts.isEmpty ? null : vehicleParts.join(' · '),
    );
  }

  factory _EducationScheduleSummary.fromMonthlySchedules({
    required List<EducationMonthlySchedule> schedules,
    required EducationMonthlySchedule schedule,
  }) {
    final boardingTime = schedule.vehicleBoardingTime?.toApiString();
    final dropoffTime = schedule.vehicleDropoffTime?.toApiString();
    final vehicleParts = [
      if (boardingTime != null) '승차 $boardingTime',
      if (dropoffTime != null) '하차 $dropoffTime',
    ];
    final scheduleText = schedules
        .map(
          (entry) =>
              '${_weekOfMonthLabels[entry.weekOfMonth]} ${_weekdayLabels[entry.weekday]}',
        )
        .join(',');

    return _EducationScheduleSummary(
      title:
          '매월 $scheduleText ${schedule.startsAt.toApiString()}-${schedule.endsAt.toApiString()}',
      vehicleText: vehicleParts.isEmpty ? null : vehicleParts.join(' · '),
    );
  }
}

int _minutes(TimeOfDayValue value) => value.hour * 60 + value.minute;

String _twoDigits(int value) => value.toString().padLeft(2, '0');
