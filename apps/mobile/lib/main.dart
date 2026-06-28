import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import 'core/api_config.dart';
import 'core/theme_preference.dart';
import 'design_system/app_colors.dart';
import 'design_system/app_theme.dart';
import 'design_system/app_theme_extension.dart';
import 'design_system/app_typography.dart';
import 'features/auth/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (ApiConfig.kakaoNativeAppKey.isNotEmpty) {
    KakaoSdk.init(nativeAppKey: ApiConfig.kakaoNativeAppKey);
  }

  runApp(const CheckyApp());
}

class CheckyApp extends StatefulWidget {
  const CheckyApp({super.key});

  @override
  State<CheckyApp> createState() => _CheckyAppState();
}

class _CheckyAppState extends State<CheckyApp> {
  late final ThemePreferenceController _themePreferenceController;

  @override
  void initState() {
    super.initState();
    _themePreferenceController = ThemePreferenceController();
    _themePreferenceController.load();
  }

  @override
  void dispose() {
    _themePreferenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThemePreferenceScope(
      controller: _themePreferenceController,
      child: AnimatedBuilder(
        animation: _themePreferenceController,
        builder: (context, _) {
          return MaterialApp(
            title: '체키',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: _themePreferenceController.themeMode,
            builder: (context, child) {
              final brightness = Theme.of(context).brightness;
              AppColors.useBrightness(brightness);

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
        },
      ),
    );
  }
}
