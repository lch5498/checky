import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Theme;

import '../../core/api_client.dart';
import '../../core/theme_preference.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_radius.dart';
import '../../design_system/app_spacing.dart';
import '../../design_system/app_theme_preset.dart';
import '../../design_system/app_typography.dart';
import '../family/family_screen.dart';
import '../profile/profile_screen.dart';
import 'font_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.user,
    required this.sessionToken,
    required this.familyCount,
    required this.onSaveProfile,
    required this.onDeleteAccount,
    required this.currentUserId,
    this.onGroupsChanged,
    this.onLogout,
  });

  final AppUser user;
  final String sessionToken;
  final int familyCount;
  final ProfileSaveCallback onSaveProfile;
  final Future<void> Function() onDeleteAccount;
  final String currentUserId;
  final Future<void> Function()? onGroupsChanged;
  final Future<void> Function()? onLogout;

  void _openProfile(BuildContext context) {
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute<void>(
        builder: (_) => ProfileScreen(
          user: user,
          familyCount: familyCount,
          onSave: onSaveProfile,
          onDeleteAccount: onDeleteAccount,
          onLogout: onLogout,
        ),
      ),
    );
  }

  Future<void> _openGroups(BuildContext context) async {
    await Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute<void>(
        builder: (_) => FamilyScreen(
          sessionToken: sessionToken,
          currentUserId: currentUserId,
        ),
      ),
    );
    await onGroupsChanged?.call();
  }

  void _openTheme(BuildContext context) {
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute<void>(builder: (_) => const ThemeSettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppColors.of(context);
    return CupertinoPageScaffold(
      backgroundColor: AppColors.background,
      navigationBar: const CupertinoNavigationBar(middle: Text('설정')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            18,
            AppSpacing.page,
            AppSpacing.xxl,
          ),
          children: [
            _SettingsMenuRow(
              icon: CupertinoIcons.person,
              title: '내 정보 관리',
              subtitle: '프로필 이름, 로그아웃, 탈퇴하기',
              onPressed: () => _openProfile(context),
            ),
            _SettingsMenuRow(
              icon: CupertinoIcons.person_2,
              title: '그룹 관리',
              subtitle: '그룹과 그룹 구성원을 관리해요',
              onPressed: () => _openGroups(context),
            ),
            _SettingsMenuRow(
              icon: CupertinoIcons.sun_max,
              title: '화면 설정',
              subtitle: '테마, 글꼴과 라이트·다크 모드를 설정해요',
              onPressed: () => _openTheme(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsMenuRow extends StatelessWidget {
  const _SettingsMenuRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    AppColors.of(context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 21),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.label.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle,
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_forward,
              color: CupertinoColors.systemGrey3,
              size: 17,
            ),
          ],
        ),
      ),
    );
  }
}

class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final controller = ThemePreferenceScope.of(context);
    final brightness = Theme.of(context).brightness;

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: const CupertinoNavigationBar(middle: Text('화면 설정')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.xl,
            AppSpacing.page,
            AppSpacing.xxl,
          ),
          children: [
            Text(
              '화면 모드',
              style: AppTypography.titleMedium.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: colors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoSlidingSegmentedControl<AppThemePreference>(
                    groupValue: controller.preference,
                    backgroundColor: colors.surfaceElevated,
                    thumbColor: colors.surface,
                    children: {
                      for (final preference in AppThemePreference.values)
                        preference: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.md,
                          ),
                          child: Text(
                            preference.label,
                            style: AppTypography.labelSmall.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                    },
                    onValueChanged: (preference) {
                      if (preference != null) {
                        controller.setPreference(preference);
                      }
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            CupertinoButton(
              key: const ValueKey('open-font-settings'),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              onPressed: () => Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) => const FontSettingsScreen(),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '글꼴',
                      style: AppTypography.titleMedium.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    controller.font.label,
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
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              '테마',
              style: AppTypography.titleMedium.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final preset in AppThemePreset.values) ...[
              _ThemePresetOption(
                preset: preset,
                brightness: brightness,
                selected: controller.preset == preset,
                onPressed: () => controller.setPreset(preset),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThemePresetOption extends StatelessWidget {
  const _ThemePresetOption({
    required this.preset,
    required this.brightness,
    required this.selected,
    required this.onPressed,
  });

  final AppThemePreset preset;
  final Brightness brightness;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final preview = preset.colors(brightness);

    return Semantics(
      selected: selected,
      button: true,
      child: CupertinoButton(
        key: ValueKey('theme-preset-${preset.storageValue}'),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? colors.primary : colors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 76,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: preview.background,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: preview.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 20,
                        height: 6,
                        decoration: BoxDecoration(
                          color: preview.primary,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        height: 24,
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: preview.surface,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        child: Row(
                          children: [
                            Container(width: 3, color: preview.primary),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Container(
                                height: 3,
                                color: preview.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Text(
                  preset.label,
                  style: AppTypography.titleSmall.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Icon(
                selected
                    ? CupertinoIcons.check_mark_circled_solid
                    : CupertinoIcons.circle,
                color: selected ? colors.primary : colors.textMuted,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
