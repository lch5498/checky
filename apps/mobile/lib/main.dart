import 'package:flutter/cupertino.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import 'core/api_config.dart';
import 'features/auth/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (ApiConfig.kakaoNativeAppKey.isNotEmpty) {
    KakaoSdk.init(nativeAppKey: ApiConfig.kakaoNativeAppKey);
  }

  runApp(const HouseKeepingApp());
}

class HouseKeepingApp extends StatelessWidget {
  const HouseKeepingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      title: 'House Keeping',
      debugShowCheckedModeBanner: false,
      theme: CupertinoThemeData(
        brightness: Brightness.light,
        primaryColor: CupertinoColors.systemTeal,
        scaffoldBackgroundColor: Color(0xFFF5F5F7),
        barBackgroundColor: Color(0xF2F5F5F7),
        textTheme: CupertinoTextThemeData(
          navLargeTitleTextStyle: TextStyle(
            inherit: false,
            color: Color(0xFF111111),
            fontSize: 34,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
          navTitleTextStyle: TextStyle(
            inherit: false,
            color: Color(0xFF111111),
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
      home: AuthGate(),
    );
  }
}
