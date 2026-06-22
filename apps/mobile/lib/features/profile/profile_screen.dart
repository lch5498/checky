import 'package:flutter/cupertino.dart';

import '../../core/api_client.dart';
import '../../design_system/app_colors.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.user, required this.onSave});

  final AppUser user;
  final Future<AppUser> Function(String nickname) onSave;

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

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('프로필'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 32),
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const CupertinoActivityIndicator()
              : const Text(
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
            const Text(
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
            const Text(
              '카카오 계정 이름과 별개로 파비스 안에서만 사용하는 이름입니다.',
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
              style: const TextStyle(
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
            const SizedBox(height: 24),
            SizedBox(
              height: 54,
              child: CupertinoButton.filled(
                borderRadius: BorderRadius.circular(14),
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const CupertinoActivityIndicator(
                        color: CupertinoColors.white,
                      )
                    : const Text(
                        '변경사항 저장',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
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
          style: const TextStyle(
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
