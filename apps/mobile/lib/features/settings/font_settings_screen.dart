import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/theme_preference.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_font_preset.dart';
import '../../design_system/app_radius.dart';
import '../../design_system/app_spacing.dart';
import '../../design_system/app_typography.dart';

class FontSettingsScreen extends StatelessWidget {
  const FontSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final controller = ThemePreferenceScope.of(context);

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: const CupertinoNavigationBar(middle: Text('글꼴')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.page),
          children: [
            for (final font in AppFontPreset.values) ...[
              Semantics(
                button: true,
                selected: controller.font == font,
                child: CupertinoButton(
                  key: ValueKey('font-preset-${font.storageValue}'),
                  padding: EdgeInsets.zero,
                  onPressed: () => controller.setFont(font),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: controller.font == font
                            ? colors.primary
                            : colors.border,
                        width: controller.font == font ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                font.label,
                                style: font
                                    .applyTo(AppTypography.titleSmall)
                                    .copyWith(color: colors.textPrimary),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                '가족과 함께하는 하루\nChecky · Today 10:30',
                                style: font
                                    .applyTo(AppTypography.bodyLarge)
                                    .copyWith(color: colors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Icon(
                          controller.font == font
                              ? CupertinoIcons.check_mark_circled_solid
                              : CupertinoIcons.circle,
                          size: 24,
                          color: controller.font == font
                              ? colors.primary
                              : colors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            CupertinoButton(
              onPressed: () => Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) => const _FontLicensesScreen(),
                ),
              ),
              child: Text(
                '글꼴 라이선스',
                style: AppTypography.labelSmall.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FontLicensesScreen extends StatefulWidget {
  const _FontLicensesScreen();

  @override
  State<_FontLicensesScreen> createState() => _FontLicensesScreenState();
}

class _FontLicensesScreenState extends State<_FontLicensesScreen> {
  late final _licenses = Future.wait([
    for (final font in AppFontPreset.values)
      if (font.licenseAsset != null) rootBundle.loadString(font.licenseAsset!),
  ]);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fonts = AppFontPreset.values
        .where((font) => font.licenseAsset != null)
        .toList();
    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: const CupertinoNavigationBar(middle: Text('글꼴 라이선스')),
      child: SafeArea(
        child: FutureBuilder<List<String>>(
          future: _licenses,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  '라이선스를 불러오지 못했어요.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CupertinoActivityIndicator());
            }
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.page),
              children: [
                for (var index = 0; index < fonts.length; index++) ...[
                  Text(
                    fonts[index].label,
                    style: AppFontPreset.system
                        .applyTo(AppTypography.titleMedium)
                        .copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    snapshot.data![index],
                    style: AppFontPreset.system
                        .applyTo(AppTypography.bodySmall)
                        .copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
