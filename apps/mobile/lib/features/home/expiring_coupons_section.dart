import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../core/api_client.dart';
import '../../core/coupon.dart';
import '../../core/group_refresh.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_radius.dart';
import '../../design_system/app_spacing.dart';
import '../../design_system/app_typography.dart';
import '../scrap/coupon_screen.dart';

/// A secondary home briefing: failures never block schedules or parking.
class ExpiringCouponsSection extends StatefulWidget {
  const ExpiringCouponsSection({
    super.key,
    required this.family,
    required this.sessionToken,
    required this.refreshToken,
    this.apiClient,
    this.now = DateTime.now,
  });

  final AppFamily family;
  final String sessionToken;
  final int refreshToken;
  final ApiClient? apiClient;
  final DateTime Function() now;

  @override
  State<ExpiringCouponsSection> createState() => _ExpiringCouponsSectionState();
}

class _ExpiringCouponsSectionState extends State<ExpiringCouponsSection>
    with GroupRefreshListener<ExpiringCouponsSection>, WidgetsBindingObserver {
  late final _api = widget.apiClient ?? ApiClient();
  List<Coupon> _coupons = const [];
  Timer? _midnight;

  @override
  String get refreshFamilyId => widget.family.id;

  @override
  Future<void> refreshGroupContent() => _load();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _scheduleMidnight();
  }

  @override
  void didUpdateWidget(covariant ExpiringCouponsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedGroup =
        oldWidget.family.id != widget.family.id ||
        oldWidget.sessionToken != widget.sessionToken;
    if (changedGroup) _coupons = const [];
    if (changedGroup || oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // HomeScreen already refreshes the group's data when resuming.
      setState(() {});
      _scheduleMidnight();
    }
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = widget.now();
    _midnight = Timer(
      DateTime(now.year, now.month, now.day + 1).difference(now),
      () {
        if (!mounted) return;
        setState(() {});
        _scheduleMidnight();
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final version = beginGroupLoad();
    try {
      final coupons = await _api.getCoupons(
        widget.sessionToken,
        widget.family.id,
      );
      if (isCurrentGroupLoad(version)) {
        setState(() => _coupons = coupons);
      }
    } catch (_) {
      // Keep an existing same-group briefing during transient network failures.
    }
  }

  Future<void> _open(Coupon coupon) async {
    final family = widget.family;
    final sessionToken = widget.sessionToken;
    await Navigator.of(context, rootNavigator: true).push<void>(
      CupertinoPageRoute<void>(
        builder: (_) => CouponDetailScreen(
          family: family,
          sessionToken: sessionToken,
          coupon: coupon,
          apiClient: _api,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final now = widget.now();
    final coupons = expiringCoupons(_coupons, now);
    if (coupons.isEmpty) return const SizedBox.shrink();

    return Container(
      key: const ValueKey('home-expiring-coupons'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Semantics(
                label: '만료 임박',
                child: const ExcludeSemantics(
                  child: Text('🚨', style: AppTypography.titleSmall),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '만료 예정 쿠폰',
                  style: AppTypography.titleSmall.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final coupon in coupons)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              minimumSize: const Size(44, 44),
              onPressed: () => _open(coupon),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          coupon.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.label.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${couponDate(coupon.expiresOn!).replaceAll('-', '.')} 만료',
                          style: AppTypography.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: colors.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      coupon.expiryCountdown(now)!,
                      style: AppTypography.labelSmall.copyWith(
                        color: colors.danger,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    CupertinoIcons.chevron_forward,
                    size: 16,
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
