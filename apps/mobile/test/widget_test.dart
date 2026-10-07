import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:favis_mobile/core/api_client.dart';
import 'package:favis_mobile/core/auth_session_store.dart';
import 'package:favis_mobile/features/auth/auth_gate.dart';
import 'package:favis_mobile/main.dart';

void main() {
  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          if (call.method == 'read') {
            return null;
          }

          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  testWidgets('auth gate shows kakao login entry', (tester) async {
    await tester.pumpWidget(const CheckyApp());
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();

    expect(find.text('체키'), findsOneWidget);
    expect(find.text('카카오로 계속하기'), findsOneWidget);
  });

  testWidgets('network failure keeps the stored session and offers retry', (
    tester,
  ) async {
    final sessionStore = _FakeAuthSessionStore(
      StoredAuthSession(
        accessToken: 'stored-token',
        tokenType: 'Bearer',
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    );
    final apiClient = _FailingApiClient(
      const ApiConnectionException('network unavailable'),
    );

    await tester.pumpWidget(
      CupertinoApp(
        home: AuthGate(
          apiClient: apiClient,
          sessionStore: sessionStore,
          startupSplashDuration: Duration.zero,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('서버에 연결할 수 없어요'), findsOneWidget);
    expect(find.textContaining('로그인 정보는 그대로'), findsNothing);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.text('카카오로 계속하기'), findsNothing);
    expect(apiClient.getMeCallCount, 1);
    expect(sessionStore.clearCallCount, 0);
  });

  testWidgets('server 500 keeps the stored session', (tester) async {
    final sessionStore = _FakeAuthSessionStore(_validStoredSession());

    await tester.pumpWidget(
      CupertinoApp(
        home: AuthGate(
          apiClient: _FailingApiClient(const ApiException(500, {})),
          sessionStore: sessionStore,
          startupSplashDuration: Duration.zero,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('서버에 연결할 수 없어요'), findsOneWidget);
    expect(find.text('카카오로 계속하기'), findsNothing);
    expect(sessionStore.clearCallCount, 0);
  });

  testWidgets('server 401 clears the stored session and shows login', (
    tester,
  ) async {
    final sessionStore = _FakeAuthSessionStore(_validStoredSession());

    await tester.pumpWidget(
      CupertinoApp(
        home: AuthGate(
          apiClient: _FailingApiClient(
            const ApiException(401, {'error': 'invalid_token'}),
          ),
          sessionStore: sessionStore,
          startupSplashDuration: Duration.zero,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('카카오로 계속하기'), findsOneWidget);
    expect(find.text('서버에 연결할 수 없어요'), findsNothing);
    expect(sessionStore.clearCallCount, 1);
  });
}

StoredAuthSession _validStoredSession() {
  return StoredAuthSession(
    accessToken: 'stored-token',
    tokenType: 'Bearer',
    expiresAt: DateTime.now().add(const Duration(days: 1)),
  );
}

class _FakeAuthSessionStore extends AuthSessionStore {
  _FakeAuthSessionStore(this.session);

  final StoredAuthSession? session;
  int clearCallCount = 0;

  @override
  Future<StoredAuthSession?> read() async => session;

  @override
  Future<void> clear() async {
    clearCallCount += 1;
  }
}

class _FailingApiClient extends ApiClient {
  _FailingApiClient(this.error) : super(baseUrl: 'https://example.com');

  final Object error;
  int getMeCallCount = 0;

  @override
  Future<AppUser> getMe(String sessionToken) async {
    getMeCallCount += 1;
    throw error;
  }
}
