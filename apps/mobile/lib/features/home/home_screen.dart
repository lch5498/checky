import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../family/family_screen.dart';
import '../parking/parking_screen.dart';
import '../profile/profile_screen.dart';
import '../schedule/schedule_screen.dart';

const _preferencesChannel = MethodChannel('housekeeping/preferences');
const _selectedFamilyPreferenceKey = 'selectedFamilyId';

class HomeScreen extends StatefulWidget {
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
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _apiClient = ApiClient();

  List<FamilySummary> _families = const [];
  String? _selectedFamilyId;
  String? _message;
  bool _isLoadingFamilies = true;

  AppFamily? get _selectedFamily {
    if (_families.isEmpty) {
      return null;
    }

    for (final summary in _families) {
      if (summary.family.id == _selectedFamilyId) {
        return summary.family;
      }
    }

    return _families.first.family;
  }

  @override
  void initState() {
    super.initState();
    _loadFamilies();
  }

  Future<void> _loadFamilies() async {
    setState(() {
      _isLoadingFamilies = true;
      _message = null;
    });

    try {
      final preferredFamilyId =
          _selectedFamilyId ?? await _readSelectedFamilyId();
      final families = await _apiClient.listFamilies(widget.sessionToken);
      final selectedFamilyId = _resolveSelectedFamilyId(
        families,
        preferredFamilyId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _families = families;
        _selectedFamilyId = selectedFamilyId;
      });

      if (selectedFamilyId != null) {
        await _saveSelectedFamilyId(selectedFamilyId);
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
          _isLoadingFamilies = false;
        });
      }
    }
  }

  String? _resolveSelectedFamilyId(
    List<FamilySummary> families,
    String? preferredFamilyId,
  ) {
    if (families.isEmpty) {
      return null;
    }

    if (preferredFamilyId != null &&
        families.any((summary) => summary.family.id == preferredFamilyId)) {
      return preferredFamilyId;
    }

    return families.first.family.id;
  }

  Future<String?> _readSelectedFamilyId() async {
    try {
      return await _preferencesChannel.invokeMethod<String>('getString', {
        'key': _selectedFamilyPreferenceKey,
      });
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _saveSelectedFamilyId(String familyId) async {
    try {
      await _preferencesChannel.invokeMethod<void>('setString', {
        'key': _selectedFamilyPreferenceKey,
        'value': familyId,
      });
    } on MissingPluginException {
      return;
    }
  }

  Future<void> _openFamilyManagement() async {
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => FamilyScreen(
          sessionToken: widget.sessionToken,
          currentUserId: widget.user.id,
        ),
      ),
    );
    await _loadFamilies();
  }

  Future<void> _switchFamily() async {
    if (_families.length < 2) {
      return;
    }

    final selectedFamilyId = await showCupertinoModalPopup<String>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('가족 전환'),
        actions: _families
            .map(
              (summary) => CupertinoActionSheetAction(
                isDefaultAction: summary.family.id == _selectedFamilyId,
                onPressed: () => Navigator.of(context).pop(summary.family.id),
                child: Text(summary.family.name),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
      ),
    );

    if (selectedFamilyId == null) {
      return;
    }

    setState(() {
      _selectedFamilyId = selectedFamilyId;
    });
    await _saveSelectedFamilyId(selectedFamilyId);
  }

  @override
  Widget build(BuildContext context) {
    final selectedFamily = _selectedFamily;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: _HomeTitle(
          family: selectedFamily,
          canSwitch: _families.length > 1,
          onPressed: _switchFamily,
        ),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 32),
          onPressed: _openFamilyManagement,
          child: const Icon(CupertinoIcons.person_2),
        ),
        trailing: widget.onLogout == null
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
                            user: widget.user,
                            onSave: widget.onUpdateProfile,
                          ),
                        ),
                      );
                    },
                    child: const Icon(CupertinoIcons.person_crop_circle),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(32, 32),
                    onPressed: widget.onLogout,
                    child: const Icon(CupertinoIcons.square_arrow_right),
                  ),
                ],
              ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: _HomeBody(
            user: widget.user,
            sessionToken: widget.sessionToken,
            selectedFamily: selectedFamily,
            message: _message,
            isLoadingFamilies: _isLoadingFamilies,
            onReloadFamilies: _loadFamilies,
            onOpenFamilyManagement: _openFamilyManagement,
          ),
        ),
      ),
    );
  }
}

class _HomeTitle extends StatelessWidget {
  const _HomeTitle({
    required this.family,
    required this.canSwitch,
    required this.onPressed,
  });

  final AppFamily? family;
  final bool canSwitch;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final family = this.family;

    if (family == null) {
      return const Text('House Keeping');
    }

    if (!canSwitch) {
      return Text(
        family.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          inherit: false,
          color: Color(0xFF111111),
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
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
              family.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                inherit: false,
                color: Color(0xFF111111),
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          if (canSwitch) ...[
            const SizedBox(width: 4),
            const Icon(CupertinoIcons.chevron_down, size: 15),
          ],
        ],
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({
    required this.user,
    required this.sessionToken,
    required this.selectedFamily,
    required this.message,
    required this.isLoadingFamilies,
    required this.onReloadFamilies,
    required this.onOpenFamilyManagement,
  });

  final AppUser user;
  final String sessionToken;
  final AppFamily? selectedFamily;
  final String? message;
  final bool isLoadingFamilies;
  final Future<void> Function() onReloadFamilies;
  final VoidCallback onOpenFamilyManagement;

  @override
  Widget build(BuildContext context) {
    if (isLoadingFamilies) {
      return const Center(child: CupertinoActivityIndicator());
    }

    final selectedFamily = this.selectedFamily;

    if (selectedFamily == null) {
      return _FamilyRequiredIntro(
        userNickname: user.nickname,
        message: message,
        onReloadFamilies: onReloadFamilies,
        onOpenFamilyManagement: onOpenFamilyManagement,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HomeHeader(
          userNickname: user.nickname,
          familyName: selectedFamily.name,
        ),
        if (message != null) ...[
          const SizedBox(height: 14),
          _InlineMessage(message: message!),
        ],
        const SizedBox(height: 22),
        Expanded(
          child: _HomeMenuTile(
            icon: CupertinoIcons.calendar,
            title: '학원 일정 관리',
            subtitle: '${selectedFamily.name} 가족의 수업 시간과 이동 일정을 봅니다.',
            accentColor: CupertinoColors.systemTeal,
            backgroundColor: const Color(0xFFE6F3F1),
            onPressed: () {
              Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) => ScheduleScreen(
                    family: selectedFamily,
                    sessionToken: sessionToken,
                  ),
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
            subtitle: '${selectedFamily.name} 가족의 차량과 주차 위치를 관리합니다.',
            accentColor: CupertinoColors.systemOrange,
            backgroundColor: const Color(0xFFFFF0E5),
            onPressed: () {
              Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) => ParkingScreen(
                    family: selectedFamily,
                    sessionToken: sessionToken,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FamilyRequiredIntro extends StatelessWidget {
  const _FamilyRequiredIntro({
    required this.userNickname,
    required this.message,
    required this.onReloadFamilies,
    required this.onOpenFamilyManagement,
  });

  final String userNickname;
  final String? message;
  final Future<void> Function() onReloadFamilies;
  final VoidCallback onOpenFamilyManagement;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 24),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: CupertinoColors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            CupertinoIcons.person_2_fill,
            color: CupertinoColors.systemTeal,
            size: 34,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          '$userNickname님, 가족을 먼저 등록해 주세요.',
          style: const TextStyle(
            color: Color(0xFF111111),
            fontSize: 30,
            fontWeight: FontWeight.w800,
            height: 1.12,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'House Keeping의 학원 일정, 차량, 주차 기록은 모두 가족 단위로 저장됩니다. 가족을 만들거나 초대 링크를 수락하면 홈에서 기능을 사용할 수 있습니다.',
          style: TextStyle(
            color: Color(0xFF6E6E73),
            fontSize: 16,
            height: 1.45,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 22),
        if (message != null) ...[
          _InlineMessage(message: message!),
          const SizedBox(height: 14),
        ],
        SizedBox(
          height: 54,
          child: CupertinoButton.filled(
            borderRadius: BorderRadius.circular(14),
            onPressed: onOpenFamilyManagement,
            child: const Text(
              '가족 등록하기',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 50,
          child: CupertinoButton(
            color: CupertinoColors.white,
            borderRadius: BorderRadius.circular(14),
            onPressed: onReloadFamilies,
            child: const Text(
              '가족 목록 새로고침',
              style: TextStyle(
                color: CupertinoColors.systemTeal,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.userNickname, required this.familyName});

  final String userNickname;
  final String familyName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$familyName 가족',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: CupertinoColors.systemGrey,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$userNickname님, 오늘 뭐부터 볼까요?',
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

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          message,
          style: const TextStyle(
            color: Color(0xFFB42318),
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
