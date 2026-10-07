enum CouponFilter { available, used, expired, all }

enum CouponSort { expiry, newest }

class Coupon {
  const Coupon({
    required this.id,
    required this.title,
    required this.memo,
    required this.expiresOn,
    required this.usedAt,
    required this.createdAt,
    required this.version,
    required this.canManage,
    this.usedByName,
  });

  final String id;
  final String title;
  final String memo;
  final DateTime? expiresOn;
  final DateTime? usedAt;
  final DateTime createdAt;
  final int version;
  final bool canManage;
  final String? usedByName;

  String? get completionLabel => usedAt == null
      ? null
      : '사용 완료: ${usedByName?.trim().isNotEmpty == true ? usedByName!.trim() : '알 수 없는 구성원'}';

  factory Coupon.fromJson(Map<String, Object?> json) => Coupon(
    id: json['id'] as String,
    title: json['title'] as String,
    memo: json['memo'] as String? ?? '',
    expiresOn: DateTime.tryParse(json['expires_on'] as String? ?? ''),
    usedAt: DateTime.tryParse(json['used_at'] as String? ?? ''),
    createdAt: DateTime.parse(json['created_at'] as String),
    version: json['version'] as int,
    canManage: json['can_manage'] as bool? ?? false,
    usedByName: json['used_by_name'] as String?,
  );

  bool isExpired(DateTime now) =>
      expiresOn != null &&
      expiresOn!.isBefore(DateTime(now.year, now.month, now.day));
  String status(DateTime now) => usedAt != null
      ? '사용 완료'
      : isExpired(now)
      ? '만료'
      : '사용 가능';
}

String couponDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

List<Coupon> visibleCoupons(
  List<Coupon> coupons,
  CouponFilter filter,
  CouponSort sort,
  DateTime now,
) {
  final result = coupons
      .where(
        (coupon) => switch (filter) {
          CouponFilter.available =>
            coupon.usedAt == null && !coupon.isExpired(now),
          CouponFilter.used => coupon.usedAt != null,
          CouponFilter.expired =>
            coupon.usedAt == null && coupon.isExpired(now),
          CouponFilter.all => true,
        },
      )
      .toList();
  result.sort((a, b) {
    if (sort == CouponSort.expiry) {
      if (a.expiresOn == null && b.expiresOn != null) return 1;
      if (b.expiresOn == null && a.expiresOn != null) return -1;
      if (a.expiresOn != null && b.expiresOn != null) {
        final byDate = a.expiresOn!.compareTo(b.expiresOn!);
        if (byDate != 0) return byDate;
      }
    }
    final byCreated = b.createdAt.compareTo(a.createdAt);
    return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
  });
  return result;
}
