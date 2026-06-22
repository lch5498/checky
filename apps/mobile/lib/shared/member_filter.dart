import 'package:flutter/cupertino.dart';

import '../design_system/app_colors.dart';

import '../core/api_client.dart';

enum MemberFilterColor {
  teal,
  blue,
  indigo,
  purple,
  pink,
  red,
  orange,
  yellow,
  green,
  gray,
}

class MemberFilterBar extends StatelessWidget {
  const MemberFilterBar({
    super.key,
    required this.members,
    required this.hiddenMemberIds,
    required this.onToggleMember,
    this.memberColors = const {},
  });

  final List<FamilyMember> members;
  final Set<String> hiddenMemberIds;
  final ValueChanged<String> onToggleMember;
  final Map<String, MemberFilterColor> memberColors;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (var index = 0; index < members.length; index++)
          _MemberFilterButton(
            label: members[index].userNickname,
            isActive: !hiddenMemberIds.contains(members[index].id),
            color: _colorForMember(members[index], index),
            onPressed: () => onToggleMember(members[index].id),
          ),
      ],
    );
  }

  MemberFilterColor _colorForMember(FamilyMember member, int index) {
    return memberColors[member.id] ??
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
    final style = MemberFilterColorStyle.from(color);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 118),
      child: SizedBox(
        height: 30,
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: isActive ? style.background : AppColors.darkBackground,
          borderRadius: BorderRadius.circular(9),
          onPressed: onPressed,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isActive
                    ? CupertinoIcons.check_mark_circled_solid
                    : CupertinoIcons.circle,
                color: isActive ? style.foreground : CupertinoColors.systemGrey,
                size: 15,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isActive
                        ? style.foreground
                        : AppColors.darkTextSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
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
  const MemberFilterColorStyle({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color border;

  factory MemberFilterColorStyle.from(MemberFilterColor color) {
    return switch (color) {
      MemberFilterColor.teal => const MemberFilterColorStyle(
        background: AppColors.darkPrimarySoft,
        foreground: Color(0xFF006D68),
        border: Color(0xFFD2E8E5),
      ),
      MemberFilterColor.blue => const MemberFilterColorStyle(
        background: Color(0xFFE8F1FF),
        foreground: Color(0xFF0A63CE),
        border: Color(0xFFD1E3FF),
      ),
      MemberFilterColor.indigo => const MemberFilterColorStyle(
        background: Color(0xFFEDEEFF),
        foreground: Color(0xFF4951B8),
        border: Color(0xFFDCDCFF),
      ),
      MemberFilterColor.purple => const MemberFilterColorStyle(
        background: Color(0xFFF3EAFE),
        foreground: Color(0xFF7A3EB1),
        border: Color(0xFFE3D0F8),
      ),
      MemberFilterColor.pink => const MemberFilterColorStyle(
        background: Color(0xFFFFEAF3),
        foreground: Color(0xFFC13B75),
        border: Color(0xFFF7D0E1),
      ),
      MemberFilterColor.red => const MemberFilterColorStyle(
        background: Color(0xFFFFEDEC),
        foreground: Color(0xFFC7352B),
        border: Color(0xFFF6D2D0),
      ),
      MemberFilterColor.orange => const MemberFilterColorStyle(
        background: Color(0xFFFFF0E3),
        foreground: Color(0xFFC75B12),
        border: Color(0xFFF4D7BA),
      ),
      MemberFilterColor.yellow => const MemberFilterColorStyle(
        background: Color(0xFFFFF7D6),
        foreground: Color(0xFF9A7200),
        border: Color(0xFFEFE2A9),
      ),
      MemberFilterColor.green => const MemberFilterColorStyle(
        background: Color(0xFFEAF7E8),
        foreground: Color(0xFF2F7D32),
        border: Color(0xFFD0E8CC),
      ),
      MemberFilterColor.gray => const MemberFilterColorStyle(
        background: Color(0xFFEFEFF4),
        foreground: Color(0xFF5E5E66),
        border: Color(0xFFDCDCE4),
      ),
    };
  }
}
