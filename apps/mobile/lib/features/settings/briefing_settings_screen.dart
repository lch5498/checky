import 'package:flutter/cupertino.dart';

import '../../core/api_client.dart';
import '../../core/briefing_settings.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_radius.dart';
import '../../design_system/app_spacing.dart';
import '../../design_system/app_typography.dart';

/// The time picker steps in 10 minutes; the API accepts any minute.
const _minuteInterval = 10;

class BriefingSettingsScreen extends StatefulWidget {
  const BriefingSettingsScreen({
    super.key,
    required this.sessionToken,
    ApiClient? apiClient,
  }) : _apiClient = apiClient;

  final String sessionToken;
  final ApiClient? _apiClient;

  @override
  State<BriefingSettingsScreen> createState() => _BriefingSettingsScreenState();
}

class _BriefingSettingsScreenState extends State<BriefingSettingsScreen> {
  late final ApiClient _api = widget._apiClient ?? ApiClient();

  BriefingSettings? _settings;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Future<void> Function()? _retry;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _retry = _load;
    });
    try {
      final settings = await _api.getBriefingSettings(widget.sessionToken);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _loading = false;
        _retry = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _describe(error);
      });
    }
  }

  /// Saves immediately; on failure the previous value is restored.
  Future<void> _save(BriefingSettings next) async {
    final previous = _settings;
    if (previous == null || previous == next) return;
    setState(() {
      _settings = next;
      _saving = true;
      _error = null;
      _retry = null;
    });
    try {
      final saved = await _api.updateBriefingSettings(
        widget.sessionToken,
        next,
      );
      if (!mounted) return;
      setState(() {
        _settings = saved;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _settings = previous;
        _saving = false;
        _error = _describe(error);
        _retry = () => _save(next);
      });
    }
  }

  String _describe(Object error) =>
      error is ApiConnectionException ? error.message : '설정을 저장하지 못했습니다.';

  Future<void> _pickTime() async {
    final settings = _settings;
    if (settings == null) return;
    final colors = AppColors.of(context);
    var picked = DateTime(
      2026,
      1,
      1,
      settings.hour,
      settings.minute - settings.minute % _minuteInterval,
    );
    final confirmed = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => Container(
        height: 300,
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        color: colors.surface,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CupertinoButton(
                    key: const ValueKey('briefing-time-done'),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('완료'),
                  ),
                ],
              ),
              Expanded(
                child: CupertinoDatePicker(
                  key: const ValueKey('briefing-time-picker'),
                  mode: CupertinoDatePickerMode.time,
                  minuteInterval: _minuteInterval,
                  use24hFormat: false,
                  initialDateTime: picked,
                  onDateTimeChanged: (value) => picked = value,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await _save(settings.copyWith(hour: picked.hour, minute: picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final settings = _settings;
    final error = _error;

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: const CupertinoNavigationBar(middle: Text('아침 브리핑')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.xl,
            AppSpacing.page,
            AppSpacing.xxl,
          ),
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CupertinoActivityIndicator()),
              ),
            if (error != null) ...[
              _Notice(text: error, onRetry: _retry),
              const SizedBox(height: AppSpacing.md),
            ],
            if (settings != null) ...[
              _SettingsCard(
                children: [
                  _SwitchRow(
                    switchKey: const ValueKey('briefing-enabled'),
                    title: '아침 브리핑 받기',
                    subtitle: '오늘 일정, 주차 위치, 7일 내 만료 쿠폰, 여행 D-N',
                    value: settings.enabled,
                    enabled: !_saving,
                    onChanged: (value) =>
                        _save(settings.copyWith(enabled: value)),
                  ),
                  _Divider(),
                  _ValueRow(
                    key: const ValueKey('briefing-time'),
                    title: '발송 시각',
                    value: settings.sendTimeLabel,
                    onPressed: _saving ? null : _pickTime,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _SettingsCard(
                children: [
                  _SwitchRow(
                    switchKey: const ValueKey('briefing-weekly'),
                    title: '주간 미리보기',
                    subtitle: '일요일 저녁 8시에 다음 주 일정을 보내요',
                    value: settings.weeklyPreviewEnabled,
                    enabled: !_saving,
                    onChanged: (value) =>
                        _save(settings.copyWith(weeklyPreviewEnabled: value)),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                '내가 속한 모든 그룹의 내용을 한 번에 보내요. 시각은 한국 시간 기준이며, '
                '기기 알림이 꺼져 있으면 받을 수 없어요.',
                style: AppTypography.labelSmall.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(children: children),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(height: 1, color: colors.border);
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.switchKey,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final Key switchKey;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.label.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle,
                  style: AppTypography.labelSmall.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          CupertinoSwitch(
            key: switchKey,
            value: value,
            activeTrackColor: colors.primary,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    super.key,
    required this.title,
    required this.value,
    required this.onPressed,
  });

  final String title;
  final String value;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      onPressed: onPressed,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTypography.label.copyWith(color: colors.textPrimary),
            ),
          ),
          Text(
            value,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(
            CupertinoIcons.chevron_forward,
            size: 16,
            color: colors.textMuted,
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.onRetry});

  final String text;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: AppTypography.bodyMedium.copyWith(color: colors.textPrimary),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.sm),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              onPressed: onRetry,
              child: const Text('다시 시도'),
            ),
          ],
        ],
      ),
    );
  }
}
