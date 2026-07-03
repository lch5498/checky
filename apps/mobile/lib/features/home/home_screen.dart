import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/theme_preference.dart';
import '../../design_system/app_colors.dart';
import '../anniversary/anniversary_screen.dart';
import '../education/education_screen.dart';
import '../family/family_screen.dart';
import '../parking/parking_screen.dart';
import '../profile/profile_screen.dart';
import '../schedule/schedule_screen.dart';
import '../../shared/member_filter.dart';
import '../../shared/refreshable_scroll_view.dart';

const _preferencesChannel = MethodChannel('checky/preferences');
const _deepLinkChannel = MethodChannel('checky/deep_links');
const _selectedFamilyPreferenceKey = 'selectedFamilyId';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.user,
    required this.sessionToken,
    required this.onUpdateProfile,
    required this.onDeleteAccount,
    this.initialFamilies,
    this.initialSelectedFamilyId,
    this.initialScheduleDashboard,
    this.initialParkingDashboard,
    this.onLogout,
  });

  final AppUser user;
  final String sessionToken;
  final Future<AppUser> Function(String nickname) onUpdateProfile;
  final Future<void> Function() onDeleteAccount;
  final List<FamilySummary>? initialFamilies;
  final String? initialSelectedFamilyId;
  final ScheduleDashboard? initialScheduleDashboard;
  final ParkingDashboard? initialParkingDashboard;
  final Future<void> Function()? onLogout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _apiClient = ApiClient();
  late final CupertinoTabController _tabController;

  List<FamilySummary> _families = const [];
  String? _selectedFamilyId;
  String? _message;
  bool _isLoadingFamilies = true;
  int _homeRefreshToken = 0;
  int _scheduleRefreshToken = 0;
  int _todayScheduleRequestToken = 0;
  final Set<String> _handledInviteTokens = <String>{};

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
    WidgetsBinding.instance.addObserver(this);
    _tabController = CupertinoTabController();
    _tabController.addListener(_handleTabChange);
    _deepLinkChannel.setMethodCallHandler(_handleDeepLinkMethodCall);
    final initialFamilies = widget.initialFamilies;
    if (initialFamilies != null) {
      _families = initialFamilies;
      _selectedFamilyId = _resolveSelectedFamilyId(
        initialFamilies,
        widget.initialSelectedFamilyId,
      );
      _isLoadingFamilies = false;
    } else {
      _loadFamilies();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumeInviteLinkFromChannel('getInitialLink');
      _consumeInviteLinkFromChannel('getLatestLink');
      _consumeInviteLinkFromChannelLater('getLatestLink');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deepLinkChannel.setMethodCallHandler(null);
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      _consumeInviteLinkFromChannel('getLatestLink');
      _consumeInviteLinkFromChannelLater('getLatestLink');
    }
  }

  void _handleTabChange() {
    if (_tabController.index == 0) {
      setState(() {
        _homeRefreshToken += 1;
      });
    } else if (_tabController.index == 1) {
      setState(() {
        _scheduleRefreshToken += 1;
      });
    }
  }

  void _openScheduleTab() {
    setState(() {
      _todayScheduleRequestToken += 1;
    });
    _tabController.index = 1;
  }

  void _openParkingTab() {
    _tabController.index = 4;
  }

  Future<void> _handleDeepLinkMethodCall(MethodCall call) async {
    if (call.method != 'onLink') {
      return;
    }

    final link = call.arguments as String?;

    if (link == null || link.trim().isEmpty) {
      return;
    }

    await _handleInviteLink(link);
  }

  Future<void> _consumeInviteLinkFromChannelLater(String method) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));

    if (!mounted) {
      return;
    }

    await _consumeInviteLinkFromChannel(method);
  }

  Future<void> _consumeInviteLinkFromChannel(String method) async {
    try {
      final link = await _deepLinkChannel.invokeMethod<String>(method);

      if (!mounted || link == null || link.trim().isEmpty) {
        return;
      }

      await _handleInviteLink(link);
    } on MissingPluginException {
      return;
    }
  }

  Future<void> _handleInviteLink(String link) async {
    final inviteToken = _extractInviteToken(link);

    if (inviteToken.isEmpty || _handledInviteTokens.contains(inviteToken)) {
      return;
    }

    _handledInviteTokens.add(inviteToken);

    final shouldAccept = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text('가족 초대 수락'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('이 초대 링크로 가족에 참여할까요?'),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('취소'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('수락'),
          ),
        ],
      ),
    );

    if (shouldAccept != true || !mounted) {
      _handledInviteTokens.remove(inviteToken);
      return;
    }

    setState(() {
      _isLoadingFamilies = true;
      _message = null;
    });

    try {
      final detail = await _apiClient.acceptFamilyInvitation(
        widget.sessionToken,
        inviteToken: inviteToken,
      );
      await _loadFamilies();

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedFamilyId = detail.family.id;
      });
      await _saveSelectedFamilyId(detail.family.id);

      if (!mounted) {
        return;
      }

      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text('초대 수락 완료'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('${detail.family.name} 가족에 연결되었습니다.'),
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('확인'),
            ),
          ],
        ),
      );
    } catch (error) {
      _handledInviteTokens.remove(inviteToken);

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
      builder: (popupContext) => CupertinoActionSheet(
        title: Text('가족 전환'),
        actions: _families
            .map(
              (summary) => CupertinoActionSheetAction(
                isDefaultAction: summary.family.id == _selectedFamilyId,
                onPressed: () =>
                    Navigator.of(popupContext).pop(summary.family.id),
                child: Text(summary.family.name),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: Text('취소'),
        ),
      ),
    );

    if (selectedFamilyId == null) {
      return;
    }

    final selectedFamily = _families
        .map((summary) => summary.family)
        .firstWhere((family) => family.id == selectedFamilyId);
    await _selectFamily(selectedFamily);
  }

  Future<void> _selectFamily(AppFamily family) async {
    setState(() {
      _selectedFamilyId = family.id;
    });
    await _saveSelectedFamilyId(family.id);
  }

  @override
  Widget build(BuildContext context) {
    ThemePreferenceScope.of(context);
    AppColors.useBrightness(Theme.of(context).brightness);

    final selectedFamily = _selectedFamily;

    if (!_isLoadingFamilies && selectedFamily != null) {
      final families = _families.map((summary) => summary.family).toList();

      return CupertinoTabScaffold(
        controller: _tabController,
        tabBar: CupertinoTabBar(
          backgroundColor: AppColors.darkSurfaceElevated,
          activeColor: AppColors.darkPrimary,
          inactiveColor: AppColors.darkTextMuted,
          iconSize: 24,
          border: Border(top: BorderSide(color: AppColors.darkBorder)),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.house),
              activeIcon: Icon(CupertinoIcons.house_fill),
              label: '홈',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.calendar),
              activeIcon: Icon(CupertinoIcons.calendar_today),
              label: '일정',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.book),
              activeIcon: Icon(CupertinoIcons.book_fill),
              label: '학교/학원',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.gift),
              activeIcon: Icon(CupertinoIcons.gift_fill),
              label: '기념일',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.car_detailed),
              activeIcon: Icon(CupertinoIcons.car_detailed),
              label: '주차',
            ),
          ],
        ),
        tabBuilder: (context, index) {
          return CupertinoTabView(
            key: ValueKey('family-tab-${selectedFamily.id}-$index'),
            builder: (context) {
              switch (index) {
                case 1:
                  return ScheduleScreen(
                    family: selectedFamily,
                    families: families,
                    sessionToken: widget.sessionToken,
                    refreshToken: _scheduleRefreshToken,
                    todayRequestToken: _todayScheduleRequestToken,
                    onSelectFamily: _selectFamily,
                  );
                case 2:
                  return EducationScreen(
                    family: selectedFamily,
                    families: families,
                    sessionToken: widget.sessionToken,
                    onSelectFamily: _selectFamily,
                  );
                case 3:
                  return AnniversaryScreen(
                    family: selectedFamily,
                    families: families,
                    sessionToken: widget.sessionToken,
                    onSelectFamily: _selectFamily,
                  );
                case 4:
                  return ParkingScreen(
                    family: selectedFamily,
                    families: families,
                    sessionToken: widget.sessionToken,
                    onSelectFamily: _selectFamily,
                  );
                case 0:
                default:
                  return _HomeDashboardTab(
                    user: widget.user,
                    sessionToken: widget.sessionToken,
                    family: selectedFamily,
                    families: families,
                    refreshToken: _homeRefreshToken,
                    initialDashboardFamilyId: _resolveSelectedFamilyId(
                      _families,
                      widget.initialSelectedFamilyId,
                    ),
                    initialScheduleDashboard: widget.initialScheduleDashboard,
                    initialParkingDashboard: widget.initialParkingDashboard,
                    message: _message,
                    onOpenFamilyManagement: _openFamilyManagement,
                    onSwitchFamily: _switchFamily,
                    onOpenSchedule: _openScheduleTab,
                    onOpenParking: _openParkingTab,
                    onUpdateProfile: widget.onUpdateProfile,
                    onDeleteAccount: widget.onDeleteAccount,
                    onLogout: widget.onLogout,
                  );
              }
            },
          );
        },
      );
    }

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
        trailing: _HomeNavigationTrailing(
          user: widget.user,
          onUpdateProfile: widget.onUpdateProfile,
          onDeleteAccount: widget.onDeleteAccount,
          onLogout: widget.onLogout,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: _isLoadingFamilies
              ? const Center(child: CupertinoActivityIndicator())
              : _FamilyRequiredIntro(
                  userNickname: widget.user.nickname,
                  message: _message,
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
      return Text('체키');
    }

    if (!canSwitch) {
      return Text(
        family.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          inherit: false,
          color: AppColors.darkTextPrimary,
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
              style: TextStyle(
                inherit: false,
                color: AppColors.darkTextPrimary,
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

class _HomeNavigationTrailing extends StatelessWidget {
  const _HomeNavigationTrailing({
    required this.user,
    required this.onUpdateProfile,
    required this.onDeleteAccount,
    required this.onLogout,
  });

  final AppUser user;
  final Future<AppUser> Function(String nickname) onUpdateProfile;
  final Future<void> Function() onDeleteAccount;
  final Future<void> Function()? onLogout;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(32, 32),
      onPressed: () {
        Navigator.of(context).push(
          CupertinoPageRoute<void>(
            builder: (_) => ProfileScreen(
              user: user,
              onSave: onUpdateProfile,
              onDeleteAccount: onDeleteAccount,
              onLogout: onLogout,
            ),
          ),
        );
      },
      child: const Icon(CupertinoIcons.person_crop_circle),
    );
  }
}

class _HomeDashboardTab extends StatefulWidget {
  const _HomeDashboardTab({
    required this.user,
    required this.sessionToken,
    required this.family,
    required this.families,
    required this.refreshToken,
    required this.initialDashboardFamilyId,
    required this.initialScheduleDashboard,
    required this.initialParkingDashboard,
    required this.message,
    required this.onOpenFamilyManagement,
    required this.onSwitchFamily,
    required this.onOpenSchedule,
    required this.onOpenParking,
    required this.onUpdateProfile,
    required this.onDeleteAccount,
    required this.onLogout,
  });

  final AppUser user;
  final String sessionToken;
  final AppFamily family;
  final List<AppFamily> families;
  final int refreshToken;
  final String? initialDashboardFamilyId;
  final ScheduleDashboard? initialScheduleDashboard;
  final ParkingDashboard? initialParkingDashboard;
  final String? message;
  final VoidCallback onOpenFamilyManagement;
  final VoidCallback onSwitchFamily;
  final VoidCallback onOpenSchedule;
  final VoidCallback onOpenParking;
  final Future<AppUser> Function(String nickname) onUpdateProfile;
  final Future<void> Function() onDeleteAccount;
  final Future<void> Function()? onLogout;

  @override
  State<_HomeDashboardTab> createState() => _HomeDashboardTabState();
}

class _HomeDashboardTabState extends State<_HomeDashboardTab> {
  final _apiClient = ApiClient();

  ScheduleDashboard? _scheduleDashboard;
  ParkingDashboard? _parkingDashboard;
  String? _message;
  bool _isLoading = true;
  int _briefingLoadToken = 0;

  @override
  void initState() {
    super.initState();
    final canUseInitialDashboard =
        widget.initialDashboardFamilyId == widget.family.id;
    _scheduleDashboard = canUseInitialDashboard
        ? widget.initialScheduleDashboard
        : null;
    _parkingDashboard = canUseInitialDashboard
        ? widget.initialParkingDashboard
        : null;
    _isLoading = _scheduleDashboard == null && _parkingDashboard == null;

    if (_isLoading) {
      _loadBriefing();
    }
  }

  @override
  void didUpdateWidget(covariant _HomeDashboardTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.family.id != widget.family.id ||
        oldWidget.sessionToken != widget.sessionToken ||
        oldWidget.refreshToken != widget.refreshToken) {
      setState(() {
        _scheduleDashboard = null;
        _parkingDashboard = null;
        _isLoading = true;
        _message = null;
      });
      _loadBriefing();
    }
  }

  Future<void> _loadBriefing() async {
    final loadToken = ++_briefingLoadToken;
    final familyId = widget.family.id;

    setState(() {
      _isLoading = true;
      _message = null;
    });

    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    try {
      final schedules = await _apiClient.getScheduleDashboard(
        widget.sessionToken,
        familyId: familyId,
        rangeStart: dayStart,
        rangeEnd: dayEnd,
      );
      final parking = await _apiClient.getParkingDashboard(
        widget.sessionToken,
        familyId: familyId,
      );

      if (!mounted || loadToken != _briefingLoadToken) {
        return;
      }

      setState(() {
        _scheduleDashboard = schedules;
        _parkingDashboard = parking;
      });
    } catch (error) {
      if (mounted && loadToken == _briefingLoadToken) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted && loadToken == _briefingLoadToken) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: _HomeTitle(
          family: widget.family,
          canSwitch: widget.families.length > 1,
          onPressed: widget.onSwitchFamily,
        ),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 32),
          onPressed: widget.onOpenFamilyManagement,
          child: const Icon(CupertinoIcons.person_2),
        ),
        trailing: _HomeNavigationTrailing(
          user: widget.user,
          onUpdateProfile: widget.onUpdateProfile,
          onDeleteAccount: widget.onDeleteAccount,
          onLogout: widget.onLogout,
        ),
      ),
      child: SafeArea(
        child: RefreshableScrollView(
          onRefresh: _loadBriefing,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            if (widget.message != null) ...[
              _InlineMessage(message: widget.message!),
              const SizedBox(height: 14),
            ],
            if (_message != null) ...[
              _InlineMessage(message: _message!),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: CupertinoButton(
                  color: AppColors.darkSurfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  onPressed: _loadBriefing,
                  child: Text(
                    '브리핑 새로고침',
                    style: TextStyle(
                      color: AppColors.darkPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (_isLoading &&
                _scheduleDashboard == null &&
                _parkingDashboard == null)
              Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CupertinoActivityIndicator()),
              )
            else ...[
              _ScheduleBriefingSection(
                schedules: _scheduleDashboard?.schedules ?? const [],
                members: _scheduleDashboard?.members ?? const [],
                onPressed: widget.onOpenSchedule,
              ),
              _ParkingBriefingSection(
                dashboard: _parkingDashboard,
                onPressed: widget.onOpenParking,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScheduleBriefingSection extends StatelessWidget {
  const _ScheduleBriefingSection({
    required this.schedules,
    required this.members,
    required this.onPressed,
  });

  final List<AppSchedule> schedules;
  final List<FamilyMember> members;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final orderedSchedules = [...schedules]
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final memberColors = _homeMemberColors(members);

    return _BriefingSection(
      icon: CupertinoIcons.calendar,
      title: '오늘 일정',
      emptyText: '오늘 등록된 일정이 없습니다.',
      isEmpty: orderedSchedules.isEmpty,
      onPressed: onPressed,
      children: orderedSchedules
          .take(4)
          .map(
            (schedule) => _ScheduleBriefingTile(
              schedule: schedule,
              memberColor:
                  memberColors[schedule.familyMemberId] ??
                  MemberFilterColor.gray,
            ),
          )
          .toList(),
    );
  }
}

class _ParkingBriefingSection extends StatelessWidget {
  const _ParkingBriefingSection({
    required this.dashboard,
    required this.onPressed,
  });

  final ParkingDashboard? dashboard;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final parkingDashboard = dashboard;
    final currentLocations = parkingDashboard?.currentLocations ?? const [];
    final vehiclesById = {
      for (final vehicle in parkingDashboard?.vehicles ?? const <Vehicle>[])
        vehicle.id: vehicle,
    };

    return _BriefingSection(
      icon: CupertinoIcons.car_detailed,
      title: '주차 위치',
      emptyText: '등록된 현재 주차 위치가 없습니다.',
      isEmpty: currentLocations.isEmpty,
      onPressed: onPressed,
      children: currentLocations
          .map(
            (record) => _ParkingBriefingTile(
              record: record,
              vehicle: vehiclesById[record.vehicleId],
            ),
          )
          .toList(),
    );
  }
}

class _BriefingSection extends StatelessWidget {
  const _BriefingSection({
    required this.icon,
    required this.title,
    required this.emptyText,
    required this.isEmpty,
    required this.onPressed,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String emptyText;
  final bool isEmpty;
  final VoidCallback onPressed;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.darkBorder)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.darkPrimary, size: 21),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.darkTextPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const Icon(
                  CupertinoIcons.chevron_forward,
                  color: CupertinoColors.systemGrey3,
                  size: 17,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  emptyText,
                  style: TextStyle(
                    color: AppColors.darkTextSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              )
            else
              ...children,
          ],
        ),
      ),
    );
  }
}

class _ScheduleBriefingTile extends StatelessWidget {
  const _ScheduleBriefingTile({
    required this.schedule,
    required this.memberColor,
  });

  final AppSchedule schedule;
  final MemberFilterColor memberColor;

  @override
  Widget build(BuildContext context) {
    final timeText =
        '${_koreanTimeText(schedule.startsAt)}~${_koreanTimeText(schedule.endsAt)}';
    final memberColorStyle = MemberFilterColorStyle.from(memberColor);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              timeText,
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  schedule.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.darkTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 118),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: memberColorStyle.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: memberColorStyle.border),
                    ),
                    child: Text(
                      schedule.memberNickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: memberColorStyle.foreground,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        letterSpacing: 0,
                      ),
                    ),
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

class _ParkingBriefingTile extends StatelessWidget {
  const _ParkingBriefingTile({required this.record, required this.vehicle});

  final ParkingRecord record;
  final Vehicle? vehicle;

  @override
  Widget build(BuildContext context) {
    final vehicleTitle = vehicle == null
        ? '차량'
        : '${vehicle!.nickname} · ${vehicle!.plateNumber}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.darkPrimarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              CupertinoIcons.location_solid,
              color: AppColors.darkPrimary,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vehicleTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.darkTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  record.locationText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
        ],
      ),
    );
  }
}

Map<String, MemberFilterColor> _homeMemberColors(List<FamilyMember> members) {
  return {
    for (var index = 0; index < members.length; index++)
      members[index].id:
          MemberFilterColor.fromValue(members[index].color) ??
          MemberFilterColor.values[index % MemberFilterColor.values.length],
  };
}

String _koreanTimeText(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute;

  if (minute == 0) {
    return '$hour시';
  }

  return '$hour시$minute분';
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
    return RefreshableScrollView(
      onRefresh: onReloadFamilies,
      children: [
        const SizedBox(height: 24),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Icon(
            CupertinoIcons.check_mark_circled_solid,
            color: AppColors.darkPrimary,
            size: 34,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          '$userNickname님,\n체키를 시작해 볼까요?',
          style: TextStyle(
            color: AppColors.darkTextPrimary,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.16,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '체키는 우리의 하루를 함께 체크하는 작은 비서예요. 우리의 일정과 주차 위치를 예쁘게 챙겨요.',
          style: TextStyle(
            color: AppColors.darkTextSecondary,
            fontSize: 16,
            height: 1.45,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _IntroFeaturePill(
                icon: CupertinoIcons.calendar,
                title: '아이 일정 관리',
                description: '학교와 학원 시간을 가족이 함께 확인',
                color: AppColors.darkPrimary,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _IntroFeaturePill(
                icon: CupertinoIcons.car_detailed,
                title: '주차 관리',
                description: '차량별 주차 위치를 빠르게 공유',
                color: AppColors.brandCoral,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '일정, 차량, 주차 기록은 모두 가족 단위로 저장됩니다. 가족을 만들거나 초대 링크를 수락하면 홈에서 바로 사용할 수 있어요.',
          style: TextStyle(
            color: AppColors.darkTextMuted,
            fontSize: 14,
            height: 1.42,
            fontWeight: FontWeight.w600,
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
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(14),
            onPressed: onOpenFamilyManagement,
            child: const Center(
              child: Text(
                '가족 등록하기',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 50,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            color: AppColors.darkSurfaceElevated,
            borderRadius: BorderRadius.circular(14),
            onPressed: onReloadFamilies,
            child: Center(
              child: Text(
                '가족 목록 새로고침',
                style: TextStyle(
                  color: AppColors.darkPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _IntroFeaturePill extends StatelessWidget {
  const _IntroFeaturePill({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                height: 1.15,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.darkTextSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.3,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
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

String _extractInviteToken(String input) {
  final trimmed = input.trim();
  final uri = Uri.tryParse(trimmed);

  if (uri != null && uri.pathSegments.isNotEmpty) {
    return uri.pathSegments.last;
  }

  if (trimmed.contains('/')) {
    return trimmed.split('/').where((segment) => segment.isNotEmpty).last;
  }

  return trimmed;
}
