import 'package:flutter/cupertino.dart';

import '../../core/api_client.dart';
import '../../core/theme_preference.dart';
import '../../design_system/app_colors.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.user,
    required this.onSave,
    required this.onDeleteAccount,
    this.onLogout,
  });

  final AppUser user;
  final Future<AppUser> Function(String nickname) onSave;
  final Future<void> Function() onDeleteAccount;
  final Future<void> Function()? onLogout;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nicknameController;

  String? _message;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.user.nickname);
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nickname = _nicknameController.text.trim();

    if (nickname.isEmpty) {
      setState(() {
        _message = '닉네임을 입력해 주세요.';
      });
      return;
    }

    if (nickname.length > 30) {
      setState(() {
        _message = '닉네임은 30자 이하로 입력해 주세요.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      await widget.onSave(nickname);

      if (mounted) {
        Navigator.of(context).pop();
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
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return CupertinoAlertDialog(
          title: Text('로그아웃할까요?'),
          content: Text('다시 사용하려면 카카오 로그인이 필요합니다.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('취소'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('로그아웃'),
            ),
          ],
        );
      },
    );

    final onLogout = widget.onLogout;

    if (shouldLogout != true || !mounted || onLogout == null) {
      return;
    }

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }

    await onLogout();
  }

  Future<void> _confirmDeleteAccount() async {
    final shouldDelete = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return CupertinoAlertDialog(
          title: Text('탈퇴할까요?'),
          content: Text('모든 데이터가 삭제되며 복구되지 않습니다. 정말 탈퇴할까요?'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('취소'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('탈퇴하기'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !mounted) {
      return;
    }

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      await widget.onDeleteAccount();

      if (mounted) {
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
        }
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
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themePreferenceController = ThemePreferenceScope.of(context);

    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text('프로필'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 32),
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const CupertinoActivityIndicator()
              : Text(
                  '저장',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Text(
              '가족에게 보일 이름',
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                height: 1.12,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '카카오 계정 이름과 별개로 체키 안에서만 사용하는 이름입니다.',
              style: TextStyle(
                color: AppColors.darkTextSecondary,
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 26),
            CupertinoTextField(
              controller: _nicknameController,
              autofocus: true,
              clearButtonMode: OverlayVisibilityMode.editing,
              maxLength: 30,
              placeholder: '닉네임',
              textInputAction: TextInputAction.done,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
              decoration: BoxDecoration(
                color: AppColors.darkSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.darkBorder),
              ),
              onSubmitted: (_) => _save(),
            ),
            if (_message != null) ...[
              const SizedBox(height: 14),
              _ProfileMessage(message: _message!),
            ],
            const SizedBox(height: 28),
            _ThemePreferenceSelector(controller: themePreferenceController),
            const SizedBox(height: 34),
            if (widget.onLogout != null) ...[
              _ProfileTextAction(
                label: '로그아웃',
                onPressed: _isSaving ? null : _confirmLogout,
              ),
              const SizedBox(height: 8),
            ],
            _ProfileTextAction(
              label: '탈퇴하기',
              isDestructive: true,
              onPressed: _isSaving ? null : _confirmDeleteAccount,
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemePreferenceSelector extends StatelessWidget {
  const _ThemePreferenceSelector({required this.controller});

  final ThemePreferenceController controller;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '화면 모드',
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '기기 설정을 따르거나 직접 밝기를 고를 수 있어요.',
              style: TextStyle(
                color: AppColors.darkTextSecondary,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
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
          ],
        ),
      ),
    );
  }
}

class _ProfileTextAction extends StatelessWidget {
  const _ProfileTextAction({
    required this.label,
    required this.onPressed,
    this.isDestructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: Size.zero,
        onPressed: onPressed,
        child: Text(
          label,
          style: TextStyle(
            color:
                (isDestructive
                        ? CupertinoColors.destructiveRed
                        : AppColors.darkTextMuted)
                    .withValues(alpha: onPressed == null ? 0.35 : 0.78),
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _ProfileMessage extends StatelessWidget {
  const _ProfileMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
      ),
    );
  }
}
