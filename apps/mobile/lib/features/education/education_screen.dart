import 'package:flutter/cupertino.dart';

import '../../core/api_client.dart';
import '../../shared/member_filter.dart';

const _weekdayLabels = ['일', '월', '화', '수', '목', '금', '토'];

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

    final input = await Navigator.of(context).push<EducationProgramInput>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (_) => _EducationProgramFormScreen(
          members: dashboard.members,
          program: program,
        ),
      ),
    );

    if (input == null) {
      return;
    }

    await _runTask(() async {
      final result = program == null
          ? await _apiClient.createEducationProgram(
              widget.sessionToken,
              familyId: _family.id,
              input: input,
            )
          : await _apiClient.updateEducationProgram(
              widget.sessionToken,
              familyId: _family.id,
              programId: program.id,
              input: input,
            );

      await _loadPrograms();

      if (mounted) {
        setState(() {
          _message = '${result.generatedScheduleCount}개 일정이 캘린더에 반영되었습니다.';
        });
      }
    });
  }

  Future<void> _deleteProgram(EducationProgram program) async {
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

    await _runTask(() async {
      await _apiClient.deleteEducationProgram(
        widget.sessionToken,
        familyId: _family.id,
        programId: program.id,
      );
      await _loadPrograms();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = _dashboard;
    final programs = _filteredPrograms;

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
      child: SafeArea(
        child: ListView(
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
                (program) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _EducationProgramCard(
                    program: program,
                    canManage: dashboard?.canManage ?? false,
                    onEdit: () => _openProgramForm(program: program),
                    onDelete: () => _deleteProgram(program),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EducationProgramCard extends StatelessWidget {
  const _EducationProgramCard({
    required this.program,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  final EducationProgram program;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheduleSummaries = _weeklyScheduleSummaries(program.weeklySchedules);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA)),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF4F2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  CupertinoIcons.book_fill,
                  color: CupertinoColors.systemTeal,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      program.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF111111),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _ProgramMetaPill(
                          icon: CupertinoIcons.person_fill,
                          label: program.memberNickname,
                        ),
                        _ProgramMetaPill(
                          icon: CupertinoIcons.calendar,
                          label:
                              '${_dateText(program.startsOn)} - ${_dateText(program.endsOn)}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (canManage) ...[
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(32, 32),
                  onPressed: onEdit,
                  child: const Icon(CupertinoIcons.pencil, size: 20),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(32, 32),
                  onPressed: onDelete,
                  child: const Icon(
                    CupertinoIcons.delete,
                    color: CupertinoColors.destructiveRed,
                    size: 20,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final summary in scheduleSummaries)
                _WeeklyScheduleChip(summary: summary),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgramMetaPill extends StatelessWidget {
  const _ProgramMetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF6E6E73)),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF6E6E73),
                fontSize: 12,
                height: 1.1,
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

class _WeeklyScheduleChip extends StatelessWidget {
  const _WeeklyScheduleChip({required this.summary});

  final _WeeklyScheduleSummary summary;

  @override
  Widget build(BuildContext context) {
    final vehicleText = summary.vehicleText;

    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD6E8E4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${summary.weekdayText} ${summary.startsAt}-${summary.endsAt}',
            style: const TextStyle(
              color: Color(0xFF111111),
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
                color: Color(0xFF6E6E73),
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
    required this.onToggleMember,
  });

  final List<FamilyMember> members;
  final Set<String> hiddenMemberIds;
  final ValueChanged<String> onToggleMember;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: MemberFilterBar(
        members: members,
        hiddenMemberIds: hiddenMemberIds,
        onToggleMember: onToggleMember,
      ),
    );
  }
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
  late final Map<int, _DayRule> _dayRules;
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

    for (final schedule in program?.weeklySchedules ?? const []) {
      _dayRules[schedule.weekday] = _DayRule(
        enabled: true,
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

  void _submit() {
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

    if (weeklySchedules.isEmpty) {
      setState(() {
        _message = '하나 이상의 요일 일정을 선택해 주세요.';
      });
      return;
    }

    for (final schedule in weeklySchedules) {
      if (_minutes(schedule.endsAt) < _minutes(schedule.startsAt)) {
        setState(() {
          _message = '${_weekdayLabels[schedule.weekday]}요일 종료 시각을 확인해 주세요.';
        });
        return;
      }
    }

    Navigator.of(context).pop(
      EducationProgramInput(
        familyMemberId: _familyMemberId,
        name: name,
        startsOn: _startsOn,
        endsOn: _endsOn,
        weeklySchedules: weeklySchedules,
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
            ),
          ],
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
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E5EA)),
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
                color: Color(0xFF111111),
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
                color: Color(0xFF111111),
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
                    color: Color(0xFF111111),
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
                          ? const Color(0xFFEAF3FF)
                          : const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: canCopy
                            ? const Color(0xFFCDE2FF)
                            : const Color(0xFFE5E5EA),
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
              color: Color(0xFF6E6E73),
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
          child: Text('-', style: TextStyle(color: Color(0xFF6E6E73))),
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
        color: const Color(0xFFF2F2F7),
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
              family.name,
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

class _EmptyPrograms extends StatelessWidget {
  const _EmptyPrograms({required this.canManage});

  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Text(
        canManage ? '등록된 학교/학원이 없습니다. + 버튼으로 추가해 주세요.' : '등록된 학교/학원이 없습니다.',
        style: const TextStyle(
          color: Color(0xFF6E6E73),
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
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: const Text(
        '선택한 구성원의 학교/학원이 없습니다.',
        style: TextStyle(
          color: Color(0xFF6E6E73),
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
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
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

List<_WeeklyScheduleSummary> _weeklyScheduleSummaries(
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

    return _WeeklyScheduleSummary.fromSchedules(
      weekdays: group.map((schedule) => schedule.weekday).toList(),
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

class _WeeklyScheduleSummary {
  const _WeeklyScheduleSummary({
    required this.weekdayText,
    required this.startsAt,
    required this.endsAt,
    required this.vehicleText,
  });

  final String weekdayText;
  final String startsAt;
  final String endsAt;
  final String? vehicleText;

  factory _WeeklyScheduleSummary.fromSchedules({
    required List<int> weekdays,
    required EducationWeeklySchedule schedule,
  }) {
    final boardingTime = schedule.vehicleBoardingTime?.toApiString();
    final dropoffTime = schedule.vehicleDropoffTime?.toApiString();
    final vehicleParts = [
      if (boardingTime != null) '승차 $boardingTime',
      if (dropoffTime != null) '하차 $dropoffTime',
    ];

    return _WeeklyScheduleSummary(
      weekdayText: _weekdayGroupText(weekdays),
      startsAt: schedule.startsAt.toApiString(),
      endsAt: schedule.endsAt.toApiString(),
      vehicleText: vehicleParts.isEmpty ? null : vehicleParts.join(' · '),
    );
  }
}

int _minutes(TimeOfDayValue value) => value.hour * 60 + value.minute;

String _twoDigits(int value) => value.toString().padLeft(2, '0');
