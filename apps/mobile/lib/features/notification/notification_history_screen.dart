import 'package:flutter/cupertino.dart';

import '../../core/api_client.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_spacing.dart';
import '../../design_system/app_typography.dart';
import '../../shared/refreshable_scroll_view.dart';

class NotificationHistoryScreen extends StatefulWidget {
  const NotificationHistoryScreen({super.key, required this.sessionToken});

  final String sessionToken;

  @override
  State<NotificationHistoryScreen> createState() =>
      _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState extends State<NotificationHistoryScreen> {
  final _apiClient = ApiClient();

  List<PushNotificationHistoryItem> _notifications = const [];
  String? _message;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final notifications = await _apiClient.getPushNotificationHistory(
        widget.sessionToken,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _notifications = notifications;
      });
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
    AppColors.of(context);
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('알림')),
      child: SafeArea(
        child: _isLoading
            ? const Center(child: CupertinoActivityIndicator())
            : RefreshableScrollView(
                onRefresh: _loadNotifications,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  18,
                  AppSpacing.page,
                  28,
                ),
                children: [
                  if (_message != null)
                    _NotificationMessage(
                      message: _message!,
                      onRetry: _loadNotifications,
                    )
                  else if (_notifications.isEmpty)
                    const _NotificationEmptyState()
                  else
                    ..._notifications.map(
                      (notification) =>
                          _NotificationHistoryTile(notification: notification),
                    ),
                ],
              ),
      ),
    );
  }
}

class _NotificationHistoryTile extends StatelessWidget {
  const _NotificationHistoryTile({required this.notification});

  final PushNotificationHistoryItem notification;

  @override
  Widget build(BuildContext context) {
    AppColors.of(context);
    final familyName = notification.familyName;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
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
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              _notificationIcon(notification.type),
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  notification.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  [
                    if (familyName != null && familyName.isNotEmpty) familyName,
                    _formatSentAt(notification.sentAt),
                  ].join(' · '),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textMuted,
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

class _NotificationEmptyState extends StatelessWidget {
  const _NotificationEmptyState();

  @override
  Widget build(BuildContext context) {
    AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 112),
      child: Center(
        child: Column(
          children: [
            Icon(
              CupertinoIcons.bell_slash,
              color: AppColors.textMuted,
              size: 34,
            ),
            const SizedBox(height: 14),
            Text(
              '받은 알림이 없습니다.',
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

class _NotificationMessage extends StatelessWidget {
  const _NotificationMessage({required this.message, required this.onRetry});

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
          style: AppTypography.labelSmall.copyWith(color: AppColors.danger),
        ),
        const SizedBox(height: AppSpacing.md),
        CupertinoButton(
          color: AppColors.surfaceElevated,
          onPressed: onRetry,
          child: Text(
            '다시 시도',
            style: AppTypography.label.copyWith(color: AppColors.primary),
          ),
        ),
      ],
    );
  }
}

IconData _notificationIcon(String type) {
  return switch (type) {
    'schedule_alert' => CupertinoIcons.calendar,
    _ => CupertinoIcons.bell,
  };
}

String _formatSentAt(DateTime sentAt) {
  final now = DateTime.now();

  if (_isSameDate(now, sentAt)) {
    return '오늘 ${_twoDigits(sentAt.hour)}:${_twoDigits(sentAt.minute)}';
  }

  final yesterday = now.subtract(const Duration(days: 1));
  if (_isSameDate(yesterday, sentAt)) {
    return '어제 ${_twoDigits(sentAt.hour)}:${_twoDigits(sentAt.minute)}';
  }

  if (now.year == sentAt.year) {
    return '${sentAt.month}월 ${sentAt.day}일 ${_twoDigits(sentAt.hour)}:${_twoDigits(sentAt.minute)}';
  }

  return '${sentAt.year}.${_twoDigits(sentAt.month)}.${_twoDigits(sentAt.day)}';
}

bool _isSameDate(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
