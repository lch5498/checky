import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:house_keeping_mobile/main.dart';

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
    await tester.pumpWidget(const FavisApp());
    await tester.pump();

    expect(find.text('파비스'), findsOneWidget);
    expect(find.text('카카오로 계속하기'), findsOneWidget);
  });
}
