import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import '../../core/api_client.dart';
import '../../design_system/app_colors.dart';
import '../../core/api_config.dart';
import '../../core/auth_session_store.dart';
import '../home/home_screen.dart';

const _startupSplashDuration = Duration(milliseconds: 1500);
const _preferencesChannel = MethodChannel('checky/preferences');
const _selectedFamilyPreferenceKey = 'selectedFamilyId';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _apiClient = ApiClient();
  final _sessionStore = AuthSessionStore();

  AuthResponse? _auth;
  _InitialHomeData? _initialHomeData;
  String? _pendingKakaoAccessToken;
  String? _message;
  bool _isLoading = false;
  bool _isRestoringSession = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final minimumSplash = Future<void>.delayed(_startupSplashDuration);

    try {
      final storedSession = await _sessionStore.read();

      if (storedSession == null) {
        return;
      }

      if (storedSession.isExpired) {
        await _sessionStore.clear();
        return;
      }

      final user = await _apiClient.getMe(storedSession.accessToken);
      final initialHomeData = await _loadInitialHomeData(
        storedSession.accessToken,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _auth = AuthResponse(
          tokenType: storedSession.tokenType,
          accessToken: storedSession.accessToken,
          expiresIn: storedSession.remainingSeconds,
          isNewUser: false,
          user: user,
        );
        _initialHomeData = initialHomeData;
      });
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _sessionStore.clear();
      } else if (mounted) {
        setState(() {
          _message = '저장된 로그인 확인에 실패했습니다. 다시 시도해 주세요.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = '저장된 로그인 확인에 실패했습니다. 다시 시도해 주세요.';
        });
      }
    } finally {
      await minimumSplash;

      if (mounted) {
        setState(() {
          _isRestoringSession = false;
        });
      }
    }
  }

  Future<_InitialHomeData?> _loadInitialHomeData(String sessionToken) async {
    try {
      final preferredFamilyId = await _readSelectedFamilyId();
      final families = await _apiClient.listFamilies(sessionToken);
      final selectedFamilyId = _resolveSelectedFamilyId(
        families,
        preferredFamilyId,
      );

      ScheduleDashboard? scheduleDashboard;
      ParkingDashboard? parkingDashboard;

      if (selectedFamilyId != null) {
        await _saveSelectedFamilyId(selectedFamilyId);

        final now = DateTime.now();
        final dayStart = DateTime(now.year, now.month, now.day);
        final dayEnd = dayStart.add(const Duration(days: 1));
        final dashboards = await Future.wait<dynamic>([
          _apiClient.getScheduleDashboard(
            sessionToken,
            familyId: selectedFamilyId,
            rangeStart: dayStart,
            rangeEnd: dayEnd,
          ),
          _apiClient.getParkingDashboard(
            sessionToken,
            familyId: selectedFamilyId,
          ),
        ]);

        scheduleDashboard = dashboards[0] as ScheduleDashboard;
        parkingDashboard = dashboards[1] as ParkingDashboard;
      }

      return _InitialHomeData(
        families: families,
        selectedFamilyId: selectedFamilyId,
        scheduleDashboard: scheduleDashboard,
        parkingDashboard: parkingDashboard,
      );
    } catch (_) {
      return null;
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

  Future<void> _loginWithKakaoSdk() async {
    if (ApiConfig.kakaoNativeAppKey.isEmpty) {
      setState(() {
        _message = '카카오 네이티브 앱 키가 설정되지 않았습니다.';
      });
      return;
    }

    await _run(() async {
      final OAuthToken token;

      if (await isKakaoTalkInstalled()) {
        token = await UserApi.instance.loginWithKakaoTalk();
      } else {
        token = await UserApi.instance.loginWithKakaoAccount();
      }

      await _completeKakaoLogin(token.accessToken);
    });
  }

  Future<void> _completeKakaoLogin(
    String accessToken, {
    String? nickname,
  }) async {
    try {
      final auth = await _apiClient.loginWithKakaoAccessToken(
        accessToken,
        nickname: nickname,
      );

      await _sessionStore.save(auth);

      setState(() {
        _auth = auth;
        _pendingKakaoAccessToken = null;
      });
    } on ApiException catch (error) {
      if (error.isProfileRequired && nickname == null) {
        setState(() {
          _pendingKakaoAccessToken = accessToken;
        });
        return;
      }

      rethrow;
    }
  }

  Future<void> _createProfile(String nickname) async {
    final accessToken = _pendingKakaoAccessToken;

    if (accessToken == null) {
      setState(() {
        _message = '카카오 로그인부터 다시 진행해 주세요.';
      });
      return;
    }

    await _run(() => _completeKakaoLogin(accessToken, nickname: nickname));
  }

  Future<AppUser> _updateProfile(String nickname) async {
    final auth = _auth;

    if (auth == null) {
      throw const ApiConnectionException('로그인 정보가 없습니다.');
    }

    final user = await _apiClient.updateMyProfile(
      auth.accessToken,
      nickname: nickname,
    );
    final updatedAuth = auth.copyWith(user: user);

    await _sessionStore.save(updatedAuth);

    setState(() {
      _auth = updatedAuth;
    });

    return user;
  }

  Future<void> _deleteAccount() async {
    final auth = _auth;

    if (auth == null) {
      throw const ApiConnectionException('로그인 정보가 없습니다.');
    }

    await _apiClient.deleteMyAccount(auth.accessToken);
    await _sessionStore.clear();

    if (!mounted) {
      return;
    }

    setState(() {
      _auth = null;
      _initialHomeData = null;
      _pendingKakaoAccessToken = null;
      _message = null;
    });
  }

  Future<void> _run(Future<void> Function() task) async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      await task();
    } catch (error) {
      setState(() {
        _message = error.toString();
      });
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
    final auth = _auth;

    if (_isRestoringSession) {
      return const _StartupSplashScreen();
    }

    if (auth != null) {
      final initialHomeData = _initialHomeData;

      return HomeScreen(
        user: auth.user,
        sessionToken: auth.accessToken,
        initialFamilies: initialHomeData?.families,
        initialSelectedFamilyId: initialHomeData?.selectedFamilyId,
        initialScheduleDashboard: initialHomeData?.scheduleDashboard,
        initialParkingDashboard: initialHomeData?.parkingDashboard,
        onUpdateProfile: _updateProfile,
        onDeleteAccount: _deleteAccount,
        onLogout: () async {
          await _sessionStore.clear();

          if (!mounted) {
            return;
          }

          setState(() {
            _auth = null;
            _initialHomeData = null;
            _pendingKakaoAccessToken = null;
            _message = null;
          });
        },
      );
    }

    final pendingKakaoAccessToken = _pendingKakaoAccessToken;

    if (pendingKakaoAccessToken != null) {
      return _NicknameSetupScreen(
        isLoading: _isLoading,
        message: _message,
        onSubmit: _isLoading ? null : _createProfile,
        onCancel: _isLoading
            ? null
            : () {
                setState(() {
                  _pendingKakaoAccessToken = null;
                  _message = null;
                });
              },
      );
    }

    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const _AppMark(),
              const SizedBox(height: 24),
              const _LoginTitle(),
              if (_message != null) ...[
                const SizedBox(height: 18),
                _ErrorMessage(message: _message!),
              ],
              const Spacer(),
              _KakaoLoginButton(
                isLoading: _isLoading,
                onPressed: _isLoading ? null : _loginWithKakaoSdk,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InitialHomeData {
  const _InitialHomeData({
    required this.families,
    required this.selectedFamilyId,
    required this.scheduleDashboard,
    required this.parkingDashboard,
  });

  final List<FamilySummary> families;
  final String? selectedFamilyId;
  final ScheduleDashboard? scheduleDashboard;
  final ParkingDashboard? parkingDashboard;
}

class _StartupSplashScreen extends StatelessWidget {
  const _StartupSplashScreen();

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFEAFBF8),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 30,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  'assets/branding/checky-icon-source.png',
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                '체키',
                style: TextStyle(
                  color: Color(0xFF102A2A),
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '우리의 하루를 준비하는 중',
                style: TextStyle(
                  color: Color(0xFF55706F),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NicknameSetupScreen extends StatefulWidget {
  const _NicknameSetupScreen({
    required this.isLoading,
    required this.message,
    required this.onSubmit,
    required this.onCancel,
  });

  final bool isLoading;
  final String? message;
  final Future<void> Function(String nickname)? onSubmit;
  final VoidCallback? onCancel;

  @override
  State<_NicknameSetupScreen> createState() => _NicknameSetupScreenState();
}

class _NicknameSetupScreenState extends State<_NicknameSetupScreen> {
  final _controller = TextEditingController();
  String? _validationMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final nickname = _controller.text.trim();

    if (nickname.isEmpty) {
      setState(() {
        _validationMessage = '가족이 알아볼 수 있는 이름을 입력해 주세요.';
      });
      return;
    }

    if (nickname.length > 30) {
      setState(() {
        _validationMessage = '닉네임은 30자 이하로 입력해 주세요.';
      });
      return;
    }

    setState(() {
      _validationMessage = null;
    });

    await widget.onSubmit?.call(nickname);
  }

  @override
  Widget build(BuildContext context) {
    final message = _validationMessage ?? widget.message;

    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text('프로필 설정'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 32),
          onPressed: widget.onCancel,
          child: const Icon(CupertinoIcons.chevron_back),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '처음 사용할 이름을 정해 주세요.',
                style: TextStyle(
                  color: AppColors.darkTextPrimary,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1.12,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '카카오 계정 정보 대신 가족이 보기 편한 이름으로 저장됩니다.',
                style: TextStyle(
                  color: AppColors.darkTextSecondary,
                  fontSize: 16,
                  height: 1.42,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 28),
              CupertinoTextField(
                controller: _controller,
                autofocus: true,
                clearButtonMode: OverlayVisibilityMode.editing,
                placeholder: '예: 아빠, 엄마, 찬이',
                textInputAction: TextInputAction.done,
                maxLength: 30,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
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
                onSubmitted: (_) => _submit(),
              ),
              if (message != null) ...[
                const SizedBox(height: 14),
                _ErrorMessage(message: message),
              ],
              const Spacer(),
              SizedBox(
                height: 56,
                child: CupertinoButton.filled(
                  borderRadius: BorderRadius.circular(14),
                  onPressed: widget.isLoading ? null : _submit,
                  child: widget.isLoading
                      ? const CupertinoActivityIndicator(
                          color: CupertinoColors.white,
                        )
                      : Text(
                          '가입 완료하기',
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
      ),
    );
  }
}

class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ],
        ),
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        child: Image.asset(
          'assets/branding/checky-icon-source.png',
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Text(
              'C',
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LoginTitle extends StatelessWidget {
  const _LoginTitle();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '체키',
          style: TextStyle(
            color: AppColors.darkTextPrimary,
            fontSize: 38,
            fontWeight: FontWeight.w800,
            height: 1.05,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: 12),
        Text(
          '까먹지 마, 체키 있잖아',
          style: TextStyle(
            color: AppColors.darkTextPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: 12),
        Text(
          '가족 일정과 주차 자리, 오늘 챙길 일을 체키 하나로 가볍게 확인해요.',
          style: TextStyle(
            color: AppColors.darkTextSecondary,
            fontSize: 17,
            height: 1.45,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: 18),
        Text(
          'Checky, 우리 가족 체크 비서',
          style: TextStyle(
            color: AppColors.brandCoral,
            fontSize: 14,
            height: 1.25,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message});

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
          ),
        ),
      ),
    );
  }
}

class _KakaoLoginButton extends StatelessWidget {
  const _KakaoLoginButton({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: CupertinoButton(
        color: const Color(0xFFFEE500),
        disabledColor: const Color(0xFFFEE500),
        borderRadius: BorderRadius.circular(14),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: isLoading
            ? const CupertinoActivityIndicator(color: Color(0xFF191919))
            : Text(
                '카카오로 계속하기',
                style: TextStyle(
                  color: Color(0xFF191919),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
      ),
    );
  }
}
