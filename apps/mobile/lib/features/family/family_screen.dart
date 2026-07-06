import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../design_system/app_colors.dart';
import '../../shared/member_filter.dart';
import '../../shared/refreshable_scroll_view.dart';

const _shareChannel = MethodChannel('checky/share');

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({
    super.key,
    required this.sessionToken,
    required this.currentUserId,
  });

  final String sessionToken;
  final String currentUserId;

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  final _apiClient = ApiClient();

  List<FamilySummary> _families = const [];
  String? _message;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFamilies();
  }

  Future<void> _loadFamilies() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final families = await _apiClient.listFamilies(widget.sessionToken);

      if (mounted) {
        setState(() {
          _families = families;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _createFamily() async {
    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (_) => const _FamilyNameDialog(title: '가족 만들기'),
    );

    if (name == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      await _apiClient.createFamily(widget.sessionToken, name: name);
      await _loadFamilies();
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _acceptInvitation() async {
    final input = await showCupertinoDialog<String>(
      context: context,
      builder: (_) => const _InviteAcceptDialog(),
    );

    if (input == null) {
      return;
    }

    final inviteToken = _extractInviteToken(input);

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      await _apiClient.acceptFamilyInvitation(
        widget.sessionToken,
        inviteToken: inviteToken,
      );
      await _loadFamilies();
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text('가족 관리'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 32),
          onPressed: _isLoading ? null : _createFamily,
          child: const Icon(CupertinoIcons.plus),
        ),
      ),
      child: SafeArea(
        child: RefreshableScrollView(
          onRefresh: _loadFamilies,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Text(
              '가족을 만들고 구성원을 초대하세요.',
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                height: 1.18,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '대표는 가족 안의 추가, 수정, 삭제를 할 수 있고 구성원은 조회만 할 수 있습니다.',
              style: TextStyle(
                color: AppColors.darkTextSecondary,
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: CupertinoButton(
                color: AppColors.darkSurfaceElevated,
                borderRadius: BorderRadius.circular(12),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                onPressed: _isLoading ? null : _acceptInvitation,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.link, size: 20),
                    SizedBox(width: 8),
                    Text(
                      '초대 링크 수락',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              _InlineMessage(message: _message!),
            ],
            const SizedBox(height: 20),
            if (_isLoading)
              Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: CupertinoActivityIndicator()),
              )
            else if (_families.isEmpty)
              const _EmptyFamilies()
            else
              ..._families.map(
                (summary) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _FamilyTile(
                    summary: summary,
                    onPressed: () async {
                      await Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (_) => FamilyDetailScreen(
                            sessionToken: widget.sessionToken,
                            currentUserId: widget.currentUserId,
                            familyId: summary.family.id,
                          ),
                        ),
                      );
                      await _loadFamilies();
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class FamilyDetailScreen extends StatefulWidget {
  const FamilyDetailScreen({
    super.key,
    required this.sessionToken,
    required this.currentUserId,
    required this.familyId,
  });

  final String sessionToken;
  final String currentUserId;
  final String familyId;

  @override
  State<FamilyDetailScreen> createState() => _FamilyDetailScreenState();
}

class _FamilyDetailScreenState extends State<FamilyDetailScreen> {
  final _apiClient = ApiClient();

  FamilyDetail? _detail;
  String? _message;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFamily();
  }

  Future<void> _loadFamily() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final detail = await _apiClient.getFamily(
        widget.sessionToken,
        familyId: widget.familyId,
      );

      if (mounted) {
        setState(() {
          _detail = detail;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _renameFamily() async {
    final detail = _detail;

    if (detail == null) {
      return;
    }

    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (_) =>
          _FamilyNameDialog(title: '가족 이름 수정', initialName: detail.family.name),
    );

    if (name == null) {
      return;
    }

    await _runDetailTask(() async {
      final family = await _apiClient.updateFamily(
        widget.sessionToken,
        familyId: detail.family.id,
        name: name,
      );
      setState(() {
        _detail = detail.copyWith(family: family);
      });
    });
  }

  Future<void> _deleteFamily() async {
    final detail = _detail;

    if (detail == null) {
      return;
    }

    final confirmed = await _confirm(
      title: '가족 삭제',
      message: '${detail.family.name} 가족을 삭제할까요? 구성원 연결과 초대가 함께 삭제됩니다.',
      actionText: '삭제',
      destructive: true,
    );

    if (!confirmed) {
      return;
    }

    await _runDetailTask(() async {
      await _apiClient.deleteFamily(
        widget.sessionToken,
        familyId: detail.family.id,
      );

      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> _createMember() async {
    final detail = _detail;

    if (detail == null) {
      return;
    }

    final input = await showCupertinoDialog<_MemberInput>(
      context: context,
      builder: (_) => const _MemberDialog(),
    );

    if (input == null) {
      return;
    }

    await _runDetailTask(() async {
      await _apiClient.createFamilyMember(
        widget.sessionToken,
        familyId: detail.family.id,
        nickname: input.nickname,
        role: input.role,
      );
      await _loadFamily();
    });
  }

  Future<void> _renameMember(FamilyMember member) async {
    final detail = _detail;

    if (detail == null) {
      return;
    }

    final nickname = await showCupertinoDialog<String>(
      context: context,
      builder: (_) => _MemberNameDialog(initialName: member.nickname),
    );

    if (nickname == null || nickname == member.nickname) {
      return;
    }

    await _runDetailTask(() async {
      await _apiClient.updateFamilyMemberName(
        widget.sessionToken,
        familyId: detail.family.id,
        memberId: member.id,
        nickname: nickname,
      );
      await _loadFamily();
    });
  }

  Future<void> _createInvitation(FamilyMember member) async {
    final detail = _detail;

    if (detail == null) {
      return;
    }

    await _runDetailTask(() async {
      final invitation = await _apiClient.createFamilyInvitation(
        widget.sessionToken,
        familyId: detail.family.id,
        memberId: member.id,
      );

      if (mounted) {
        await showCupertinoDialog<void>(
          context: context,
          builder: (_) => _InviteResultDialog(invitation: invitation),
        );
      }
    });
  }

  Future<void> _removeMember(FamilyMember member) async {
    final detail = _detail;

    if (detail == null) {
      return;
    }

    final confirmed = await _confirm(
      title: '구성원 삭제',
      message: '${member.nickname}님을 ${detail.family.name} 가족에서 삭제할까요?',
      actionText: '삭제',
      destructive: true,
    );

    if (!confirmed) {
      return;
    }

    await _runDetailTask(() async {
      await _apiClient.deleteFamilyMember(
        widget.sessionToken,
        familyId: detail.family.id,
        memberId: member.id,
      );
      await _loadFamily();
    });
  }

  Future<void> _changeMemberColor(FamilyMember member) async {
    final detail = _detail;

    if (detail == null || !detail.canManage) {
      return;
    }

    final selectedColor = await showCupertinoDialog<MemberFilterColor>(
      context: context,
      builder: (_) => _MemberColorDialog(member: member),
    );

    if (selectedColor == null) {
      return;
    }

    await _runDetailTask(() async {
      await _apiClient.updateFamilyMemberColor(
        widget.sessionToken,
        familyId: detail.family.id,
        memberId: member.id,
        color: selectedColor.name,
      );
      await _loadFamily();
    });
  }

  bool _canEditMemberName(FamilyDetail detail, FamilyMember member) {
    final isSelf = member.userId == widget.currentUserId;

    if (isSelf) {
      return true;
    }

    return detail.canManage;
  }

  bool _canEditMemberColor(FamilyDetail detail, FamilyMember member) {
    return detail.canManage;
  }

  bool _canDeleteMember(FamilyDetail detail, FamilyMember member) {
    final isSelf = member.userId == widget.currentUserId;

    return detail.canManage && !isSelf;
  }

  Future<void> _runDetailTask(Future<void> Function() task) async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      await task();
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String actionText,
    bool destructive = false,
  }) async {
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('취소'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: destructive,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(actionText),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;

    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(detail?.family.name ?? '가족'),
        trailing: detail?.canManage == true
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(32, 32),
                onPressed: _isLoading ? null : _createMember,
                child: const Icon(CupertinoIcons.person_badge_plus),
              )
            : null,
      ),
      child: SafeArea(
        child: RefreshableScrollView(
          onRefresh: _loadFamily,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            if (_isLoading && detail == null)
              Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CupertinoActivityIndicator()),
              )
            else if (detail != null) ...[
              _FamilyDetailHeader(detail: detail),
              if (_message != null) ...[
                const SizedBox(height: 16),
                _InlineMessage(message: _message!),
              ],
              if (detail.canManage) ...[
                const SizedBox(height: 20),
                _ActionRow(
                  children: [
                    _ActionButton(
                      icon: CupertinoIcons.pencil,
                      title: '이름 수정',
                      onPressed: _isLoading ? null : _renameFamily,
                    ),
                    _ActionButton(
                      icon: CupertinoIcons.trash,
                      title: '가족 삭제',
                      destructive: true,
                      onPressed: _isLoading ? null : _deleteFamily,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              const _SectionTitle(title: '구성원'),
              const SizedBox(height: 10),
              ...detail.members.asMap().entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _MemberTile(
                    member: entry.value,
                    index: entry.key,
                    canEditName: _canEditMemberName(detail, entry.value),
                    canEditColor: _canEditMemberColor(detail, entry.value),
                    canDelete: _canDeleteMember(detail, entry.value),
                    canInvite: detail.canManage && !entry.value.isLinked,
                    onEditName: () => _renameMember(entry.value),
                    onChangeColor: () => _changeMemberColor(entry.value),
                    onInvite: () => _createInvitation(entry.value),
                    onDelete: () => _removeMember(entry.value),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FamilyTile extends StatelessWidget {
  const _FamilyTile({required this.summary, required this.onPressed});

  final FamilySummary summary;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(14),
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.darkPrimarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                CupertinoIcons.person_2_fill,
                color: CupertinoColors.systemTeal,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary.family.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.darkTextPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    roleLabel(summary.role),
                    style: TextStyle(
                      color: AppColors.darkTextSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_forward,
              color: CupertinoColors.systemGrey2,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _FamilyDetailHeader extends StatelessWidget {
  const _FamilyDetailHeader({required this.detail});

  final FamilyDetail detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            detail.family.name,
            style: TextStyle(
              color: AppColors.darkTextPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.12,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${roleLabel(detail.myRole)} 권한 · 구성원 ${detail.members.length}명',
            style: TextStyle(
              color: AppColors.darkTextSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.index,
    required this.canEditName,
    required this.canEditColor,
    required this.canDelete,
    required this.canInvite,
    required this.onEditName,
    required this.onChangeColor,
    required this.onInvite,
    required this.onDelete,
  });

  final FamilyMember member;
  final int index;
  final bool canEditName;
  final bool canEditColor;
  final bool canDelete;
  final bool canInvite;
  final VoidCallback onEditName;
  final VoidCallback onChangeColor;
  final VoidCallback onInvite;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final memberColor =
        MemberFilterColor.fromValue(member.color) ??
        MemberFilterColor.selectable[index %
            MemberFilterColor.selectable.length];
    final colorStyle = MemberFilterColorStyle.from(memberColor);
    final actions = [
      if (canEditName)
        _MemberActionButton(
          onPressed: onEditName,
          child: const Icon(CupertinoIcons.pencil_circle, size: 24),
        ),
      if (canEditColor)
        _MemberActionButton(
          onPressed: onChangeColor,
          child: _ColorSwatchAction(style: colorStyle),
        ),
      if (canDelete)
        _MemberActionButton(
          onPressed: onDelete,
          child: const Icon(
            CupertinoIcons.minus_circle,
            color: CupertinoColors.destructiveRed,
            size: 24,
          ),
        ),
      if (canInvite)
        _MemberActionButton(
          onPressed: onInvite,
          child: const _InviteActionIcon(),
        ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colorStyle.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorStyle.border),
            ),
            child: Icon(
              CupertinoIcons.person_fill,
              color: colorStyle.foreground,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.darkTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${roleLabel(member.role)} · ${member.isLinked ? '계정 연결됨' : '계정 미연결'}',
                  style: TextStyle(
                    color: AppColors.darkTextSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          if (actions.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: actions,
            ),
        ],
      ),
    );
  }
}

class _MemberActionButton extends StatelessWidget {
  const _MemberActionButton({required this.onPressed, required this.child});

  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 40,
      child: Center(
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(40, 40),
          onPressed: onPressed,
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _ColorSwatchAction extends StatelessWidget {
  const _ColorSwatchAction({required this.style});

  final MemberFilterColorStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.darkSurfaceElevated,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Center(
            child: Container(
              width: 21,
              height: 21,
              decoration: BoxDecoration(
                color: style.background,
                shape: BoxShape.circle,
                border: Border.all(color: style.border, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: style.border.withValues(alpha: 0.28),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 1,
            bottom: 1,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: AppColors.darkBackground,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.darkSurfaceElevated),
              ),
              child: Icon(
                CupertinoIcons.chevron_down,
                color: style.foreground,
                size: 9,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteActionIcon extends StatelessWidget {
  const _InviteActionIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.darkPrimarySoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Icon(
        CupertinoIcons.person_badge_plus,
        color: AppColors.darkPrimary,
        size: 18,
      ),
    );
  }
}

class _MemberColorDialog extends StatelessWidget {
  const _MemberColorDialog({required this.member});

  final FamilyMember member;

  @override
  Widget build(BuildContext context) {
    final selectedColor = MemberFilterColor.fromValue(member.color);

    return CupertinoAlertDialog(
      title: const Text('구성원 색상'),
      content: Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final color in MemberFilterColor.selectable)
              _MemberColorOption(
                color: color,
                isSelected: color == selectedColor,
                onPressed: () => Navigator.of(context).pop(color),
              ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
      ],
    );
  }
}

class _MemberColorOption extends StatelessWidget {
  const _MemberColorOption({
    required this.color,
    required this.isSelected,
    required this.onPressed,
  });

  final MemberFilterColor color;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final style = MemberFilterColorStyle.from(color);

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(42, 42),
      onPressed: onPressed,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: style.background,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? AppColors.darkTextPrimary : style.border,
            width: isSelected ? 3 : 1,
          ),
        ),
        child: isSelected
            ? Icon(CupertinoIcons.check_mark, color: style.foreground, size: 18)
            : null,
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final child in children) ...[
          Expanded(child: child),
          if (child != children.last) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.title,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? CupertinoColors.destructiveRed
        : CupertinoColors.systemTeal;

    return SizedBox(
      height: 48,
      child: CupertinoButton(
        color: AppColors.darkSurfaceElevated,
        disabledColor: AppColors.darkSurfaceElevated,
        borderRadius: BorderRadius.circular(12),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 19),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FamilyNameDialog extends StatefulWidget {
  const _FamilyNameDialog({required this.title, this.initialName});

  final String title;
  final String? initialName;

  @override
  State<_FamilyNameDialog> createState() => _FamilyNameDialogState();
}

class _FamilyNameDialogState extends State<_FamilyNameDialog> {
  late final TextEditingController _controller;
  String? _message;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();

    if (name.isEmpty) {
      setState(() {
        _message = '가족 이름을 입력해 주세요.';
      });
      return;
    }

    if (name.length > 50) {
      setState(() {
        _message = '가족 이름은 50자 이하로 입력해 주세요.';
      });
      return;
    }

    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Text(widget.title),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            CupertinoTextField(
              controller: _controller,
              autofocus: true,
              placeholder: '예: 우리집',
              maxLength: 50,
              onSubmitted: (_) => _submit(),
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(
                _message!,
                style: TextStyle(
                  color: CupertinoColors.destructiveRed,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('취소'),
        ),
        CupertinoDialogAction(onPressed: _submit, child: Text('저장')),
      ],
    );
  }
}

class _InviteAcceptDialog extends StatefulWidget {
  const _InviteAcceptDialog();

  @override
  State<_InviteAcceptDialog> createState() => _InviteAcceptDialogState();
}

class _InviteAcceptDialogState extends State<_InviteAcceptDialog> {
  final _controller = TextEditingController();
  String? _message;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();

    if (value.isEmpty) {
      setState(() {
        _message = '초대 링크나 코드를 입력해 주세요.';
      });
      return;
    }

    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Text('초대 수락'),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            CupertinoTextField(
              controller: _controller,
              autofocus: true,
              placeholder: '초대 링크 또는 코드',
              onSubmitted: (_) => _submit(),
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(
                _message!,
                style: TextStyle(
                  color: CupertinoColors.destructiveRed,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('취소'),
        ),
        CupertinoDialogAction(onPressed: _submit, child: Text('수락')),
      ],
    );
  }
}

class _MemberDialog extends StatefulWidget {
  const _MemberDialog();

  @override
  State<_MemberDialog> createState() => _MemberDialogState();
}

class _MemberNameDialog extends StatefulWidget {
  const _MemberNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_MemberNameDialog> createState() => _MemberNameDialogState();
}

class _MemberNameDialogState extends State<_MemberNameDialog> {
  late final TextEditingController _nicknameController;
  String? _message;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  void _submit() {
    final nickname = _nicknameController.text.trim();

    if (nickname.isEmpty) {
      setState(() {
        _message = '구성원 이름을 입력해 주세요.';
      });
      return;
    }

    if (nickname.length > 40) {
      setState(() {
        _message = '구성원 이름은 40자 이하로 입력해 주세요.';
      });
      return;
    }

    Navigator.of(context).pop(nickname);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Text('구성원 이름 수정'),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            CupertinoTextField(
              controller: _nicknameController,
              autofocus: true,
              placeholder: '이름',
              maxLength: 40,
              onSubmitted: (_) => _submit(),
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(
                _message!,
                style: TextStyle(
                  color: CupertinoColors.destructiveRed,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('취소'),
        ),
        CupertinoDialogAction(onPressed: _submit, child: Text('저장')),
      ],
    );
  }
}

class _MemberDialogState extends State<_MemberDialog> {
  final _nicknameController = TextEditingController();
  String _role = 'member';
  String? _message;

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  void _submit() {
    final nickname = _nicknameController.text.trim();

    if (nickname.isEmpty) {
      setState(() {
        _message = '구성원 이름을 입력해 주세요.';
      });
      return;
    }

    if (nickname.length > 40) {
      setState(() {
        _message = '구성원 이름은 40자 이하로 입력해 주세요.';
      });
      return;
    }

    Navigator.of(context).pop(_MemberInput(nickname: nickname, role: _role));
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Text('구성원 추가'),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            CupertinoTextField(
              controller: _nicknameController,
              autofocus: true,
              placeholder: '이름',
              maxLength: 40,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 10),
            CupertinoSlidingSegmentedControl<String>(
              groupValue: _role,
              children: const {
                'owner': Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text('대표'),
                ),
                'member': Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text('구성원'),
                ),
              },
              onValueChanged: (value) {
                if (value != null) {
                  setState(() {
                    _role = value;
                  });
                }
              },
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(
                _message!,
                style: TextStyle(
                  color: CupertinoColors.destructiveRed,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('취소'),
        ),
        CupertinoDialogAction(onPressed: _submit, child: Text('추가')),
      ],
    );
  }
}

class _MemberInput {
  const _MemberInput({required this.nickname, required this.role});

  final String nickname;
  final String role;
}

class _InviteResultDialog extends StatefulWidget {
  const _InviteResultDialog({required this.invitation});

  final FamilyInvitation invitation;

  @override
  State<_InviteResultDialog> createState() => _InviteResultDialogState();
}

class _InviteResultDialogState extends State<_InviteResultDialog> {
  bool _isSharing = false;
  String? _message;

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: widget.invitation.inviteUrl));
  }

  Future<void> _shareLink() async {
    await _shareChannel.invokeMethod<void>('shareText', {
      'text': widget.invitation.inviteUrl,
      'subject': '체키 가족 초대',
    });
  }

  Future<void> _handleShare() async {
    if (_isSharing) {
      return;
    }

    setState(() {
      _isSharing = true;
      _message = null;
    });

    try {
      await _shareLink();
      if (!mounted) {
        return;
      }
      setState(() {
        _isSharing = false;
      });
    } catch (_) {
      await _copyLink();
      if (!mounted) {
        return;
      }
      setState(() {
        _isSharing = false;
        _message = '공유를 열지 못해 링크를 복사했어요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Text('초대 링크 생성 완료'),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            Text(
              '${widget.invitation.memberNickname}님을 ${roleLabel(widget.invitation.role)} 권한으로 연결합니다.',
            ),
            const SizedBox(height: 10),
            Text(widget.invitation.inviteUrl, style: TextStyle(fontSize: 13)),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(
                _message!,
                style: TextStyle(
                  color: AppColors.darkTextSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: _isSharing ? null : _handleShare,
          child: Text(_isSharing ? '공유 중...' : '공유'),
        ),
        CupertinoDialogAction(
          onPressed: () async {
            await _copyLink();

            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: Text('링크 복사'),
        ),
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('닫기'),
        ),
      ],
    );
  }
}

class _EmptyFamilies extends StatelessWidget {
  const _EmptyFamilies();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        children: [
          Icon(
            CupertinoIcons.person_2,
            color: CupertinoColors.systemGrey,
            size: 34,
          ),
          SizedBox(height: 10),
          Text(
            '아직 등록된 가족이 없습니다.',
            style: TextStyle(
              color: AppColors.darkTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          SizedBox(height: 6),
          Text(
            '오른쪽 위 + 버튼으로 가족을 먼저 만들어 주세요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.darkTextSecondary,
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: AppColors.darkTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          message,
          style: TextStyle(
            color: AppColors.darkDanger,
            fontSize: 14,
            height: 1.35,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

String roleLabel(String role) {
  return switch (role) {
    'owner' => '대표',
    _ => '구성원',
  };
}

String _extractInviteToken(String input) {
  final trimmed = input.trim();
  final uri = Uri.tryParse(trimmed);

  if (uri != null && uri.pathSegments.isNotEmpty) {
    return uri.pathSegments.last;
  }

  if (trimmed.contains('/')) {
    return trimmed.split('/').where((segment) => segment.isNotEmpty).last;
  }

  return trimmed;
}
