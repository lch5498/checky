/// Per-user morning briefing push settings. Times are Asia/Seoul wall-clock.
class BriefingSettings {
  const BriefingSettings({
    required this.enabled,
    required this.hour,
    required this.minute,
    required this.weeklyPreviewEnabled,
  });

  static const defaults = BriefingSettings(
    enabled: false,
    hour: 8,
    minute: 0,
    weeklyPreviewEnabled: false,
  );

  final bool enabled;
  final int hour;
  final int minute;
  final bool weeklyPreviewEnabled;

  /// `HH:MM` as the API expects it.
  String get sendTime =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// `오전 8:00`, `오후 12:30`.
  String get sendTimeLabel => formatBriefingTime(hour, minute);

  BriefingSettings copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    bool? weeklyPreviewEnabled,
  }) => BriefingSettings(
    enabled: enabled ?? this.enabled,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    weeklyPreviewEnabled: weeklyPreviewEnabled ?? this.weeklyPreviewEnabled,
  );

  factory BriefingSettings.fromJson(Map<String, Object?> json) {
    final parts = (json['sendTime'] as String? ?? '08:00').split(':');
    return BriefingSettings(
      enabled: json['enabled'] as bool? ?? false,
      hour: int.tryParse(parts[0]) ?? 8,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      weeklyPreviewEnabled: json['weeklyPreviewEnabled'] as bool? ?? false,
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'sendTime': sendTime,
    'weeklyPreviewEnabled': weeklyPreviewEnabled,
  };

  @override
  bool operator ==(Object other) =>
      other is BriefingSettings &&
      other.enabled == enabled &&
      other.hour == hour &&
      other.minute == minute &&
      other.weeklyPreviewEnabled == weeklyPreviewEnabled;

  @override
  int get hashCode => Object.hash(enabled, hour, minute, weeklyPreviewEnabled);
}

String formatBriefingTime(int hour, int minute) {
  final period = hour < 12 ? '오전' : '오후';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  return '$period $displayHour:${minute.toString().padLeft(2, '0')}';
}
