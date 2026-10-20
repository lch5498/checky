import 'package:flutter/cupertino.dart';

import '../design_system/app_colors.dart';
import '../design_system/app_spacing.dart';
import '../design_system/app_typography.dart';

enum ScheduleSection { calendar, recurring, anniversary, holiday }

class ScheduleSectionSwitcher extends StatelessWidget {
  const ScheduleSectionSwitcher({
    super.key,
    required this.selectedSection,
    required this.onSectionChanged,
  });

  final ScheduleSection selectedSection;
  final ValueChanged<ScheduleSection> onSectionChanged;

  @override
  Widget build(BuildContext context) {
    AppColors.of(context);
    return CupertinoSlidingSegmentedControl<ScheduleSection>(
      groupValue: selectedSection,
      backgroundColor: AppColors.surfaceElevated,
      thumbColor: AppColors.primary,
      padding: const EdgeInsets.all(3),
      children: {
        for (final entry in _labels.entries)
          entry.key: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 7,
            ),
            child: Text(
              entry.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSmall.copyWith(
                color: selectedSection == entry.key
                    ? AppColors.onPrimary
                    : AppColors.textPrimary,
              ),
            ),
          ),
      },
      onValueChanged: (section) {
        if (section != null && section != selectedSection) {
          onSectionChanged(section);
        }
      },
    );
  }
}

const _labels = {
  ScheduleSection.calendar: '일정',
  ScheduleSection.recurring: '반복 일정',
  ScheduleSection.anniversary: '기념일',
  ScheduleSection.holiday: '공휴일',
};
