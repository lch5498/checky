import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../design_system/app_colors.dart';
import '../../shared/alert_offset_picker.dart';
import '../../shared/member_filter.dart';
import '../../shared/refreshable_scroll_view.dart';
import '../../shared/schedule_section_switcher.dart';

const _weekdayLabels = ['일', '월', '화', '수', '목', '금', '토'];
const _weekdayPickerOrder = [1, 2, 3, 4, 5, 6, 0];
const _weekOfMonthLabels = {1: '첫째주', 2: '둘째주', 3: '셋째주', 4: '넷째주'};
const _monthlyDefaultDays = [1, 15, 20, 25];
const _phoneContactLabelOptions = ['선생님', '데스크', '직접입력'];
const _phoneChannel = MethodChannel('checky/phone');
const _contactChannel = MethodChannel('checky/contacts');

class EducationScreen extends StatefulWidget {
  const EducationScreen({
    super.key,
    required this.family,
    required this.families,
    required this.sessionToken,
    required this.onSelectFamily,
    this.selectedScheduleSection,
    this.onScheduleSectionChanged,
  });

  final AppFamily family;
  final List<AppFamily> families;
  final String sessionToken;
  final Future<void> Function(AppFamily family) onSelectFamily;
  final ScheduleSection? selectedScheduleSection;
  final ValueChanged<ScheduleSection>? onScheduleSectionChanged;

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

  Future<void> _callPhoneNumber(EducationProgramPhoneContact contact) async {
    final phoneNumber = contact.phoneNumber.trim();

    if (phoneNumber.isEmpty) {
      return;
    }

    try {
      await _phoneChannel.invokeMethod<void>('dial', {
        'phoneNumber': phoneNumber,
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = '전화 앱을 열 수 없습니다. 번호를 확인해 주세요.';
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
        title: Text('그룹 전환'),
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
          child: Text('취소'),
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
        _message = '반복 일정을 등록할 그룹 구성원이 필요합니다.';
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
      final shouldShowCalendarOverlay =
          program != null && formResult.affectsCalendar;

      if (shouldShowCalendarOverlay && mounted) {
        setState(() {
          _isApplyingCalendarChanges = true;
        });
      }

      try {
        var generatedScheduleCount = 0;

        if (program == null) {
          final memberIds = formResult.memberIds.isEmpty
              ? [input.familyMemberId]
              : formResult.memberIds;

          for (final memberId in memberIds) {
            final result = await _apiClient.createEducationProgram(
              widget.sessionToken,
              familyId: _family.id,
              input: input.copyWithFamilyMemberId(memberId),
              calendarApplyScope: formResult.calendarApplyScope,
            );
            generatedScheduleCount += result.generatedScheduleCount;
          }
        } else {
          final result = await _apiClient.updateEducationProgram(
            widget.sessionToken,
            familyId: _family.id,
            programId: program.id,
            input: input,
            calendarApplyScope: formResult.calendarApplyScope,
          );
          generatedScheduleCount = result.generatedScheduleCount;
        }

        await _loadPrograms();

        if (mounted) {
          setState(() {
            _message = generatedScheduleCount == 0
                ? '반복 일정 정보가 저장되었습니다.'
                : '$generatedScheduleCount개 일정이 캘린더에 반영되었습니다.';
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
          title: Text('반복 일정 삭제'),
          content: Text('${program.name}와 연결된 캘린더 일정을 삭제할까요?'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('취소'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('삭제'),
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
                if (widget.selectedScheduleSection != null &&
                    widget.onScheduleSectionChanged != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ScheduleSectionSwitcher(
                      selectedSection: widget.selectedScheduleSection!,
                      onSectionChanged: widget.onScheduleSectionChanged!,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (_message != null) ...[
                  _InlineMessage(message: _message!),
                  const SizedBox(height: 12),
                ],
                if (_isLoading && dashboard == null)
                  Padding(
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
                      onCallPhone: _callPhoneNumber,
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
                    style: TextStyle(
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
    required this.onCallPhone,
  });

  final EducationProgram program;
  final MemberFilterColor memberColor;
  final bool canManage;
  final VoidCallback onEdit;
  final ValueChanged<EducationProgramPhoneContact> onCallPhone;

  @override
  Widget build(BuildContext context) {
    final scheduleSummaries = _educationScheduleSummaries(program);

    final content = Container(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 16),
      decoration: BoxDecoration(
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
                    style: TextStyle(
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
          if (program.phoneContacts.isNotEmpty) ...[
            const SizedBox(height: 10),
            _EducationPhoneContactWrap(
              contacts: program.phoneContacts,
              onCallPhone: onCallPhone,
            ),
          ],
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: style.foreground,
            fontSize: 10,
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
        color: AppColors.darkSurfaceElevated,
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
            style: TextStyle(
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
            style: TextStyle(
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
              style: TextStyle(
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

class _EducationPhoneContactWrap extends StatelessWidget {
  const _EducationPhoneContactWrap({
    required this.contacts,
    required this.onCallPhone,
  });

  final List<EducationProgramPhoneContact> contacts;
  final ValueChanged<EducationProgramPhoneContact> onCallPhone;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final contact in contacts)
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: () => onCallPhone(contact),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.darkSurfaceElevated,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.phone_fill,
                    size: 13,
                    color: AppColors.darkPrimary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${contact.label} ${contact.phoneNumber}',
                    style: TextStyle(
                      color: AppColors.darkTextPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
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
      decoration: BoxDecoration(
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
    this.memberIds = const [],
    required this.calendarApplyScope,
    required this.affectsCalendar,
    this.shouldDelete = false,
  });

  const _EducationProgramFormResult.save(
    EducationProgramInput input,
    CalendarApplyScope calendarApplyScope, {
    required List<String> memberIds,
    required bool affectsCalendar,
  }) : this._(
         input: input,
         memberIds: memberIds,
         calendarApplyScope: calendarApplyScope,
         affectsCalendar: affectsCalendar,
       );

  const _EducationProgramFormResult.delete(
    CalendarApplyScope calendarApplyScope,
  ) : this._(
        shouldDelete: true,
        calendarApplyScope: calendarApplyScope,
        affectsCalendar: true,
      );

  final EducationProgramInput? input;
  final List<String> memberIds;
  final CalendarApplyScope calendarApplyScope;
  final bool affectsCalendar;
  final bool shouldDelete;
}

enum _PhoneContactAddMode { contact, manual }

enum _MonthlyRuleMode { weekday, dayOfMonth }

class _PhoneContactDraft {
  _PhoneContactDraft({
    required this.label,
    String phoneNumber = '',
    String customLabel = '',
  }) : phoneController = TextEditingController(text: phoneNumber),
       customLabelController = TextEditingController(text: customLabel);

  factory _PhoneContactDraft.fromContact(EducationProgramPhoneContact contact) {
    final hasDefaultLabel = _phoneContactLabelOptions
        .where((label) => label != '직접입력')
        .contains(contact.label);

    return _PhoneContactDraft(
      label: hasDefaultLabel ? contact.label : '직접입력',
      phoneNumber: contact.phoneNumber,
      customLabel: hasDefaultLabel ? '' : contact.label,
    );
  }

  String label;
  final TextEditingController phoneController;
  final TextEditingController customLabelController;

  void dispose() {
    phoneController.dispose();
    customLabelController.dispose();
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
  late Set<String> _selectedMemberIds;
  late final TextEditingController _nameController;
  late DateTime _startsOn;
  late DateTime _endsOn;
  late EducationRecurrenceType _recurrenceType;
  late _MonthlyRuleMode _monthlyRuleMode;
  late final Map<int, _DayRule> _dayRules;
  late final Map<int, _MonthlyRule> _monthlyRules;
  late final List<_PhoneContactDraft> _phoneContacts;
  int? _alertOffsetMinutes;
  String? _message;

  @override
  void initState() {
    super.initState();
    final program = widget.program;
    final now = DateTime.now();
    _familyMemberId = program?.familyMemberId ?? widget.members.first.id;
    _selectedMemberIds = program == null ? <String>{} : {_familyMemberId};
    _nameController = TextEditingController(text: program?.name);
    _startsOn = _dateOnly(program?.startsOn ?? now);
    _endsOn = _dateOnly(program?.endsOn ?? now.add(const Duration(days: 30)));
    _recurrenceType = program?.recurrenceType ?? EducationRecurrenceType.weekly;
    _monthlyRuleMode =
        (program?.monthlySchedules ?? const []).any(
          (schedule) => schedule.dayOfMonth != null,
        )
        ? _MonthlyRuleMode.dayOfMonth
        : _MonthlyRuleMode.weekday;
    _alertOffsetMinutes = program?.alertOffsetMinutes;
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
          dayOfMonth: _monthlyDefaultDays[weekOfMonth - 1],
          weekday: 1,
          startsAt: const TimeOfDayValue(hour: 15, minute: 0),
          endsAt: const TimeOfDayValue(hour: 16, minute: 0),
          vehicleBoardingTime: null,
          vehicleDropoffTime: null,
        ),
    };
    _phoneContacts = [
      for (final contact in program?.phoneContacts ?? const [])
        _PhoneContactDraft.fromContact(contact),
    ];

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
        dayOfMonth:
            schedule.dayOfMonth ??
            _monthlyDefaultDays[schedule.weekOfMonth - 1],
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
    for (final contact in _phoneContacts) {
      contact.dispose();
    }
    super.dispose();
  }

  Future<void> _pickMember() async {
    if (widget.program == null) {
      await _pickMembers();
      return;
    }

    final selectedId = await showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text('그룹 구성원'),
        actions: widget.members
            .map(
              (member) => CupertinoActionSheetAction(
                isDefaultAction: member.id == _familyMemberId,
                onPressed: () => Navigator.of(popupContext).pop(member.id),
                child: Text(member.nickname),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: Text('취소'),
        ),
      ),
    );

    if (selectedId != null) {
      setState(() {
        _familyMemberId = selectedId;
        _selectedMemberIds = {selectedId};
      });
    }
  }

  Future<void> _pickMembers() async {
    final nextSelectedIds = Set<String>.from(_selectedMemberIds);
    final confirmed = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (popupContext) => StatefulBuilder(
        builder: (popupContext, setPopupState) => CupertinoActionSheet(
          title: Text('구성원 선택'),
          message: Text('등록할 구성원을 선택해 주세요.'),
          actions: [
            for (final member in widget.members)
              CupertinoActionSheetAction(
                onPressed: () {
                  setPopupState(() {
                    if (nextSelectedIds.contains(member.id)) {
                      nextSelectedIds.remove(member.id);
                    } else {
                      nextSelectedIds.add(member.id);
                    }
                  });
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      nextSelectedIds.contains(member.id)
                          ? CupertinoIcons.check_mark_circled_solid
                          : CupertinoIcons.circle,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        member.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            CupertinoActionSheetAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(popupContext).pop(true),
              child: Text('선택 완료'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(popupContext).pop(false),
            child: Text('취소'),
          ),
        ),
      ),
    );

    if (confirmed == true) {
      setState(() {
        _selectedMemberIds = nextSelectedIds;
        if (nextSelectedIds.isNotEmpty) {
          _familyMemberId = nextSelectedIds.first;
        }
      });
    }
  }

  String _selectedMemberLabel() {
    final selectedMembers = widget.members
        .where((member) => _selectedMemberIds.contains(member.id))
        .toList();

    if (selectedMembers.isEmpty) {
      return '구성원 선택';
    }

    if (selectedMembers.length == 1) {
      return selectedMembers.first.nickname;
    }

    return selectedMembers.map((member) => member.nickname).join(', ');
  }

  Future<void> _addPhoneContact() async {
    if (!_canAddPhoneContact()) {
      return;
    }

    final mode = await showCupertinoModalPopup<_PhoneContactAddMode>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text('전화번호 추가'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.of(popupContext).pop(_PhoneContactAddMode.contact),
            child: Text('연락처 불러오기'),
          ),
          CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () =>
                Navigator.of(popupContext).pop(_PhoneContactAddMode.manual),
            child: Text('직접입력'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: Text('취소'),
        ),
      ),
    );

    if (!mounted || mode == null) {
      return;
    }

    switch (mode) {
      case _PhoneContactAddMode.contact:
        await _importPhoneContact();
      case _PhoneContactAddMode.manual:
        setState(() {
          _phoneContacts.add(_PhoneContactDraft(label: '선생님'));
        });
    }
  }

  bool _canAddPhoneContact() {
    if (_phoneContacts.length < 10) {
      return true;
    }

    setState(() {
      _message = '전화번호는 최대 10개까지 등록할 수 있습니다.';
    });
    return false;
  }

  Future<void> _importPhoneContact() async {
    if (!_canAddPhoneContact()) {
      return;
    }

    try {
      final result = await _contactChannel.invokeMapMethod<String, Object?>(
        'pickPhoneContact',
      );

      if (!mounted || result == null) {
        return;
      }

      final phoneNumber = (result['phoneNumber'] as String? ?? '').trim();
      if (phoneNumber.isEmpty) {
        setState(() {
          _message = '선택한 연락처에 전화번호가 없습니다.';
        });
        return;
      }

      setState(() {
        _phoneContacts.add(
          _PhoneContactDraft(label: '선생님', phoneNumber: phoneNumber),
        );
      });
    } on PlatformException catch (error) {
      if (mounted && error.code != 'cancelled') {
        setState(() {
          _message = '연락처를 불러올 수 없습니다. 직접 입력해 주세요.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = '연락처를 불러올 수 없습니다. 직접 입력해 주세요.';
        });
      }
    }
  }

  void _removePhoneContact(int index) {
    setState(() {
      final removed = _phoneContacts.removeAt(index);
      removed.dispose();
    });
  }

  Future<void> _pickPhoneContactLabel(int index) async {
    final contact = _phoneContacts[index];
    final selected = await showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text('전화번호 구분'),
        actions: _phoneContactLabelOptions
            .map(
              (label) => CupertinoActionSheetAction(
                isDefaultAction: label == contact.label,
                onPressed: () => Navigator.of(popupContext).pop(label),
                child: Text(label),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: Text('취소'),
        ),
      ),
    );

    if (selected == null) {
      return;
    }

    setState(() {
      contact.label = selected;
    });
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
          child: Text('취소'),
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

  Future<void> _pickMonthlyDay(int weekOfMonth) async {
    final rule = _monthlyRules[weekOfMonth]!;
    final selectedDay = await showCupertinoModalPopup<int>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: const Text('매월 날짜'),
        actions: [
          for (var day = 1; day <= 31; day++)
            CupertinoActionSheetAction(
              isDefaultAction: day == rule.dayOfMonth,
              onPressed: () => Navigator.of(popupContext).pop(day),
              child: Text('매월 $day일'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: const Text('취소'),
        ),
      ),
    );

    if (selectedDay == null) {
      return;
    }

    if (_isMonthlyDayInUse(selectedDay, exceptWeekOfMonth: weekOfMonth)) {
      setState(() {
        _message = '이미 선택한 날짜입니다.';
      });
      return;
    }

    setState(() {
      _monthlyRules[weekOfMonth] = rule.copyWith(dayOfMonth: selectedDay);
    });
  }

  bool _isMonthlyDayInUse(int dayOfMonth, {required int exceptWeekOfMonth}) {
    return _monthlyRules.entries.any(
      (entry) =>
          entry.key != exceptWeekOfMonth &&
          entry.value.enabled &&
          entry.value.dayOfMonth == dayOfMonth,
    );
  }

  List<int> _visibleMonthlyRuleKeys() {
    if (_monthlyRuleMode != _MonthlyRuleMode.dayOfMonth) {
      return _monthlyRules.keys.toList();
    }

    final enabledKeys = _monthlyRules.entries
        .where((entry) => entry.value.enabled)
        .map((entry) => entry.key)
        .toList();

    return enabledKeys.isEmpty ? const [1] : enabledKeys;
  }

  void _selectMonthlyRuleMode(_MonthlyRuleMode mode) {
    setState(() {
      _monthlyRuleMode = mode;

      if (mode == _MonthlyRuleMode.dayOfMonth &&
          !_monthlyRules.values.any((rule) => rule.enabled)) {
        _monthlyRules[1] = _monthlyRules[1]!.copyWith(enabled: true);
      }
    });
  }

  void _addMonthlyDayRule() {
    MapEntry<int, _MonthlyRule>? nextEntry;
    for (final entry in _monthlyRules.entries) {
      if (!entry.value.enabled) {
        nextEntry = entry;
        break;
      }
    }

    if (nextEntry == null) {
      setState(() {
        _message = '특정일은 최대 4개까지 추가할 수 있습니다.';
      });
      return;
    }

    final selectedEntry = nextEntry;
    final defaultDay = selectedEntry.value.dayOfMonth ?? 1;
    final dayOfMonth =
        _isMonthlyDayInUse(defaultDay, exceptWeekOfMonth: selectedEntry.key)
        ? _firstAvailableMonthlyDay(selectedEntry.key)
        : defaultDay;

    setState(() {
      _monthlyRules[selectedEntry.key] = selectedEntry.value.copyWith(
        enabled: true,
        dayOfMonth: dayOfMonth,
      );
    });
  }

  int _firstAvailableMonthlyDay(int exceptWeekOfMonth) {
    for (var day = 1; day <= 31; day++) {
      if (!_isMonthlyDayInUse(day, exceptWeekOfMonth: exceptWeekOfMonth)) {
        return day;
      }
    }

    return 1;
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

  Future<void> _pickAlertOffset() async {
    final picked = await pickAlertOffset(
      context,
      currentValue: _alertOffsetMinutes,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _alertOffsetMinutes = picked;
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

    return showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (popupContext) => _DateInputSheet(
        initial: _clampDate(initial, minimumDate, maximumDate),
        minimumDate: minimumDate,
        maximumDate: maximumDate,
        onCancel: () => Navigator.of(popupContext).pop(),
        onDone: (value) => Navigator.of(popupContext).pop(value),
      ),
    );
  }

  Future<TimeOfDayValue?> _showTimePicker(TimeOfDayValue initial) {
    return showCupertinoModalPopup<TimeOfDayValue>(
      context: context,
      builder: (popupContext) => _TimeInputSheet(
        initial: initial,
        onCancel: () => Navigator.of(popupContext).pop(),
        onDone: (value) => Navigator.of(popupContext).pop(value),
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
            dayOfMonth: _monthlyRuleMode == _MonthlyRuleMode.dayOfMonth
                ? entry.value.dayOfMonth
                : null,
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

    if (widget.program == null && _selectedMemberIds.isEmpty) {
      await _showMissingMembersAlert();
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
            label: schedule.dayOfMonth == null
                ? '${_weekOfMonthLabels[schedule.weekOfMonth]} ${_weekdayLabels[schedule.weekday]}요일'
                : '매월 ${schedule.dayOfMonth}일',
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

    final phoneContacts = _normalizedPhoneContacts();
    if (phoneContacts == null) {
      return;
    }

    final input = EducationProgramInput(
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
      phoneContacts: phoneContacts,
      alertOffsetMinutes: _alertOffsetMinutes,
    );

    if (!_hasAnyChanges(input)) {
      setState(() {
        _message = '변경된 내용이 없습니다.';
      });
      return;
    }

    final needsCalendarApplyScope = _hasScheduleImpactingChanges(input);
    final calendarApplyScope = needsCalendarApplyScope
        ? await _pickCalendarApplyScope(
            title: '캘린더 반영 범위',
            message: '반복 일정을 캘린더에 어느 범위로 반영할까요?',
            allLabel: '전체 기간에 반영',
            futureLabel: '오늘 이후 일정에 반영',
          )
        : CalendarApplyScope.future;

    if (!mounted || calendarApplyScope == null) {
      return;
    }

    Navigator.of(context).pop(
      _EducationProgramFormResult.save(
        input,
        calendarApplyScope,
        memberIds: widget.program == null
            ? _selectedMemberIds.toList()
            : [_familyMemberId],
        affectsCalendar: needsCalendarApplyScope,
      ),
    );
  }

  Future<void> _showMissingMembersAlert() {
    return showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text('구성원 선택'),
        content: Text('반복 일정을 등록할 구성원을 선택해 주세요.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('확인'),
          ),
        ],
      ),
    );
  }

  List<EducationProgramPhoneContact>? _normalizedPhoneContacts() {
    final contacts = <EducationProgramPhoneContact>[];

    for (final contact in _phoneContacts) {
      final phoneNumber = contact.phoneController.text.trim();
      final customLabel = contact.customLabelController.text.trim();
      final label = contact.label == '직접입력' ? customLabel : contact.label;

      if (phoneNumber.isEmpty && label.isEmpty) {
        continue;
      }

      if (phoneNumber.isEmpty) {
        setState(() {
          _message = '전화번호를 입력해 주세요.';
        });
        return null;
      }

      if (label.isEmpty) {
        setState(() {
          _message = '전화번호 구분을 입력해 주세요.';
        });
        return null;
      }

      contacts.add(
        EducationProgramPhoneContact(label: label, phoneNumber: phoneNumber),
      );
    }

    return contacts;
  }

  bool _hasAnyChanges(EducationProgramInput input) {
    final program = widget.program;

    if (program == null) {
      return true;
    }

    return _hasScheduleImpactingChanges(input) ||
        !_samePhoneContacts(program.phoneContacts, input.phoneContacts);
  }

  bool _hasScheduleImpactingChanges(EducationProgramInput input) {
    final program = widget.program;

    if (program == null) {
      return true;
    }

    return program.familyMemberId != input.familyMemberId ||
        program.name != input.name ||
        !_isSameDate(program.startsOn, input.startsOn) ||
        !_isSameDate(program.endsOn, input.endsOn) ||
        program.recurrenceType != input.recurrenceType ||
        !_sameWeeklySchedules(program.weeklySchedules, input.weeklySchedules) ||
        !_sameMonthlySchedules(
          program.monthlySchedules,
          input.monthlySchedules,
        ) ||
        program.alertOffsetMinutes != input.alertOffsetMinutes;
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
          child: Text('취소'),
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
        title: Text('반복 일정 삭제'),
        content: Text('${program.name}와 연결된 캘린더 일정을 삭제할까요?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('취소'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('삭제'),
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
    final memberValue = widget.program == null
        ? _selectedMemberLabel()
        : selectedMember.nickname;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.program == null ? '반복 일정 등록' : '반복 일정 수정'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 32),
          onPressed: () => Navigator.of(context).pop(),
          child: Text('취소'),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 32),
          onPressed: _submit,
          child: Text('저장'),
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
                  placeholder: '예: 영어 수업',
                ),
                _PickerRow(
                  label: '구성원',
                  value: memberValue,
                  valueMaxLines: 1,
                  onPressed: _pickMember,
                ),
                _DateRangeRow(
                  startValue: _dateText(_startsOn),
                  endValue: _dateText(_endsOn),
                  onPickStart: () => _pickDate(isStart: true),
                  onPickEnd: () => _pickDate(isStart: false),
                ),
                _PickerRow(
                  label: '알림',
                  value: alertOffsetLabel(_alertOffsetMinutes),
                  onPressed: _pickAlertOffset,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _FormSection(
              children: [
                _PhoneContactsHeader(onAdd: _addPhoneContact),
                for (var index = 0; index < _phoneContacts.length; index++)
                  _PhoneContactInputRow(
                    contact: _phoneContacts[index],
                    onPickLabel: () => _pickPhoneContactLabel(index),
                    onRemove: () => _removePhoneContact(index),
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
            if (_recurrenceType == EducationRecurrenceType.monthly) ...[
              _FormSection(
                children: [
                  _MonthlyRuleModeRow(
                    value: _monthlyRuleMode,
                    onChanged: _selectMonthlyRuleMode,
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
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
                  for (final weekOfMonth in _visibleMonthlyRuleKeys())
                    _MonthlyRuleRow(
                      weekOfMonth: weekOfMonth,
                      mode: _monthlyRuleMode,
                      rule: _monthlyRules[weekOfMonth]!,
                      onToggle: (value) {
                        if (value &&
                            _monthlyRuleMode == _MonthlyRuleMode.dayOfMonth &&
                            _isMonthlyDayInUse(
                              _monthlyRules[weekOfMonth]!.dayOfMonth ?? 1,
                              exceptWeekOfMonth: weekOfMonth,
                            )) {
                          setState(() {
                            _message = '이미 선택한 날짜입니다.';
                          });
                          return;
                        }
                        setState(() {
                          _monthlyRules[weekOfMonth] =
                              _monthlyRules[weekOfMonth]!.copyWith(
                                enabled: value,
                              );
                        });
                      },
                      onPickWeekday: () => _pickMonthlyWeekday(weekOfMonth),
                      onPickDay: () => _pickMonthlyDay(weekOfMonth),
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
                  if (_monthlyRuleMode == _MonthlyRuleMode.dayOfMonth &&
                      _monthlyRules.values
                              .where((rule) => rule.enabled)
                              .length <
                          _monthlyRules.length)
                    _AddMonthlyDayRuleButton(onPressed: _addMonthlyDayRule),
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
        child: Text(
          '반복 일정 삭제',
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

class _DateInputSheet extends StatefulWidget {
  const _DateInputSheet({
    required this.initial,
    required this.minimumDate,
    required this.maximumDate,
    required this.onCancel,
    required this.onDone,
  });

  final DateTime initial;
  final DateTime minimumDate;
  final DateTime maximumDate;
  final VoidCallback onCancel;
  final ValueChanged<DateTime> onDone;

  @override
  State<_DateInputSheet> createState() => _DateInputSheetState();
}

class _DateInputSheetState extends State<_DateInputSheet> {
  late final TextEditingController _yearController;
  late final TextEditingController _monthController;
  late final TextEditingController _dayController;
  String? _message;

  @override
  void initState() {
    super.initState();
    _yearController = TextEditingController(text: '${widget.initial.year}');
    _monthController = TextEditingController(
      text: _twoDigits(widget.initial.month),
    );
    _dayController = TextEditingController(
      text: _twoDigits(widget.initial.day),
    );
  }

  @override
  void dispose() {
    _yearController.dispose();
    _monthController.dispose();
    _dayController.dispose();
    super.dispose();
  }

  void _submit() {
    final year = int.tryParse(_yearController.text);
    final month = int.tryParse(_monthController.text);
    final day = int.tryParse(_dayController.text);

    if (year == null || month == null || day == null) {
      setState(() => _message = '날짜를 숫자로 입력해 주세요.');
      return;
    }

    if (month < 1 || month > 12) {
      setState(() => _message = '월은 1부터 12까지 입력해 주세요.');
      return;
    }

    final value = DateTime(year, month, day);
    if (value.year != year || value.month != month || value.day != day) {
      setState(() => _message = '존재하는 날짜를 입력해 주세요.');
      return;
    }

    final date = _dateOnly(value);
    if (date.isBefore(widget.minimumDate) || date.isAfter(widget.maximumDate)) {
      setState(() => _message = '오늘 기준 1년 전부터 1년 후까지만 입력할 수 있습니다.');
      return;
    }

    widget.onDone(date);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.darkSurface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 14,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 52,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: widget.onCancel,
                      child: Text('취소'),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _submit,
                      child: Text('완료'),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _NumberInputField(
                      controller: _yearController,
                      placeholder: '2026',
                      suffix: '년',
                      maxLength: 4,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _NumberInputField(
                      controller: _monthController,
                      placeholder: '06',
                      suffix: '월',
                      maxLength: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _NumberInputField(
                      controller: _dayController,
                      placeholder: '27',
                      suffix: '일',
                      maxLength: 2,
                    ),
                  ),
                ],
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(
                  _message!,
                  style: TextStyle(
                    color: AppColors.darkDanger,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeInputSheet extends StatefulWidget {
  const _TimeInputSheet({
    required this.initial,
    required this.onCancel,
    required this.onDone,
  });

  final TimeOfDayValue initial;
  final VoidCallback onCancel;
  final ValueChanged<TimeOfDayValue> onDone;

  @override
  State<_TimeInputSheet> createState() => _TimeInputSheetState();
}

class _TimeInputSheetState extends State<_TimeInputSheet> {
  late final TextEditingController _hourController;
  late final TextEditingController _minuteController;
  late bool _isPm;
  String? _message;

  @override
  void initState() {
    super.initState();
    final displayHour = widget.initial.hour % 12 == 0
        ? 12
        : widget.initial.hour % 12;
    _hourController = TextEditingController(text: _twoDigits(displayHour));
    _minuteController = TextEditingController(
      text: _twoDigits(widget.initial.minute),
    );
    _isPm = widget.initial.hour >= 12;
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  void _submit() {
    final hour = int.tryParse(_hourController.text);
    final minute = int.tryParse(_minuteController.text);

    if (hour == null || minute == null) {
      setState(() => _message = '시각을 숫자로 입력해 주세요.');
      return;
    }

    if (hour < 1 || hour > 12) {
      setState(() => _message = '시는 1부터 12까지 입력해 주세요.');
      return;
    }

    if (minute < 0 || minute > 59) {
      setState(() => _message = '분은 0부터 59까지 입력해 주세요.');
      return;
    }

    final convertedHour = _isPm
        ? (hour == 12 ? 12 : hour + 12)
        : (hour == 12 ? 0 : hour);

    widget.onDone(TimeOfDayValue(hour: convertedHour, minute: minute));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.darkSurface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 14,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 52,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: widget.onCancel,
                      child: Text('취소'),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _submit,
                      child: Text('완료'),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  CupertinoSlidingSegmentedControl<bool>(
                    groupValue: _isPm,
                    children: const {
                      false: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('오전'),
                      ),
                      true: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('오후'),
                      ),
                    },
                    onValueChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _isPm = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _NumberInputField(
                      controller: _hourController,
                      placeholder: '3',
                      suffix: '시',
                      maxLength: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _NumberInputField(
                      controller: _minuteController,
                      placeholder: '30',
                      suffix: '분',
                      maxLength: 2,
                    ),
                  ),
                ],
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(
                  _message!,
                  style: TextStyle(
                    color: AppColors.darkDanger,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NumberInputField extends StatelessWidget {
  const _NumberInputField({
    required this.controller,
    required this.placeholder,
    required this.suffix,
    required this.maxLength,
  });

  final TextEditingController controller;
  final String placeholder;
  final String suffix;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: CupertinoTextField(
            controller: controller,
            placeholder: placeholder,
            maxLength: maxLength,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            style: TextStyle(
              color: AppColors.darkTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
            decoration: BoxDecoration(
              color: AppColors.darkBackground,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.darkBorder),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          suffix,
          style: TextStyle(
            color: AppColors.darkTextSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ],
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
        color: AppColors.darkSurfaceElevated,
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
              style: TextStyle(
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
              decoration: BoxDecoration(),
              style: TextStyle(fontSize: 16, letterSpacing: 0),
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
    this.valueMaxLines = 1,
  });

  final String label;
  final String value;
  final VoidCallback onPressed;
  final int? valueMaxLines;

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
              style: TextStyle(
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
              maxLines: valueMaxLines,
              overflow: valueMaxLines == null
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: TextStyle(
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

class _PhoneContactsHeader extends StatelessWidget {
  const _PhoneContactsHeader({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '전화번호',
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            minimumSize: Size.zero,
            color: AppColors.darkPrimarySoft,
            borderRadius: BorderRadius.circular(999),
            onPressed: onAdd,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.plus,
                  size: 13,
                  color: AppColors.darkPrimary,
                ),
                const SizedBox(width: 4),
                Text(
                  '전화번호 추가',
                  style: TextStyle(
                    color: AppColors.darkPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddMonthlyDayRuleButton extends StatelessWidget {
  const _AddMonthlyDayRuleButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: const Size(44, 36),
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.add, size: 16, color: AppColors.darkPrimary),
            const SizedBox(width: 4),
            Text(
              '특정일 추가',
              style: TextStyle(
                color: AppColors.darkPrimary,
                fontSize: 14,
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

class _PhoneContactInputRow extends StatelessWidget {
  const _PhoneContactInputRow({
    required this.contact,
    required this.onPickLabel,
    required this.onRemove,
  });

  final _PhoneContactDraft contact;
  final VoidCallback onPickLabel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 10, 12),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 112,
                child: contact.label == '직접입력'
                    ? _PhoneContactCustomLabelField(
                        controller: contact.customLabelController,
                        onPickLabel: onPickLabel,
                      )
                    : _PhoneContactLabelButton(
                        label: contact.label,
                        onPressed: onPickLabel,
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PhoneNumberTextField(
                  controller: contact.phoneController,
                ),
              ),
              const SizedBox(width: 6),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(30, 30),
                onPressed: onRemove,
                child: Icon(
                  CupertinoIcons.minus_circle_fill,
                  size: 20,
                  color: AppColors.darkDanger,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhoneContactLabelButton extends StatelessWidget {
  const _PhoneContactLabelButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      minimumSize: Size.zero,
      color: AppColors.darkBackground,
      borderRadius: BorderRadius.circular(10),
      onPressed: onPressed,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          Icon(
            CupertinoIcons.chevron_down,
            size: 13,
            color: AppColors.darkTextSecondary,
          ),
        ],
      ),
    );
  }
}

class _PhoneContactCustomLabelField extends StatelessWidget {
  const _PhoneContactCustomLabelField({
    required this.controller,
    required this.onPickLabel,
  });

  final TextEditingController controller;
  final VoidCallback onPickLabel;

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: controller,
      placeholder: '구분',
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      style: TextStyle(
        color: AppColors.darkTextPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      suffix: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(26, 26),
        onPressed: onPickLabel,
        child: Icon(
          CupertinoIcons.chevron_down,
          size: 13,
          color: AppColors.darkTextSecondary,
        ),
      ),
      decoration: BoxDecoration(
        color: AppColors.darkBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.darkPrimary),
      ),
    );
  }
}

class _PhoneNumberTextField extends StatelessWidget {
  const _PhoneNumberTextField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: controller,
      placeholder: '전화번호',
      keyboardType: TextInputType.phone,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      style: TextStyle(
        color: AppColors.darkTextPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      decoration: BoxDecoration(
        color: AppColors.darkBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.darkBorder),
      ),
    );
  }
}

class _DateRangeRow extends StatelessWidget {
  const _DateRangeRow({
    required this.startValue,
    required this.endValue,
    required this.onPickStart,
    required this.onPickEnd,
  });

  final String startValue;
  final String endValue;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              '기간',
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _CompactValueButton(
                    value: startValue,
                    onPressed: onPickStart,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '~',
                    style: TextStyle(
                      color: AppColors.darkTextSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                Expanded(
                  child: _CompactValueButton(
                    value: endValue,
                    onPressed: onPickEnd,
                  ),
                ),
              ],
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
          SizedBox(
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

class _MonthlyRuleModeRow extends StatelessWidget {
  const _MonthlyRuleModeRow({required this.value, required this.onChanged});

  final _MonthlyRuleMode value;
  final ValueChanged<_MonthlyRuleMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              '월 반복 기준',
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          Expanded(
            child: CupertinoSlidingSegmentedControl<_MonthlyRuleMode>(
              groupValue: value,
              children: const {
                _MonthlyRuleMode.weekday: Padding(
                  padding: EdgeInsets.symmetric(vertical: 7),
                  child: Text('특정 요일'),
                ),
                _MonthlyRuleMode.dayOfMonth: Padding(
                  padding: EdgeInsets.symmetric(vertical: 7),
                  child: Text('특정일'),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RuleLeadingColumn(
            label: _weekdayLabels[weekday],
            enabled: rule.enabled,
            onToggle: onToggle,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              children: [
                _AlignedRuleTimeLine(
                  label: '일정',
                  startValue: _timeOfDayLabel(rule.startsAt),
                  endValue: _timeOfDayLabel(rule.endsAt),
                  onPickStart: rule.enabled ? onPickStart : null,
                  onPickEnd: rule.enabled ? onPickEnd : null,
                  trailing: copyLabel == null
                      ? null
                      : _CopyPreviousRuleButton(
                          enabled: canCopy,
                          label: copyLabel!,
                          onPressed: onCopyPrevious,
                        ),
                ),
                const SizedBox(height: 6),
                _AlignedRuleTimeLine(
                  label: '차량',
                  startValue: rule.vehicleBoardingTime == null
                      ? '탑승'
                      : _timeOfDayLabel(rule.vehicleBoardingTime!),
                  endValue: rule.vehicleDropoffTime == null
                      ? '하차'
                      : _timeOfDayLabel(rule.vehicleDropoffTime!),
                  onPickStart: rule.enabled ? onPickBoarding : null,
                  onPickEnd: rule.enabled ? onPickDropoff : null,
                  onClearStart: rule.vehicleBoardingTime != null
                      ? onClearBoarding
                      : null,
                  onClearEnd: rule.vehicleDropoffTime != null
                      ? onClearDropoff
                      : null,
                  trailing: copyLabel == null
                      ? null
                      : const SizedBox(width: 28, height: 32),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyRuleRow extends StatelessWidget {
  const _MonthlyRuleRow({
    required this.weekOfMonth,
    required this.mode,
    required this.rule,
    required this.onToggle,
    required this.onPickWeekday,
    required this.onPickDay,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onPickBoarding,
    required this.onPickDropoff,
    required this.onClearBoarding,
    required this.onClearDropoff,
  });

  final int weekOfMonth;
  final _MonthlyRuleMode mode;
  final _MonthlyRule rule;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickWeekday;
  final VoidCallback onPickDay;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onPickBoarding;
  final VoidCallback onPickDropoff;
  final VoidCallback onClearBoarding;
  final VoidCallback onClearDropoff;

  @override
  Widget build(BuildContext context) {
    final isDayOfMonth = mode == _MonthlyRuleMode.dayOfMonth;
    final selectorWidth = isDayOfMonth ? 64.0 : 48.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RuleLeadingColumn(
            label: isDayOfMonth
                ? '특정일'
                : _weekOfMonthLabels[weekOfMonth] ?? '$weekOfMonth주',
            enabled: rule.enabled,
            onToggle: onToggle,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: _SmallWeekdayButton(
                    width: selectorWidth,
                    value: isDayOfMonth
                        ? '매월 ${rule.dayOfMonth}일'
                        : '${_weekdayLabels[rule.weekday]}요일',
                    enabled: rule.enabled,
                    onPressed: isDayOfMonth ? onPickDay : onPickWeekday,
                  ),
                ),
                const SizedBox(height: 6),
                _AlignedRuleTimeLine(
                  label: '시간',
                  startValue: _timeOfDayLabel(rule.startsAt),
                  endValue: _timeOfDayLabel(rule.endsAt),
                  onPickStart: rule.enabled ? onPickStart : null,
                  onPickEnd: rule.enabled ? onPickEnd : null,
                ),
                const SizedBox(height: 6),
                _AlignedRuleTimeLine(
                  label: '차량',
                  startValue: rule.vehicleBoardingTime == null
                      ? '탑승'
                      : _timeOfDayLabel(rule.vehicleBoardingTime!),
                  endValue: rule.vehicleDropoffTime == null
                      ? '하차'
                      : _timeOfDayLabel(rule.vehicleDropoffTime!),
                  onPickStart: rule.enabled ? onPickBoarding : null,
                  onPickEnd: rule.enabled ? onPickDropoff : null,
                  onClearStart: rule.vehicleBoardingTime != null
                      ? onClearBoarding
                      : null,
                  onClearEnd: rule.vehicleDropoffTime != null
                      ? onClearDropoff
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleLeadingColumn extends StatelessWidget {
  const _RuleLeadingColumn({
    required this.label,
    required this.enabled,
    required this.onToggle,
  });

  final String label;
  final bool enabled;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.darkTextPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 34,
            height: 22,
            child: FittedBox(
              fit: BoxFit.contain,
              child: CupertinoSwitch(value: enabled, onChanged: onToggle),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallWeekdayButton extends StatelessWidget {
  const _SmallWeekdayButton({
    required this.value,
    required this.enabled,
    required this.onPressed,
    this.width = 48,
  });

  final String value;
  final bool enabled;
  final VoidCallback onPressed;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 32,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        color: AppColors.darkSurfaceElevated,
        borderRadius: BorderRadius.circular(9),
        onPressed: enabled ? onPressed : null,
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: enabled
                ? CupertinoColors.systemBlue
                : CupertinoColors.systemGrey,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _CopyPreviousRuleButton extends StatelessWidget {
  const _CopyPreviousRuleButton({
    required this.enabled,
    required this.label,
    required this.onPressed,
  });

  final bool enabled;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? CupertinoColors.systemBlue
        : CupertinoColors.systemGrey;

    return Semantics(
      button: true,
      label: '$label 아래로 복사',
      child: SizedBox(
        width: 28,
        height: 32,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          color: enabled
              ? AppColors.darkPrimarySoft
              : AppColors.darkSurfaceElevated,
          borderRadius: BorderRadius.circular(9),
          onPressed: enabled ? onPressed : null,
          child: Icon(CupertinoIcons.arrow_down_doc, size: 14, color: color),
        ),
      ),
    );
  }
}

class _AlignedRuleTimeLine extends StatelessWidget {
  const _AlignedRuleTimeLine({
    required this.label,
    required this.startValue,
    required this.endValue,
    required this.onPickStart,
    required this.onPickEnd,
    this.onClearStart,
    this.onClearEnd,
    this.trailing,
  });

  final String label;
  final String startValue;
  final String endValue;
  final VoidCallback? onPickStart;
  final VoidCallback? onPickEnd;
  final VoidCallback? onClearStart;
  final VoidCallback? onClearEnd;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.darkTextSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
        Expanded(
          child: _CompactValueButton(value: startValue, onPressed: onPickStart),
        ),
        _ClearTimeSlot(onPressed: onClearStart),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 3),
          child: Text(
            '~',
            style: TextStyle(
              color: AppColors.darkTextSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
        Expanded(
          child: _CompactValueButton(value: endValue, onPressed: onPickEnd),
        ),
        _ClearTimeSlot(onPressed: onClearEnd),
        if (trailing != null) ...[const SizedBox(width: 4), trailing!],
      ],
    );
  }
}

class _ClearTimeSlot extends StatelessWidget {
  const _ClearTimeSlot({this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      child: onPressed == null
          ? const SizedBox.shrink()
          : _ClearTimeButton(onPressed: onPressed!),
    );
  }
}

class _CompactValueButton extends StatelessWidget {
  const _CompactValueButton({required this.value, required this.onPressed});

  final String value;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        color: AppColors.darkSurfaceElevated,
        borderRadius: BorderRadius.circular(9),
        onPressed: onPressed,
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: onPressed == null
                ? CupertinoColors.systemGrey
                : CupertinoColors.systemBlue,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
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
    required this.dayOfMonth,
    required this.weekday,
    required this.startsAt,
    required this.endsAt,
    required this.vehicleBoardingTime,
    required this.vehicleDropoffTime,
  });

  final bool enabled;
  final int? dayOfMonth;
  final int weekday;
  final TimeOfDayValue startsAt;
  final TimeOfDayValue endsAt;
  final TimeOfDayValue? vehicleBoardingTime;
  final TimeOfDayValue? vehicleDropoffTime;

  _MonthlyRule copyWith({
    bool? enabled,
    int? dayOfMonth,
    int? weekday,
    TimeOfDayValue? startsAt,
    TimeOfDayValue? endsAt,
    _OptionalTimeUpdate? vehicleBoardingTime,
    _OptionalTimeUpdate? vehicleDropoffTime,
  }) {
    return _MonthlyRule(
      enabled: enabled ?? this.enabled,
      dayOfMonth: dayOfMonth ?? this.dayOfMonth,
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
        style: TextStyle(
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
              style: TextStyle(
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
        color: AppColors.darkSurfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Text(
        canManage ? '등록된 반복 일정이 없습니다. + 버튼으로 추가해 주세요.' : '등록된 반복 일정이 없습니다.',
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
      child: Text(
        '선택한 구성원의 반복 일정이 없습니다.',
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
        style: TextStyle(
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

bool _isSameDate(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

bool _sameWeeklySchedules(
  List<EducationWeeklySchedule> left,
  List<EducationWeeklySchedule> right,
) {
  final sortedLeft = [...left]..sort((a, b) => a.weekday.compareTo(b.weekday));
  final sortedRight = [...right]
    ..sort((a, b) => a.weekday.compareTo(b.weekday));

  if (sortedLeft.length != sortedRight.length) {
    return false;
  }

  for (var index = 0; index < sortedLeft.length; index++) {
    final leftSchedule = sortedLeft[index];
    final rightSchedule = sortedRight[index];

    if (leftSchedule.weekday != rightSchedule.weekday ||
        !_sameTimeOfDay(leftSchedule.startsAt, rightSchedule.startsAt) ||
        !_sameTimeOfDay(leftSchedule.endsAt, rightSchedule.endsAt) ||
        !_sameOptionalTimeOfDay(
          leftSchedule.vehicleBoardingTime,
          rightSchedule.vehicleBoardingTime,
        ) ||
        !_sameOptionalTimeOfDay(
          leftSchedule.vehicleDropoffTime,
          rightSchedule.vehicleDropoffTime,
        )) {
      return false;
    }
  }

  return true;
}

bool _sameMonthlySchedules(
  List<EducationMonthlySchedule> left,
  List<EducationMonthlySchedule> right,
) {
  final sortedLeft = [...left]
    ..sort((a, b) => a.weekOfMonth.compareTo(b.weekOfMonth));
  final sortedRight = [...right]
    ..sort((a, b) => a.weekOfMonth.compareTo(b.weekOfMonth));

  if (sortedLeft.length != sortedRight.length) {
    return false;
  }

  for (var index = 0; index < sortedLeft.length; index++) {
    final leftSchedule = sortedLeft[index];
    final rightSchedule = sortedRight[index];

    if (leftSchedule.weekOfMonth != rightSchedule.weekOfMonth ||
        leftSchedule.weekday != rightSchedule.weekday ||
        leftSchedule.dayOfMonth != rightSchedule.dayOfMonth ||
        !_sameTimeOfDay(leftSchedule.startsAt, rightSchedule.startsAt) ||
        !_sameTimeOfDay(leftSchedule.endsAt, rightSchedule.endsAt) ||
        !_sameOptionalTimeOfDay(
          leftSchedule.vehicleBoardingTime,
          rightSchedule.vehicleBoardingTime,
        ) ||
        !_sameOptionalTimeOfDay(
          leftSchedule.vehicleDropoffTime,
          rightSchedule.vehicleDropoffTime,
        )) {
      return false;
    }
  }

  return true;
}

bool _samePhoneContacts(
  List<EducationProgramPhoneContact> left,
  List<EducationProgramPhoneContact> right,
) {
  if (left.length != right.length) {
    return false;
  }

  for (var index = 0; index < left.length; index++) {
    if (left[index].label.trim() != right[index].label.trim() ||
        left[index].phoneNumber.trim() != right[index].phoneNumber.trim()) {
      return false;
    }
  }

  return true;
}

bool _sameOptionalTimeOfDay(TimeOfDayValue? left, TimeOfDayValue? right) {
  if (left == null || right == null) {
    return left == null && right == null;
  }

  return _sameTimeOfDay(left, right);
}

bool _sameTimeOfDay(TimeOfDayValue left, TimeOfDayValue right) {
  return left.hour == right.hour && left.minute == right.minute;
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
          MemberFilterColor.fromValue(members[index].color) ??
          MemberFilterColor.selectable[index %
              MemberFilterColor.selectable.length],
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
    final boardingTime = schedule.vehicleBoardingTime == null
        ? null
        : _timeOfDayLabel(schedule.vehicleBoardingTime!);
    final dropoffTime = schedule.vehicleDropoffTime == null
        ? null
        : _timeOfDayLabel(schedule.vehicleDropoffTime!);
    final vehicleParts = [
      if (boardingTime != null) '승차 $boardingTime',
      if (dropoffTime != null) '하차 $dropoffTime',
    ];

    return _EducationScheduleSummary(
      title:
          '${_weekdayGroupText(weekdays)} ${_timeOfDayLabel(schedule.startsAt)}-${_timeOfDayLabel(schedule.endsAt)}',
      vehicleText: vehicleParts.isEmpty ? null : vehicleParts.join(' · '),
    );
  }

  factory _EducationScheduleSummary.fromMonthlySchedules({
    required List<EducationMonthlySchedule> schedules,
    required EducationMonthlySchedule schedule,
  }) {
    final boardingTime = schedule.vehicleBoardingTime == null
        ? null
        : _timeOfDayLabel(schedule.vehicleBoardingTime!);
    final dropoffTime = schedule.vehicleDropoffTime == null
        ? null
        : _timeOfDayLabel(schedule.vehicleDropoffTime!);
    final vehicleParts = [
      if (boardingTime != null) '승차 $boardingTime',
      if (dropoffTime != null) '하차 $dropoffTime',
    ];
    final scheduleText = schedules
        .map(
          (entry) => entry.dayOfMonth == null
              ? '${_weekOfMonthLabels[entry.weekOfMonth]} ${_weekdayLabels[entry.weekday]}요일'
              : '${entry.dayOfMonth}일',
        )
        .join(',');

    return _EducationScheduleSummary(
      title:
          '매월 $scheduleText ${_timeOfDayLabel(schedule.startsAt)}-${_timeOfDayLabel(schedule.endsAt)}',
      vehicleText: vehicleParts.isEmpty ? null : vehicleParts.join(' · '),
    );
  }
}

int _minutes(TimeOfDayValue value) => value.hour * 60 + value.minute;

String _timeOfDayLabel(TimeOfDayValue value) {
  final isPm = value.hour >= 12;
  final displayHour = value.hour % 12 == 0 ? 12 : value.hour % 12;

  return '${isPm ? '오후' : '오전'} $displayHour:${_twoDigits(value.minute)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
