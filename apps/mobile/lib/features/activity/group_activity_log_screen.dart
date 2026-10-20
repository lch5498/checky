import 'package:flutter/cupertino.dart';

import '../../core/api_client.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_spacing.dart';
import '../../design_system/app_typography.dart';
import '../../shared/refreshable_scroll_view.dart';
import '../education/education_screen.dart';
import '../schedule/schedule_screen.dart';
import '../scrap/scrap_screen.dart';
import '../travel/travel_screen.dart';
import 'group_activity_read_state.dart';

class GroupActivityLogScreen extends StatefulWidget {
  const GroupActivityLogScreen({
    super.key,
    required this.sessionToken,
    required this.family,
    this.onOpenParkingTab,
  });

  final String sessionToken;
  final AppFamily family;
  final VoidCallback? onOpenParkingTab;

  @override
  State<GroupActivityLogScreen> createState() => _GroupActivityLogScreenState();
}

class _GroupActivityLogScreenState extends State<GroupActivityLogScreen> {
  final _apiClient = ApiClient();

  List<GroupActivityItem> _activities = const [];
  GroupActivityType _selectedType = GroupActivityType.all;
  String? _message;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final activities = await _apiClient.getGroupActivities(
        widget.sessionToken,
        familyId: widget.family.id,
      );
      if (activities.isNotEmpty) {
        try {
          await GroupActivityReadState.markRead(
            familyId: widget.family.id,
            readAt: activities.first.createdAt,
          );
        } catch (_) {
          // 읽음 시각 저장에 실패해도 활동 목록은 계속 보여 준다.
        }
      }
      if (mounted) {
        setState(() {
          _activities = activities;
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

  Future<void> _openActivity(GroupActivityItem activity) async {
    final target = activity.target;

    if (target == null) {
      return;
    }

    try {
      switch (target.type) {
        case GroupActivityTargetType.schedule:
          await Navigator.of(context).push(
            CupertinoPageRoute<void>(
              builder: (_) => ScheduleScreen(
                family: widget.family,
                families: [widget.family],
                sessionToken: widget.sessionToken,
                refreshToken: 0,
                todayRequestToken: 0,
                initialDate: target.startsAt,
                onSelectFamily: (_) async {},
              ),
            ),
          );
        case GroupActivityTargetType.recurringSchedule:
          await Navigator.of(context).push(
            CupertinoPageRoute<void>(
              builder: (_) => EducationScreen(
                family: widget.family,
                families: [widget.family],
                sessionToken: widget.sessionToken,
                onSelectFamily: (_) async {},
              ),
            ),
          );
        case GroupActivityTargetType.parkingVehicle:
          final onOpenParkingTab = widget.onOpenParkingTab;
          if (onOpenParkingTab == null) {
            return;
          }
          Navigator.of(context).pop();
          onOpenParkingTab();
        case GroupActivityTargetType.scrapPost:
          final channelId = target.parentId;
          if (channelId == null) {
            return;
          }
          final dashboard = await _apiClient.getScrapDashboard(
            widget.sessionToken,
            familyId: widget.family.id,
          );
          ScrapChannel? channel;
          for (final candidate in dashboard.channels) {
            if (candidate.id == channelId) {
              channel = candidate;
              break;
            }
          }
          if (channel == null || !mounted) {
            return;
          }
          await Navigator.of(context).push(
            CupertinoPageRoute<void>(
              builder: (_) => ScrapChannelScreen(
                family: widget.family,
                sessionToken: widget.sessionToken,
                channel: channel!,
              ),
            ),
          );
        case GroupActivityTargetType.travelTrip:
          final detail = await _apiClient.getTravelTripDetail(
            widget.sessionToken,
            familyId: widget.family.id,
            tripId: target.id,
          );
          if (!mounted) {
            return;
          }
          await Navigator.of(context).push(
            CupertinoPageRoute<void>(
              builder: (_) => TravelDetailScreen(
                family: widget.family,
                sessionToken: widget.sessionToken,
                trip: detail.trip,
              ),
            ),
          );
        case GroupActivityTargetType.travelItinerary:
          final tripId = target.parentId;
          if (tripId == null) {
            return;
          }
          final detail = await _apiClient.getTravelTripDetail(
            widget.sessionToken,
            familyId: widget.family.id,
            tripId: tripId,
          );
          if (!mounted) {
            return;
          }
          await Navigator.of(context).push(
            CupertinoPageRoute<void>(
              builder: (_) => TravelDetailScreen(
                family: widget.family,
                sessionToken: widget.sessionToken,
                trip: detail.trip,
                initialItineraryId: target.id,
              ),
            ),
          );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('활동을 열 수 없습니다'),
          content: const Text('대상이 수정되었거나 더 이상 존재하지 않습니다.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    AppColors.of(context);
    final activities = _selectedType == GroupActivityType.all
        ? _activities
        : _activities.where((item) => item.type == _selectedType).toList();

    return CupertinoPageScaffold(
      backgroundColor: AppColors.background,
      navigationBar: const CupertinoNavigationBar(middle: Text('그룹 활동')),
      child: SafeArea(
        child: _isLoading
            ? const Center(child: CupertinoActivityIndicator())
            : RefreshableScrollView(
                onRefresh: _loadActivities,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  18,
                  AppSpacing.page,
                  28,
                ),
                children: [
                  Text(
                    '${widget.family.name}의 최근 7일 활동',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ActivityFilter(
                    selectedType: _selectedType,
                    onChanged: (type) {
                      setState(() {
                        _selectedType = type;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  if (_message != null)
                    _ActivityMessage(
                      message: _message!,
                      onRetry: _loadActivities,
                    )
                  else if (activities.isEmpty)
                    _ActivityEmptyState(type: _selectedType)
                  else
                    ...activities.map(
                      (activity) => _ActivityTile(
                        activity: activity,
                        onPressed: activity.target == null
                            ? null
                            : () => _openActivity(activity),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _ActivityFilter extends StatelessWidget {
  const _ActivityFilter({required this.selectedType, required this.onChanged});

  final GroupActivityType selectedType;
  final ValueChanged<GroupActivityType> onChanged;

  @override
  Widget build(BuildContext context) {
    AppColors.of(context);
    return SizedBox(
      width: double.infinity,
      child: CupertinoSlidingSegmentedControl<GroupActivityType>(
        groupValue: selectedType,
        backgroundColor: AppColors.surfaceElevated,
        thumbColor: AppColors.primary,
        onValueChanged: (value) {
          if (value != null) {
            onChanged(value);
          }
        },
        children: {
          for (final type in GroupActivityType.values)
            type: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                _activityTypeLabel(type),
                style: AppTypography.caption.copyWith(
                  color: selectedType == type
                      ? AppColors.onPrimary
                      : AppColors.textPrimary,
                ),
              ),
            ),
        },
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity, required this.onPressed});

  final GroupActivityItem activity;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    AppColors.of(context);
    final color = _activityColor(activity.type);

    final child = Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(_activityIcon(activity.type), color: color, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${activity.actorNickname ?? '알 수 없음'} · ${activity.detail}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  _activityTimeText(activity.createdAt),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (onPressed != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Icon(
              CupertinoIcons.chevron_right,
              color: AppColors.textMuted,
              size: 16,
            ),
          ],
        ],
      ),
    );

    if (onPressed == null) {
      return child;
    }

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: child,
    );
  }
}

class _ActivityEmptyState extends StatelessWidget {
  const _ActivityEmptyState({required this.type});

  final GroupActivityType type;

  @override
  Widget build(BuildContext context) {
    AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 112),
      child: Center(
        child: Column(
          children: [
            Icon(CupertinoIcons.clock, color: AppColors.textMuted, size: 34),
            const SizedBox(height: 14),
            Text(
              type == GroupActivityType.all
                  ? '최근 활동이 없습니다.'
                  : '${_activityTypeLabel(type)} 활동이 없습니다.',
              style: AppTypography.label.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityMessage extends StatelessWidget {
  const _ActivityMessage({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    AppColors.of(context);
    return Column(
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(color: AppColors.danger),
        ),
        CupertinoButton(onPressed: onRetry, child: const Text('다시 시도')),
      ],
    );
  }
}

String _activityTypeLabel(GroupActivityType type) {
  return switch (type) {
    GroupActivityType.all => '전체',
    GroupActivityType.schedule => '일정',
    GroupActivityType.parking => '주차',
    GroupActivityType.scrap => '스크랩',
    GroupActivityType.travel => '여행',
  };
}

IconData _activityIcon(GroupActivityType type) {
  return switch (type) {
    GroupActivityType.all => CupertinoIcons.clock,
    GroupActivityType.schedule => CupertinoIcons.calendar,
    GroupActivityType.parking => CupertinoIcons.car_detailed,
    GroupActivityType.scrap => CupertinoIcons.bookmark,
    GroupActivityType.travel => CupertinoIcons.airplane,
  };
}

Color _activityColor(GroupActivityType type) {
  return switch (type) {
    GroupActivityType.all => AppColors.textMuted,
    GroupActivityType.schedule => CupertinoColors.systemBlue,
    GroupActivityType.parking => CupertinoColors.systemOrange,
    GroupActivityType.scrap => CupertinoColors.systemPurple,
    GroupActivityType.travel => AppColors.primary,
  };
}

String _activityTimeText(DateTime value) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(value.year, value.month, value.day);
  final time = '${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';
  if (target == today) {
    return '오늘 $time';
  }
  if (target == today.subtract(const Duration(days: 1))) {
    return '어제 $time';
  }
  return '${value.month}월 ${value.day}일 $time';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
