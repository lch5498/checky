import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Theme;

import '../../core/api_client.dart';
import '../../core/theme_preference.dart';
import '../../design_system/app_colors.dart';
import '../family/family_screen.dart';
import '../profile/profile_screen.dart';

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
    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: const CupertinoNavigationBar(middle: Text('설정')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
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
              subtitle: '라이트 모드와 다크 모드를 설정해요',
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
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.darkBorder)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.darkPrimary, size: 21),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.darkTextPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
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
    final controller = ThemePreferenceScope.of(context);
    AppColors.useBrightness(Theme.of(context).brightness);

    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: const CupertinoNavigationBar(middle: Text('화면 설정')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Text(
              '화면 모드',
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '기기 설정을 따르거나 직접 밝기를 고를 수 있어요.',
              style: TextStyle(
                color: AppColors.darkTextSecondary,
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 26),
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.darkSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoSlidingSegmentedControl<AppThemePreference>(
                    groupValue: controller.preference,
                    children: {
                      for (final preference in AppThemePreference.values)
                        preference: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 7,
                          ),
                          child: Text(
                            preference.label,
                            style: TextStyle(
                              color: AppColors.darkTextPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
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
          ],
        ),
      ),
    );
  }
}
