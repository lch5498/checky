import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import 'core/api_config.dart';
import 'design_system/app_theme.dart';
import 'design_system/app_theme_extension.dart';
import 'design_system/app_typography.dart';
import 'features/auth/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (ApiConfig.kakaoNativeAppKey.isNotEmpty) {
    KakaoSdk.init(nativeAppKey: ApiConfig.kakaoNativeAppKey);
  }

  runApp(const FavisApp());
}

class FavisApp extends StatelessWidget {
  const FavisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '파비스',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      builder: (context, child) {
        final brightness = Theme.of(context).brightness;
        final colors = AppThemeExtension.of(context);
        final textStyle = AppTypography.bodyMedium.copyWith(
          color: colors.textPrimary,
          decoration: TextDecoration.none,
        );

        return CupertinoTheme(
          data: AppTheme.cupertinoTheme(brightness),
          child: DefaultTextStyle.merge(
            style: textStyle,
            child: IconTheme(
              data: IconThemeData(color: colors.textPrimary),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
      home: const AuthGate(),
    );
  }
}
