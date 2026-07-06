import 'package:flutter/cupertino.dart';

import '../../core/api_client.dart';
import '../../design_system/app_colors.dart';
import '../../shared/alert_offset_picker.dart';
import '../../shared/refreshable_scroll_view.dart';

class AnniversaryScreen extends StatefulWidget {
  const AnniversaryScreen({
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
  State<AnniversaryScreen> createState() => _AnniversaryScreenState();
}

class _AnniversaryScreenState extends State<AnniversaryScreen> {
  final _apiClient = ApiClient();

  late AppFamily _family;
  AnniversaryDashboard? _dashboard;
  String? _message;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _family = widget.family;
    _loadAnniversaries();
  }

  @override
  void didUpdateWidget(covariant AnniversaryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.family.id != widget.family.id) {
      _family = widget.family;
      _dashboard = null;
      _loadAnniversaries();
    }
  }

  Future<void> _loadAnniversaries() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final dashboard = await _apiClient.getAnniversaryDashboard(
        widget.sessionToken,
        familyId: _family.id,
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

  Future<void> _switchFamily() async {
    if (widget.families.length < 2) {
      return;
    }

    final selectedFamilyId = await showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text('가족 전환'),
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
    });
    await widget.onSelectFamily(selectedFamily);
    await _loadAnniversaries();
  }

  Future<void> _openForm() async {
    await _openFormFor();
  }

  Future<void> _openFormFor({Anniversary? anniversary}) async {
    final result = await Navigator.of(context).push<_AnniversaryFormResult>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (_) => _AnniversaryFormScreen(anniversary: anniversary),
      ),
    );

    if (result == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      String nextMessage;

      if (result.shouldDelete) {
        if (anniversary == null) {
          return;
        }

        await _apiClient.deleteAnniversary(
          widget.sessionToken,
          familyId: _family.id,
          anniversaryId: anniversary.id,
        );
        nextMessage = '기념일이 삭제되었습니다.';
      } else {
        final input = result.input;

        if (input == null) {
          return;
        }

        final mutationResult = anniversary == null
            ? await _apiClient.createAnniversary(
                widget.sessionToken,
                familyId: _family.id,
                input: input,
              )
            : await _apiClient.updateAnniversary(
                widget.sessionToken,
                familyId: _family.id,
                anniversaryId: anniversary.id,
                input: input,
              );
        nextMessage = mutationResult.generatedScheduleCount == 0
            ? '기념일이 저장되었습니다.'
            : '${mutationResult.generatedScheduleCount}개 일정이 캘린더에 반영되었습니다.';
      }

      await _loadAnniversaries();

      if (mounted) {
        setState(() {
          _message = nextMessage;
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

  @override
  Widget build(BuildContext context) {
    final dashboard = _dashboard;
    final anniversaries = [...dashboard?.anniversaries ?? const <Anniversary>[]]
      ..sort(_compareAnniversary);

    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: CupertinoNavigationBar(
        middle: _FeatureFamilyTitle(
          family: _family,
          featureName: '기념일',
          canSwitch: widget.families.length > 1,
          onPressed: _switchFamily,
        ),
        trailing: dashboard?.canManage == true
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(32, 32),
                onPressed: _isLoading ? null : _openForm,
                child: const Icon(CupertinoIcons.plus),
              )
            : null,
      ),
      child: SafeArea(
        child: RefreshableScrollView(
          onRefresh: _loadAnniversaries,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            if (_message != null) ...[
              _InlineMessage(message: _message!),
              const SizedBox(height: 14),
            ],
            if (_isLoading && dashboard == null)
              Padding(
                padding: EdgeInsets.only(top: 72),
                child: Center(child: CupertinoActivityIndicator()),
              )
            else if (dashboard == null)
              _EmptyState(
                text: '기념일 정보를 불러오지 못했습니다.',
                canManage: true,
                actionLabel: '다시 불러오기',
                onPressed: _loadAnniversaries,
              )
            else if (anniversaries.isEmpty)
              _EmptyState(
                text: '등록된 기념일이 없습니다.\n+ 버튼으로 추가해 주세요',
                canManage: dashboard.canManage,
                actionLabel: '기념일 추가',
                onPressed: _openForm,
              )
            else
              for (final anniversary in anniversaries)
                _AnniversaryTile(
                  anniversary: anniversary,
                  onPressed: dashboard.canManage
                      ? () => _openFormFor(anniversary: anniversary)
                      : null,
                ),
          ],
        ),
      ),
    );
  }
}

class _AnniversaryTile extends StatelessWidget {
  const _AnniversaryTile({required this.anniversary, required this.onPressed});

  final Anniversary anniversary;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.darkBorder)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _categoryColor(
                  anniversary.category,
                ).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _categoryIcon(anniversary.category),
                color: _categoryColor(anniversary.category),
                size: 23,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          anniversary.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.darkTextPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      if (anniversary.nextOccurrenceOrdinal != null) ...[
                        const SizedBox(width: 7),
                        _OrdinalBadge(
                          ordinal: anniversary.nextOccurrenceOrdinal!,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _anniversaryDateLabel(anniversary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.darkTextSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _dDayLabel(anniversary.nextOccurrenceDate),
              style: TextStyle(
                color: AppColors.darkPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            if (onPressed != null) ...[
              const SizedBox(width: 6),
              Icon(
                CupertinoIcons.chevron_right,
                color: AppColors.darkTextMuted,
                size: 16,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OrdinalBadge extends StatelessWidget {
  const _OrdinalBadge({required this.ordinal});

  final int ordinal;

  @override
  Widget build(BuildContext context) {
    final badgeColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemPink,
      context,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: badgeColor.withValues(alpha: 0.34)),
      ),
      child: Text(
        '$ordinal번째',
        style: TextStyle(
          color: badgeColor,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _AnniversaryFormResult {
  const _AnniversaryFormResult.save(this.input) : shouldDelete = false;
  const _AnniversaryFormResult.delete() : input = null, shouldDelete = true;

  final AnniversaryInput? input;
  final bool shouldDelete;
}

class _AnniversaryFormScreen extends StatefulWidget {
  const _AnniversaryFormScreen({this.anniversary});

  final Anniversary? anniversary;

  @override
  State<_AnniversaryFormScreen> createState() => _AnniversaryFormScreenState();
}

class _AnniversaryFormScreenState extends State<_AnniversaryFormScreen> {
  late final TextEditingController _customCategoryController;
  late final TextEditingController _titleController;
  late final TextEditingController _monthController;
  late final TextEditingController _dayController;
  late final TextEditingController _yearController;
  late AnniversaryCategory _category;
  late AnniversaryCalendarType _calendarType;
  late bool _isLunarLeap;
  int? _alertOffsetMinutes;
  String? _message;

  @override
  void initState() {
    super.initState();
    final anniversary = widget.anniversary;
    _category = anniversary?.category ?? AnniversaryCategory.birthday;
    _calendarType = anniversary?.calendarType ?? AnniversaryCalendarType.solar;
    _isLunarLeap = anniversary?.isLunarLeap ?? false;
    _alertOffsetMinutes = anniversary?.alertOffsetMinutes;
    _customCategoryController = TextEditingController(
      text: anniversary?.customCategoryLabel ?? '',
    );
    _titleController = TextEditingController(text: anniversary?.title ?? '');
    _monthController = TextEditingController(
      text: anniversary == null ? '' : '${anniversary.month}',
    );
    _dayController = TextEditingController(
      text: anniversary == null ? '' : '${anniversary.day}',
    );
    _yearController = TextEditingController(
      text: anniversary?.year == null ? '' : '${anniversary!.year}',
    );
  }

  @override
  void dispose() {
    _customCategoryController.dispose();
    _titleController.dispose();
    _monthController.dispose();
    _dayController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  Future<void> _pickCategory() async {
    final selected = await showCupertinoModalPopup<AnniversaryCategory>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: const Text('카테고리'),
        actions: AnniversaryCategory.values
            .map(
              (category) => CupertinoActionSheetAction(
                isDefaultAction: category == _category,
                onPressed: () => Navigator.of(popupContext).pop(category),
                child: Text(_categoryLabel(category)),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: const Text('취소'),
        ),
      ),
    );

    if (selected != null) {
      setState(() {
        _category = selected;
        if (selected == AnniversaryCategory.wedding) {
          _calendarType = AnniversaryCalendarType.solar;
          _isLunarLeap = false;
        }
      });
    }
  }

  Future<void> _confirmDelete() async {
    final anniversary = widget.anniversary;

    if (anniversary == null) {
      return;
    }

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('기념일 삭제'),
        content: Text('${anniversary.title} 기념일과 연결된 캘린더 일정을 삭제할까요?'),
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

    if (mounted && confirmed == true) {
      Navigator.of(context).pop(const _AnniversaryFormResult.delete());
    }
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

  void _submit() {
    final customCategoryLabel = _customCategoryController.text.trim();
    final title = _titleController.text.trim();
    final month = int.tryParse(_monthController.text.trim());
    final day = int.tryParse(_dayController.text.trim());
    final yearText = _yearController.text.trim();
    final year = yearText.isEmpty ? null : int.tryParse(yearText);

    if (_category == AnniversaryCategory.custom) {
      if (customCategoryLabel.isEmpty) {
        setState(() => _message = '직접입력 카테고리를 입력해 주세요.');
        return;
      }

      if (customCategoryLabel.length > 40) {
        setState(() => _message = '직접입력 카테고리는 40자 이하로 입력해 주세요.');
        return;
      }
    }

    if (title.isEmpty) {
      setState(() => _message = '기념일 제목을 입력해 주세요.');
      return;
    }

    if (month == null || month < 1 || month > 12) {
      setState(() => _message = '월은 1부터 12까지 입력해 주세요.');
      return;
    }

    if (day == null || day < 1 || day > 31) {
      setState(() => _message = '일은 1부터 31까지 입력해 주세요.');
      return;
    }

    final currentYear = DateTime.now().year;
    if (yearText.isNotEmpty &&
        (year == null || year < 1900 || year > currentYear)) {
      setState(() => _message = '년은 1900년부터 올해까지 입력해 주세요.');
      return;
    }

    Navigator.of(context).pop(
      _AnniversaryFormResult.save(
        AnniversaryInput(
          category: _category,
          customCategoryLabel: _category == AnniversaryCategory.custom
              ? customCategoryLabel
              : null,
          title: title,
          calendarType: _allowsCalendarTypeSelection(_category)
              ? _calendarType
              : AnniversaryCalendarType.solar,
          month: month,
          day: day,
          isLunarLeap:
              _allowsCalendarTypeSelection(_category) &&
              _calendarType == AnniversaryCalendarType.lunar &&
              _isLunarLeap,
          year: year,
          alertOffsetMinutes: _alertOffsetMinutes,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.anniversary != null;

    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(isEditing ? '기념일 수정' : '기념일 추가'),
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
                _CategoryRow(
                  category: _category,
                  customCategoryController: _customCategoryController,
                  onPickCategory: _pickCategory,
                ),
                _TextFieldRow(
                  label: '제목',
                  controller: _titleController,
                  placeholder: '예: 엄마 생일',
                ),
                _AnniversaryDateRow(
                  yearController: _yearController,
                  monthController: _monthController,
                  dayController: _dayController,
                ),
                if (_allowsCalendarTypeSelection(_category)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                    child: Row(
                      children: [
                        const SizedBox(width: 70),
                        CupertinoSlidingSegmentedControl<
                          AnniversaryCalendarType
                        >(
                          groupValue: _calendarType,
                          children: const {
                            AnniversaryCalendarType.solar: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 13),
                              child: Text('양력'),
                            ),
                            AnniversaryCalendarType.lunar: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 13),
                              child: Text('음력'),
                            ),
                          },
                          onValueChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _calendarType = value;
                                if (value != AnniversaryCalendarType.lunar) {
                                  _isLunarLeap = false;
                                }
                              });
                            }
                          },
                        ),
                        const Spacer(),
                        if (_calendarType == AnniversaryCalendarType.lunar) ...[
                          Text(
                            '윤달',
                            style: TextStyle(
                              color: AppColors.darkTextSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Transform.scale(
                            scale: 0.78,
                            child: CupertinoSwitch(
                              value: _isLunarLeap,
                              activeTrackColor: AppColors.darkPrimary,
                              onChanged: (value) {
                                setState(() => _isLunarLeap = value);
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                _PickerRow(
                  label: '알림',
                  value: alertOffsetLabel(_alertOffsetMinutes),
                  onPressed: _pickAlertOffset,
                ),
              ],
            ),
            if (isEditing) ...[
              const SizedBox(height: 18),
              _RecentSchedulesSection(
                schedules: widget.anniversary!.recentSchedules,
              ),
            ],
            if (isEditing) ...[
              const SizedBox(height: 22),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 12),
                onPressed: _confirmDelete,
                child: const Text(
                  '기념일 삭제',
                  style: TextStyle(
                    color: CupertinoColors.destructiveRed,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
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

class _RecentSchedulesSection extends StatelessWidget {
  const _RecentSchedulesSection({required this.schedules});

  final List<AnniversaryScheduleOccurrence> schedules;

  @override
  Widget build(BuildContext context) {
    return _FormSection(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Row(
            children: [
              Text(
                '다가오는 일정',
                style: TextStyle(
                  color: AppColors.darkTextPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const Spacer(),
              Text(
                '최근 5개',
                style: TextStyle(
                  color: AppColors.darkTextMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        if (schedules.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '다가오는 일정이 없습니다.',
                style: TextStyle(
                  color: AppColors.darkTextSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
          )
        else
          for (final schedule in schedules)
            _RecentScheduleRow(schedule: schedule),
      ],
    );
  }
}

class _RecentScheduleRow extends StatelessWidget {
  const _RecentScheduleRow({required this.schedule});

  final AnniversaryScheduleOccurrence schedule;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 10),
      child: Row(
        children: [
          Text(
            _dDayLabel(schedule.startsAt),
            style: TextStyle(
              color: AppColors.darkPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _scheduleDateLabel(schedule.startsAt),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.darkTextSecondary,
                fontSize: 13,
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

class _AnniversaryDateRow extends StatelessWidget {
  const _AnniversaryDateRow({
    required this.yearController,
    required this.monthController,
    required this.dayController,
  });

  final TextEditingController yearController;
  final TextEditingController monthController;
  final TextEditingController dayController;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        children: [
          SizedBox(width: 82, child: Text('날짜', style: _rowLabelStyle)),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  flex: 2,
                  child: _NumberField(
                    controller: yearController,
                    placeholder: '선택',
                    fontSize: 14,
                    horizontalPadding: 6,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Text('년', style: _suffixStyle),
                ),
                Flexible(
                  child: _NumberField(
                    controller: monthController,
                    placeholder: '월',
                    horizontalPadding: 6,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Text('월', style: _suffixStyle),
                ),
                Flexible(
                  child: _NumberField(
                    controller: dayController,
                    placeholder: '일',
                    horizontalPadding: 6,
                  ),
                ),
                const SizedBox(width: 5),
                Text('일', style: _suffixStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.placeholder,
    this.fontSize = 16,
    this.horizontalPadding = 10,
  });

  final TextEditingController controller;
  final String placeholder;
  final double fontSize;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: AppColors.darkSurfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.darkBorder),
      ),
      style: TextStyle(fontSize: fontSize, letterSpacing: 0),
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
        borderRadius: BorderRadius.circular(16),
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
          SizedBox(width: 82, child: Text(label, style: _rowLabelStyle)),
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

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.customCategoryController,
    required this.onPickCategory,
  });

  final AnniversaryCategory category;
  final TextEditingController customCategoryController;
  final VoidCallback onPickCategory;

  @override
  Widget build(BuildContext context) {
    if (category != AnniversaryCategory.custom) {
      return _PickerRow(
        label: '카테고리',
        value: _categoryLabel(category),
        onPressed: onPickCategory,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        children: [
          SizedBox(width: 82, child: Text('카테고리', style: _rowLabelStyle)),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
            minimumSize: const Size(62, 34),
            onPressed: onPickCategory,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _categoryLabel(category),
                  style: TextStyle(
                    color: AppColors.darkPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  CupertinoIcons.chevron_down,
                  color: AppColors.darkPrimary,
                  size: 13,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: CupertinoTextField(
              controller: customCategoryController,
              placeholder: '예: 첫 만남',
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
              decoration: const BoxDecoration(),
              style: const TextStyle(fontSize: 16, letterSpacing: 0),
              textInputAction: TextInputAction.next,
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
          SizedBox(width: 82, child: Text(label, style: _rowLabelStyle)),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.text,
    required this.canManage,
    required this.actionLabel,
    required this.onPressed,
  });

  final String text;
  final bool canManage;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(
            CupertinoIcons.gift_fill,
            size: 42,
            color: AppColors.darkPrimary,
          ),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.darkTextSecondary,
              fontSize: 15,
              height: 1.45,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          if (canManage) ...[
            const SizedBox(height: 18),
            SizedBox(
              height: 50,
              child: CupertinoButton.filled(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                minimumSize: const Size.fromHeight(50),
                borderRadius: BorderRadius.circular(12),
                onPressed: onPressed,
                child: Text(
                  actionLabel,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.25,
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkDanger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkDanger.withValues(alpha: 0.3)),
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
        style: _navTitleStyle,
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
              style: _navTitleStyle,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(CupertinoIcons.chevron_down, size: 15),
        ],
      ),
    );
  }
}

int _compareAnniversary(Anniversary left, Anniversary right) {
  final leftDate = left.nextOccurrenceDate;
  final rightDate = right.nextOccurrenceDate;

  if (leftDate == null || rightDate == null) {
    return leftDate == null && rightDate == null
        ? left.title.compareTo(right.title)
        : leftDate == null
        ? 1
        : -1;
  }

  final dateCompare = leftDate.compareTo(rightDate);
  return dateCompare == 0 ? left.title.compareTo(right.title) : dateCompare;
}

String _dDayLabel(DateTime? date) {
  if (date == null) {
    return '-';
  }

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final days = target.difference(today).inDays;

  return days == 0 ? '오늘' : '+$days일';
}

String _scheduleDateLabel(DateTime date) {
  return '${date.year}.${_two(date.month)}.${_two(date.day)} ${_weekdayLabel(date.weekday)}';
}

String _weekdayLabel(int weekday) {
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  return weekdays[weekday - 1];
}

String _categoryLabel(AnniversaryCategory category) {
  return switch (category) {
    AnniversaryCategory.birthday => '생일',
    AnniversaryCategory.wedding => '결혼기념일',
    AnniversaryCategory.custom => '직접입력',
  };
}

String _anniversaryCategoryLabel(Anniversary anniversary) {
  if (anniversary.category == AnniversaryCategory.custom) {
    final customLabel = anniversary.customCategoryLabel?.trim();
    if (customLabel != null && customLabel.isNotEmpty) {
      return customLabel;
    }
  }

  return _categoryLabel(anniversary.category);
}

bool _allowsCalendarTypeSelection(AnniversaryCategory category) {
  return category == AnniversaryCategory.birthday ||
      category == AnniversaryCategory.custom;
}

String _calendarLabel(AnniversaryCalendarType type) {
  return switch (type) {
    AnniversaryCalendarType.solar => '양력',
    AnniversaryCalendarType.lunar => '음력',
  };
}

String _anniversaryDateLabel(Anniversary anniversary) {
  final calendarLabel = _calendarLabel(anniversary.calendarType);
  final lunarLeapLabel =
      anniversary.calendarType == AnniversaryCalendarType.lunar &&
          anniversary.isLunarLeap
      ? ' 윤달'
      : '';

  return '${_anniversaryCategoryLabel(anniversary)} · $calendarLabel$lunarLeapLabel ${anniversary.month}월 ${anniversary.day}일';
}

IconData _categoryIcon(AnniversaryCategory category) {
  return switch (category) {
    AnniversaryCategory.birthday => CupertinoIcons.gift_fill,
    AnniversaryCategory.wedding => CupertinoIcons.heart_fill,
    AnniversaryCategory.custom => CupertinoIcons.star_fill,
  };
}

Color _categoryColor(AnniversaryCategory category) {
  return switch (category) {
    AnniversaryCategory.birthday => CupertinoColors.systemPink,
    AnniversaryCategory.wedding => CupertinoColors.systemRed,
    AnniversaryCategory.custom => CupertinoColors.systemPurple,
  };
}

String _two(int value) => value.toString().padLeft(2, '0');

TextStyle get _rowLabelStyle => TextStyle(
  color: AppColors.darkTextPrimary,
  fontSize: 15,
  fontWeight: FontWeight.w700,
  letterSpacing: 0,
);

TextStyle get _suffixStyle => TextStyle(
  color: AppColors.darkTextSecondary,
  fontWeight: FontWeight.w800,
  letterSpacing: 0,
);

TextStyle get _navTitleStyle => TextStyle(
  inherit: false,
  color: AppColors.darkTextPrimary,
  fontSize: 17,
  fontWeight: FontWeight.w700,
  letterSpacing: 0,
);
