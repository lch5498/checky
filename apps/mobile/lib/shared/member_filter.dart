import 'package:flutter/cupertino.dart';

import '../design_system/app_colors.dart';
import '../design_system/app_radius.dart';
import '../design_system/app_spacing.dart';
import '../design_system/app_typography.dart';

import '../core/api_client.dart';

enum MemberFilterColor {
  red,
  blue,
  green,
  orange,
  purple,
  pink,
  teal,
  yellow,
  indigo,
  mint,
  gray;

  static MemberFilterColor? fromValue(String? value) {
    if (value == null) {
      return null;
    }

    for (final color in MemberFilterColor.values) {
      if (color.name == value) {
        return color;
      }
    }

    return null;
  }

  static const selectable = [
    MemberFilterColor.red,
    MemberFilterColor.blue,
    MemberFilterColor.green,
    MemberFilterColor.orange,
    MemberFilterColor.purple,
    MemberFilterColor.pink,
    MemberFilterColor.teal,
    MemberFilterColor.yellow,
    MemberFilterColor.indigo,
    MemberFilterColor.mint,
  ];
}

class MemberFilterBar extends StatelessWidget {
  const MemberFilterBar({
    super.key,
    required this.members,
    required this.hiddenMemberIds,
    required this.onToggleMember,
    this.memberColors = const {},
    this.trailingChildren = const [],
  });

  final List<FamilyMember> members;
  final Set<String> hiddenMemberIds;
  final ValueChanged<String> onToggleMember;
  final Map<String, MemberFilterColor> memberColors;
  final List<Widget> trailingChildren;

  @override
  Widget build(BuildContext context) {
    AppColors.of(context);
    if (members.isEmpty && trailingChildren.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (var index = 0; index < members.length; index++)
          _MemberFilterButton(
            label: members[index].nickname,
            isActive: !hiddenMemberIds.contains(members[index].id),
            color: _colorForMember(members[index], index),
            onPressed: () => onToggleMember(members[index].id),
          ),
        ...trailingChildren,
      ],
    );
  }

  MemberFilterColor _colorForMember(FamilyMember member, int index) {
    return MemberFilterColor.fromValue(member.color) ??
        memberColors[member.id] ??
        MemberFilterColor.values[index % MemberFilterColor.values.length];
  }
}

class _MemberFilterButton extends StatelessWidget {
  const _MemberFilterButton({
    required this.label,
    required this.isActive,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final bool isActive;
  final MemberFilterColor color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    AppColors.of(context);
    final style = MemberFilterColorStyle.from(color);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 92),
      child: SizedBox(
        height: 28,
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          color: isActive ? style.background : AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onPressed: onPressed,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isActive
                    ? CupertinoIcons.check_mark_circled_solid
                    : CupertinoIcons.circle,
                color: isActive ? style.foreground : CupertinoColors.systemGrey,
                size: 13,
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: isActive
                        ? style.foreground
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MemberFilterColorStyle {
  MemberFilterColorStyle({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color border;

  factory MemberFilterColorStyle.from(MemberFilterColor color) {
    return switch (color) {
      MemberFilterColor.red => MemberFilterColorStyle(
        background: Color(0xFFE53935),
        foreground: CupertinoColors.white,
        border: Color(0xFFC62828),
      ),
      MemberFilterColor.blue => MemberFilterColorStyle(
        background: Color(0xFF1E88E5),
        foreground: CupertinoColors.white,
        border: Color(0xFF1565C0),
      ),
      MemberFilterColor.green => MemberFilterColorStyle(
        background: Color(0xFF43A047),
        foreground: CupertinoColors.white,
        border: Color(0xFF2E7D32),
      ),
      MemberFilterColor.orange => MemberFilterColorStyle(
        background: Color(0xFFFB8C00),
        foreground: CupertinoColors.white,
        border: Color(0xFFEF6C00),
      ),
      MemberFilterColor.purple => MemberFilterColorStyle(
        background: Color(0xFF8E24AA),
        foreground: CupertinoColors.white,
        border: Color(0xFF6A1B9A),
      ),
      MemberFilterColor.pink => MemberFilterColorStyle(
        background: Color(0xFFD81B60),
        foreground: CupertinoColors.white,
        border: Color(0xFFAD1457),
      ),
      MemberFilterColor.teal => MemberFilterColorStyle(
        background: Color(0xFF00897B),
        foreground: CupertinoColors.white,
        border: Color(0xFF00695C),
      ),
      MemberFilterColor.yellow => MemberFilterColorStyle(
        background: Color(0xFFFDD835),
        foreground: Color(0xFF3D2F00),
        border: Color(0xFFF9A825),
      ),
      MemberFilterColor.indigo => MemberFilterColorStyle(
        background: Color(0xFF3949AB),
        foreground: CupertinoColors.white,
        border: Color(0xFF283593),
      ),
      MemberFilterColor.mint => MemberFilterColorStyle(
        background: Color(0xFF00ACC1),
        foreground: CupertinoColors.white,
        border: Color(0xFF00838F),
      ),
      MemberFilterColor.gray => MemberFilterColorStyle(
        background: Color(0xFF6B7280),
        foreground: CupertinoColors.white,
        border: Color(0xFF4B5563),
      ),
    };
  }
}
