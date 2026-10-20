import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../core/api_client.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_radius.dart';
import '../../design_system/app_spacing.dart';
import '../../design_system/app_typography.dart';
import '../../core/api_config.dart';
import '../../core/auth_session_store.dart';
import '../../core/push_notification_service.dart';
import '../home/home_screen.dart';

const _startupSplashDuration = Duration(milliseconds: 1500);
const _preferencesChannel = MethodChannel('checky/preferences');
const _selectedFamilyPreferenceKey = 'selectedFamilyId';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    this.apiClient,
    this.sessionStore,
    this.startupSplashDuration = _startupSplashDuration,
  });

  final ApiClient? apiClient;
  final AuthSessionStore? sessionStore;
  final Duration startupSplashDuration;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final ApiClient _apiClient;
  late final AuthSessionStore _sessionStore;
  final _pushNotificationService = PushNotificationService();

  AuthResponse? _auth;
  _InitialHomeData? _initialHomeData;
  String? _pendingKakaoAccessToken;
  String? _pendingAppleIdentityToken;
  String? _message;
  bool _isLoading = false;
  bool _isRestoringSession = true;
  bool _isRetryingSessionRestore = false;
  bool _didSessionRestoreFail = false;
  bool _isAppleSignInAvailable = false;

  @override
  void initState() {
    super.initState();
    _apiClient = widget.apiClient ?? ApiClient();
    _sessionStore = widget.sessionStore ?? AuthSessionStore();
    _restoreSession();
    _loadAppleSignInAvailability();
  }

  @override
  void dispose() {
    unawaited(_pushNotificationService.dispose());
    super.dispose();
  }

  Future<void> _loadAppleSignInAvailability() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    final isAvailable = await SignInWithApple.isAvailable();

    if (!mounted) {
      return;
    }

    setState(() {
      _isAppleSignInAvailable = isAvailable;
    });
  }

  Future<void> _restoreSession({bool isRetry = false}) async {
    final minimumSplash = isRetry
        ? Future<void>.value()
        : Future<void>.delayed(widget.startupSplashDuration);

    if (isRetry && mounted) {
      setState(() {
        _isRetryingSessionRestore = true;
      });
    }

    try {
      final storedSession = await _sessionStore.read();

      if (storedSession == null) {
        if (mounted) {
          setState(() {
            _didSessionRestoreFail = false;
          });
        }
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
        _didSessionRestoreFail = false;
      });
      unawaited(
        _pushNotificationService.attachSession(storedSession.accessToken),
      );
    } catch (error) {
      if (isSessionRejectedByServer(error)) {
        await _sessionStore.clear();

        if (mounted) {
          setState(() {
            _didSessionRestoreFail = false;
          });
        }
      } else if (mounted) {
        setState(() {
          _didSessionRestoreFail = true;
        });
      }
    } finally {
      await minimumSplash;

      if (mounted) {
        setState(() {
          _isRestoringSession = false;
          _isRetryingSessionRestore = false;
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
        _message = '카카오 로그인을 사용할 수 없습니다. 앱 설정을 확인해 주세요.';
      });
      return;
    }

    await _run(() async {
      final OAuthToken token;

      try {
        if (await isKakaoTalkInstalled()) {
          token = await UserApi.instance.loginWithKakaoTalk();
        } else {
          token = await UserApi.instance.loginWithKakaoAccount();
        }
      } on PlatformException catch (error) {
        if (error.code == 'CANCELED') {
          throw const ApiConnectionException('로그인이 취소되었습니다.');
        }

        rethrow;
      } on KakaoClientException catch (error) {
        if (error.reason == ClientErrorCause.cancelled) {
          throw const ApiConnectionException('로그인이 취소되었습니다.');
        }

        rethrow;
      }

      await _completeKakaoLogin(token.accessToken);
    });
  }

  Future<void> _loginWithApple() async {
    await _run(() async {
      try {
        final credential = await SignInWithApple.getAppleIDCredential(
          scopes: const [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
        );
        final identityToken = credential.identityToken;

        if (identityToken == null || identityToken.trim().isEmpty) {
          throw const ApiConnectionException('Apple 로그인 토큰을 받지 못했습니다.');
        }

        await _completeAppleLogin(
          identityToken,
          nickname: _appleDisplayName(
            givenName: credential.givenName,
            familyName: credential.familyName,
          ),
        );
      } on SignInWithAppleAuthorizationException catch (error) {
        if (error.code == AuthorizationErrorCode.canceled) {
          throw const ApiConnectionException('로그인이 취소되었습니다.');
        }

        if (error.code == AuthorizationErrorCode.failed ||
            error.code == AuthorizationErrorCode.notHandled ||
            error.code == AuthorizationErrorCode.notInteractive) {
          throw const ApiConnectionException(
            '기기의 Apple 계정 로그인 상태를 확인한 뒤 다시 시도해 주세요.',
          );
        }

        if (error.code == AuthorizationErrorCode.invalidResponse) {
          throw const ApiConnectionException(
            'Apple 로그인 응답을 확인할 수 없습니다. 다시 시도해 주세요.',
          );
        }

        throw const ApiConnectionException(
          'Apple 로그인을 완료할 수 없습니다. 잠시 후 다시 시도해 주세요.',
        );
      } on SignInWithAppleNotSupportedException {
        throw const ApiConnectionException('이 기기에서는 Apple 로그인을 사용할 수 없습니다.');
      } on SignInWithAppleCredentialsException {
        throw const ApiConnectionException(
          'Apple 로그인 정보를 확인할 수 없습니다. 다시 시도해 주세요.',
        );
      } on UnknownSignInWithAppleException {
        throw const ApiConnectionException(
          'Apple 로그인을 완료할 수 없습니다. 잠시 후 다시 시도해 주세요.',
        );
      }
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
        _pendingAppleIdentityToken = null;
      });
      unawaited(_pushNotificationService.attachSession(auth.accessToken));
    } on ApiException catch (error) {
      if (error.isProfileRequired && nickname == null) {
        setState(() {
          _pendingKakaoAccessToken = accessToken;
          _pendingAppleIdentityToken = null;
        });
        return;
      }

      rethrow;
    }
  }

  Future<void> _completeAppleLogin(
    String identityToken, {
    String? nickname,
  }) async {
    try {
      final auth = await _apiClient.loginWithAppleIdentityToken(
        identityToken,
        nickname: nickname,
      );

      await _sessionStore.save(auth);

      setState(() {
        _auth = auth;
        _pendingKakaoAccessToken = null;
        _pendingAppleIdentityToken = null;
      });
      unawaited(_pushNotificationService.attachSession(auth.accessToken));
    } on ApiException catch (error) {
      if (error.isProfileRequired && nickname == null) {
        await _completeAppleLogin(identityToken, nickname: '체키 사용자');
        return;
      }

      rethrow;
    }
  }

  Future<void> _createProfile(String nickname) async {
    final kakaoAccessToken = _pendingKakaoAccessToken;
    final appleIdentityToken = _pendingAppleIdentityToken;

    if (kakaoAccessToken == null && appleIdentityToken == null) {
      setState(() {
        _message = '로그인부터 다시 진행해 주세요.';
      });
      return;
    }

    if (kakaoAccessToken != null) {
      await _run(
        () => _completeKakaoLogin(kakaoAccessToken, nickname: nickname),
      );
      return;
    }

    await _run(
      () => _completeAppleLogin(appleIdentityToken!, nickname: nickname),
    );
  }

  Future<AppUser> _updateProfile(
    String nickname, {
    required bool updateFamilyMemberNicknames,
  }) async {
    final auth = _auth;

    if (auth == null) {
      throw const ApiConnectionException('로그인 정보가 없습니다.');
    }

    final user = await _apiClient.updateMyProfile(
      auth.accessToken,
      nickname: nickname,
      updateFamilyMemberNicknames: updateFamilyMemberNicknames,
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

    final navigator = Navigator.of(context, rootNavigator: true);
    await _pushNotificationService.detachSession();
    await _apiClient.deleteMyAccount(auth.accessToken);
    await _sessionStore.clear();

    if (!mounted) {
      return;
    }

    setState(() {
      _auth = null;
      _initialHomeData = null;
      _pendingKakaoAccessToken = null;
      _pendingAppleIdentityToken = null;
      _message = null;
    });
    navigator.popUntil((route) => route.isFirst);
  }

  Future<void> _logout() async {
    final navigator = Navigator.of(context, rootNavigator: true);
    await _pushNotificationService.detachSession();
    await _sessionStore.clear();

    if (!mounted) {
      return;
    }

    setState(() {
      _auth = null;
      _initialHomeData = null;
      _pendingKakaoAccessToken = null;
      _pendingAppleIdentityToken = null;
      _message = null;
    });
    navigator.popUntil((route) => route.isFirst);
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
    AppColors.of(context);
    final auth = _auth;

    if (_isRestoringSession) {
      return const _StartupSplashScreen();
    }

    if (_didSessionRestoreFail) {
      return _SessionRestoreUnavailableScreen(
        isRetrying: _isRetryingSessionRestore,
        onRetry: _isRetryingSessionRestore
            ? null
            : () => _restoreSession(isRetry: true),
      );
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
        onLogout: _logout,
      );
    }

    final hasPendingProfile =
        _pendingKakaoAccessToken != null || _pendingAppleIdentityToken != null;

    if (hasPendingProfile) {
      return _NicknameSetupScreen(
        isLoading: _isLoading,
        message: _message,
        onSubmit: _isLoading ? null : _createProfile,
        onCancel: _isLoading
            ? null
            : () {
                setState(() {
                  _pendingKakaoAccessToken = null;
                  _pendingAppleIdentityToken = null;
                  _message = null;
                });
              },
      );
    }

    return CupertinoPageScaffold(
      backgroundColor: AppColors.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            28,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const _AppMark(),
              const SizedBox(height: AppSpacing.xl),
              const _LoginTitle(),
              if (_message != null) ...[
                const SizedBox(height: 18),
                _ErrorMessage(message: _message!),
              ],
              const Spacer(),
              if (_isAppleSignInAvailable) ...[
                _AppleLoginButton(
                  isLoading: _isLoading,
                  onPressed: _isLoading ? null : _loginWithApple,
                ),
                const SizedBox(height: 10),
              ],
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

bool isSessionRejectedByServer(Object error) {
  return error is ApiException && error.statusCode == 401;
}

String? _appleDisplayName({String? givenName, String? familyName}) {
  final displayName = [familyName, givenName]
      .whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .join(' ');

  return displayName.isEmpty ? null : displayName;
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
    AppColors.of(context);
    return CupertinoPageScaffold(
      backgroundColor: AppColors.background,
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
              Text(
                '체키',
                style: AppTypography.display.copyWith(
                  color: AppColors.textPrimary,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '우리의 하루를 준비하는 중',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
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

class _SessionRestoreUnavailableScreen extends StatelessWidget {
  const _SessionRestoreUnavailableScreen({
    required this.isRetrying,
    required this.onRetry,
  });

  final bool isRetrying;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    AppColors.of(context);
    return CupertinoPageScaffold(
      backgroundColor: AppColors.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            28,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                CupertinoIcons.wifi_slash,
                color: AppColors.primary,
                size: 48,
              ),
              const SizedBox(height: 22),
              Text(
                '서버에 연결할 수 없어요',
                textAlign: TextAlign.center,
                style: AppTypography.titleLarge.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '네트워크 연결을 확인한 뒤 다시 시도해 주세요.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 54,
                child: CupertinoButton.filled(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onPressed: onRetry,
                  child: isRetrying
                      ? const CupertinoActivityIndicator(
                          color: CupertinoColors.white,
                        )
                      : const Text('다시 시도', style: AppTypography.button),
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
        _validationMessage = '구성원이 알아볼 수 있는 이름을 입력해 주세요.';
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
    AppColors.of(context);
    final message = _validationMessage ?? widget.message;

    return CupertinoPageScaffold(
      backgroundColor: AppColors.background,
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
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            28,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '처음 사용할 이름을 정해 주세요.',
                style: AppTypography.titleLarge.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '로그인 계정 정보 대신 함께 보기 편한 이름으로 저장됩니다.',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
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
                  horizontal: AppSpacing.lg,
                  vertical: 15,
                ),
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.border),
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
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onPressed: widget.isLoading ? null : _submit,
                  child: widget.isLoading
                      ? const CupertinoActivityIndicator(
                          color: CupertinoColors.white,
                        )
                      : Text('가입 완료하기', style: AppTypography.button),
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
    AppColors.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
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
              style: AppTypography.titleLarge.copyWith(
                color: AppColors.textPrimary,
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
    AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '체키',
          style: AppTypography.display.copyWith(color: AppColors.textPrimary),
        ),
        SizedBox(height: AppSpacing.md),
        Text(
          '까먹지 마, 체키 있잖아',
          style: AppTypography.titleLarge.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: AppSpacing.md),
        Text(
          '그룹 일정과 주차 자리, 오늘 챙길 일을 체키 하나로 가볍게 확인해요.',
          style: AppTypography.bodyLarge.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        SizedBox(height: 18),
        Text(
          'Checky, 우리 그룹 체크 비서',
          style: AppTypography.labelSmall.copyWith(color: AppColors.brandCoral),
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
    AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          message,
          style: AppTypography.labelSmall.copyWith(color: AppColors.danger),
        ),
      ),
    );
  }
}

class _AppleLoginButton extends StatelessWidget {
  const _AppleLoginButton({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    AppColors.of(context);
    return SignInWithAppleButton(
      text: 'Apple로 계속하기',
      height: 56,
      borderRadius: BorderRadius.circular(AppRadius.md),
      onPressed: isLoading ? null : onPressed,
    );
  }
}

class _KakaoLoginButton extends StatelessWidget {
  const _KakaoLoginButton({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    AppColors.of(context);
    return SizedBox(
      height: 56,
      child: CupertinoButton(
        color: const Color(0xFFFEE500),
        disabledColor: const Color(0xFFFEE500),
        borderRadius: BorderRadius.circular(AppRadius.md),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: isLoading
            ? const CupertinoActivityIndicator(color: Color(0xFF191919))
            : Text(
                '카카오로 계속하기',
                style: AppTypography.titleSmall.copyWith(
                  color: Color(0xFF191919),
                ),
              ),
      ),
    );
  }
}
