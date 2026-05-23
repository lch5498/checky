import 'package:flutter/cupertino.dart';

import '../../core/api_client.dart';
import '../family/family_screen.dart';
import '../parking/parking_screen.dart';
import '../profile/profile_screen.dart';
import '../schedule/schedule_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.user,
    required this.sessionToken,
    required this.onUpdateProfile,
    this.onLogout,
  });

  final AppUser user;
  final String sessionToken;
  final Future<AppUser> Function(String nickname) onUpdateProfile;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('House Keeping'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 32),
          onPressed: () {
            Navigator.of(context).push(
              CupertinoPageRoute<void>(
                builder: (_) => FamilyScreen(
                  sessionToken: sessionToken,
                  currentUserId: user.id,
                ),
              ),
            );
          },
          child: const Icon(CupertinoIcons.person_2),
        ),
        trailing: onLogout == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(32, 32),
                    onPressed: () {
                      Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (_) => ProfileScreen(
                            user: user,
                            onSave: onUpdateProfile,
                          ),
                        ),
                      );
                    },
                    child: const Icon(CupertinoIcons.person_crop_circle),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(32, 32),
                    onPressed: onLogout,
                    child: const Icon(CupertinoIcons.square_arrow_right),
                  ),
                ],
              ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HomeHeader(userNickname: user.nickname),
              const SizedBox(height: 22),
              Expanded(
                child: _HomeMenuTile(
                  icon: CupertinoIcons.calendar,
                  title: '학원 일정 관리',
                  subtitle: '수업 시간과 이동 일정을 한 곳에서 봅니다.',
                  accentColor: CupertinoColors.systemTeal,
                  backgroundColor: const Color(0xFFE6F3F1),
                  onPressed: () {
                    Navigator.of(context).push(
                      CupertinoPageRoute<void>(
                        builder: (_) => const ScheduleScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: _HomeMenuTile(
                  icon: CupertinoIcons.car_detailed,
                  title: '주차 관리',
                  subtitle: '현재 주차 위치를 빠르게 기록합니다.',
                  accentColor: CupertinoColors.systemOrange,
                  backgroundColor: const Color(0xFFFFF0E5),
                  onPressed: () {
                    Navigator.of(context).push(
                      CupertinoPageRoute<void>(
                        builder: (_) => const ParkingScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.userNickname});

  final String? userNickname;

  @override
  Widget build(BuildContext context) {
    final greeting = userNickname == null
        ? '오늘 뭐부터 볼까요?'
        : '$userNickname님, 오늘 뭐부터 볼까요?';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '집안일을 조금 더 가볍게',
          style: TextStyle(
            color: CupertinoColors.systemGrey,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          greeting,
          style: const TextStyle(
            color: Color(0xFF111111),
            fontSize: 30,
            fontWeight: FontWeight.w800,
            height: 1.12,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _HomeMenuTile extends StatelessWidget {
  const _HomeMenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.backgroundColor,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final Color backgroundColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(18),
      onPressed: onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: CupertinoColors.white,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: accentColor, size: 28),
                ),
                const Spacer(),
                Icon(
                  CupertinoIcons.chevron_forward,
                  color: accentColor,
                  size: 22,
                ),
              ],
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF111111),
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF5F6368),
                fontSize: 14,
                height: 1.3,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
