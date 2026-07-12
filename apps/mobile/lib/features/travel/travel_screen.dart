import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../design_system/app_colors.dart';
import '../../shared/refreshable_scroll_view.dart';

class TravelScreen extends StatefulWidget {
  const TravelScreen({
    super.key,
    required this.family,
    required this.families,
    required this.sessionToken,
    required this.onSelectFamily,
  });

  final AppFamily family;
  final List<AppFamily> families;
  final String sessionToken;
  final Future<void> Function(AppFamily family) onSelectFamily;

  @override
  State<TravelScreen> createState() => _TravelScreenState();
}

class _TravelScreenState extends State<TravelScreen> {
  final _apiClient = ApiClient();

  late AppFamily _family;
  TravelDashboard? _dashboard;
  String? _message;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _family = widget.family;
    _loadTravels();
  }

  @override
  void didUpdateWidget(covariant TravelScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.family.id != widget.family.id) {
      _family = widget.family;
      _dashboard = null;
      _loadTravels();
    }
  }

  Future<void> _loadTravels() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final dashboard = await _apiClient.getTravelDashboard(
        widget.sessionToken,
        familyId: _family.id,
      );

      if (mounted) {
        setState(() {
          _dashboard = dashboard;
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

  Future<void> _createTrip() async {
    final result = await Navigator.of(context).push<_TravelTripFormResult>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (context) => _TravelTripFormScreen(
          familyId: _family.id,
          sessionToken: widget.sessionToken,
        ),
      ),
    );
    final created = result?.trip;

    if (created == null || !mounted) {
      return;
    }

    await _loadTravels();

    if (!mounted) {
      return;
    }

    _openTrip(created);
  }

  Future<void> _switchFamily() async {
    if (widget.families.length < 2) {
      return;
    }

    final selected = await showCupertinoModalPopup<AppFamily>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('여행을 볼 그룹'),
        actions: widget.families
            .map(
              (family) => CupertinoActionSheetAction(
                onPressed: () => Navigator.of(context).pop(family),
                child: Text(family.name),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
      ),
    );

    if (selected == null || selected.id == _family.id) {
      return;
    }

    await widget.onSelectFamily(selected);

    if (mounted) {
      setState(() {
        _family = selected;
      });
      _loadTravels();
    }
  }

  Future<void> _openTrip(TravelTrip trip) async {
    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (context) => TravelDetailScreen(
          family: _family,
          sessionToken: widget.sessionToken,
          trip: trip,
        ),
      ),
    );

    if (mounted) {
      await _loadTravels();
    }
  }

  Future<void> _openTravelSettings() async {
    await Navigator.of(context).push(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (context) => _TravelSettingsScreen(
          family: _family,
          sessionToken: widget.sessionToken,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = _dashboard;

    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 32),
          onPressed: _isLoading ? null : _openTravelSettings,
          child: const Icon(CupertinoIcons.star),
        ),
        middle: _FeatureFamilyTitle(
          family: _family,
          featureName: '여행',
          canSwitch: widget.families.length > 1,
          onPressed: _switchFamily,
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 32),
          onPressed: _isLoading ? null : _createTrip,
          child: const Icon(CupertinoIcons.plus),
        ),
      ),
      child: SafeArea(
        child: RefreshableScrollView(
          onRefresh: _loadTravels,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            if (_message != null) ...[
              _InlineMessage(message: _message!),
              const SizedBox(height: 16),
            ],
            if (_isLoading && dashboard == null)
              const Padding(
                padding: EdgeInsets.only(top: 72),
                child: Center(child: CupertinoActivityIndicator()),
              )
            else if (dashboard == null)
              _EmptyState(
                icon: CupertinoIcons.exclamationmark_circle,
                title: '여행을 불러오지 못했습니다.',
                subtitle: '잠시 후 다시 시도해 주세요.',
                actionLabel: '다시 불러오기',
                onPressed: _loadTravels,
              )
            else if (dashboard.trips.isEmpty)
              _EmptyState(
                icon: CupertinoIcons.airplane,
                title: '아직 등록된 여행이 없습니다.',
                subtitle: '새 여행을 만들고 DAY별 일정표를 채워보세요.',
                actionLabel: '새 여행 만들기',
                onPressed: _createTrip,
              )
            else
              ...dashboard.trips.map(
                (trip) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _TravelTripRow(
                    trip: trip,
                    onTap: () => _openTrip(trip),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TravelSettingsScreen extends StatelessWidget {
  const _TravelSettingsScreen({
    required this.family,
    required this.sessionToken,
  });

  final AppFamily family;
  final String sessionToken;

  void _openTagManager(BuildContext context) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (context) =>
            _TravelTagManageScreen(family: family, sessionToken: sessionToken),
      ),
    );
  }

  void _openChecklistManager(BuildContext context) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (context) => _TravelChecklistManageScreen(
          family: family,
          sessionToken: sessionToken,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: CupertinoNavigationBar(
        automaticallyImplyLeading: false,
        middle: const Text('여행 메뉴'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            _TravelSettingsMenuRow(
              icon: CupertinoIcons.tag,
              title: '즐겨찾는 태그 관리',
              subtitle: '식당, 카페, 숙소처럼 여행 일정에 붙일 태그를 관리해요.',
              onTap: () => _openTagManager(context),
            ),
            const SizedBox(height: 12),
            _TravelSettingsMenuRow(
              icon: CupertinoIcons.checkmark_alt_circle,
              title: '여행 체크리스트 관리',
              subtitle: '여권, 충전기처럼 여행 전 챙길 준비물을 관리해요.',
              onTap: () => _openChecklistManager(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _TravelSettingsMenuRow extends StatelessWidget {
  const _TravelSettingsMenuRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.darkPrimarySoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.darkPrimary, size: 22),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.darkTextPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.darkTextMuted,
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              CupertinoIcons.chevron_forward,
              color: AppColors.darkTextMuted,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _TravelTagManageScreen extends StatefulWidget {
  const _TravelTagManageScreen({
    required this.family,
    required this.sessionToken,
  });

  final AppFamily family;
  final String sessionToken;

  @override
  State<_TravelTagManageScreen> createState() => _TravelTagManageScreenState();
}

class _TravelTagManageScreenState extends State<_TravelTagManageScreen> {
  final _apiClient = ApiClient();

  List<TravelTag> _tags = const [];
  String? _message;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final tags = await _apiClient.getTravelTags(
        widget.sessionToken,
        familyId: widget.family.id,
      );

      if (mounted) {
        setState(() {
          _tags = tags;
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

  Future<void> _addTag() async {
    final name = await _showTravelTextInput(
      context,
      title: '태그 추가',
      placeholder: '예: 맛집',
      maxLength: 24,
    );

    if (name == null || !mounted) {
      return;
    }

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      await _apiClient.createTravelTag(
        widget.sessionToken,
        familyId: widget.family.id,
        name: name,
      );
      await _loadTags();
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _editTag(TravelTag tag) async {
    final name = await _showTravelTextInput(
      context,
      title: '태그 수정',
      placeholder: '태그명',
      initialValue: tag.name,
      maxLength: 24,
    );

    if (name == null || name == tag.name || !mounted) {
      return;
    }

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      await _apiClient.updateTravelTag(
        widget.sessionToken,
        familyId: widget.family.id,
        tagId: tag.id,
        name: name,
      );
      await _loadTags();
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteTag(TravelTag tag) async {
    final confirmed = await _confirmTravelDelete(
      context,
      title: '태그를 삭제할까요?',
      content: '이 태그가 붙은 여행 일정에서도 태그가 제거됩니다.',
    );

    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      await _apiClient.deleteTravelTag(
        widget.sessionToken,
        familyId: widget.family.id,
        tagId: tag.id,
      );
      await _loadTags();
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _TravelManageScaffold(
      title: '즐겨찾는 태그',
      isSaving: _isSaving,
      onAdd: _addTag,
      onRefresh: _loadTags,
      message: _message,
      isLoading: _isLoading,
      emptyIcon: CupertinoIcons.tag,
      emptyTitle: '등록된 태그가 없습니다.',
      emptySubtitle: '+ 버튼으로 자주 쓰는 태그를 추가해 주세요.',
      children: [
        for (final tag in _tags)
          _TravelManageRow(
            title: tag.name,
            leading: CupertinoIcons.tag_fill,
            onEdit: () => _editTag(tag),
            onDelete: () => _deleteTag(tag),
          ),
      ],
    );
  }
}

class _TravelChecklistManageScreen extends StatefulWidget {
  const _TravelChecklistManageScreen({
    required this.family,
    required this.sessionToken,
  });

  final AppFamily family;
  final String sessionToken;

  @override
  State<_TravelChecklistManageScreen> createState() =>
      _TravelChecklistManageScreenState();
}

class _TravelChecklistManageScreenState
    extends State<_TravelChecklistManageScreen> {
  final _apiClient = ApiClient();

  List<TravelChecklistItem> _items = const [];
  String? _message;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final items = await _apiClient.getTravelChecklistItems(
        widget.sessionToken,
        familyId: widget.family.id,
      );

      if (mounted) {
        setState(() {
          _items = items;
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

  Future<void> _addItem({TravelChecklistItem? parent}) async {
    final name = await _showTravelTextInput(
      context,
      title: parent == null ? '체크리스트 추가' : '${parent.name} 하위 항목 추가',
      placeholder: parent == null ? '예: 여권' : '예: 여권 사본',
      maxLength: 40,
    );

    if (name == null || !mounted) {
      return;
    }

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      await _apiClient.createTravelChecklistItem(
        widget.sessionToken,
        familyId: widget.family.id,
        name: name,
        parentId: parent?.id,
      );
      await _loadItems();
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _editItem(TravelChecklistItem item) async {
    final name = await _showTravelTextInput(
      context,
      title: '체크리스트 수정',
      placeholder: '준비물',
      initialValue: item.name,
      maxLength: 40,
    );

    if (name == null || name == item.name || !mounted) {
      return;
    }

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      await _apiClient.updateTravelChecklistItem(
        widget.sessionToken,
        familyId: widget.family.id,
        itemId: item.id,
        name: name,
      );
      await _loadItems();
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteItem(TravelChecklistItem item) async {
    final confirmed = await _confirmTravelDelete(
      context,
      title: '준비물을 삭제할까요?',
      content: '삭제한 체크리스트 항목은 복구할 수 없습니다.',
    );

    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      await _apiClient.deleteTravelChecklistItem(
        widget.sessionToken,
        familyId: widget.family.id,
        itemId: item.id,
      );
      await _loadItems();
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final childrenByParentId = <String, List<TravelChecklistItem>>{};
    final parentItems = <TravelChecklistItem>[];

    for (final item in _items) {
      final parentId = item.parentId;
      if (parentId == null) {
        parentItems.add(item);
      } else {
        childrenByParentId.putIfAbsent(parentId, () => []).add(item);
      }
    }

    return _TravelManageScaffold(
      title: '여행 체크리스트',
      isSaving: _isSaving,
      onAdd: () => _addItem(),
      onRefresh: _loadItems,
      message: _message,
      isLoading: _isLoading,
      emptyIcon: CupertinoIcons.checkmark_alt_circle,
      emptyTitle: '등록된 준비물이 없습니다.',
      emptySubtitle: '+ 버튼으로 여행 전 챙길 항목을 추가해 주세요.',
      children: [
        for (final item in parentItems) ...[
          _TravelManageRow(
            title: item.name,
            leading: CupertinoIcons.checkmark_circle_fill,
            onEdit: () => _editItem(item),
            onDelete: () => _deleteItem(item),
            onAddChild: () => _addItem(parent: item),
          ),
          for (final child in childrenByParentId[item.id] ?? const [])
            _TravelManageRow(
              title: child.name,
              leading: CupertinoIcons.checkmark_circle,
              depth: 1,
              onEdit: () => _editItem(child),
              onDelete: () => _deleteItem(child),
            ),
        ],
      ],
    );
  }
}

class _TravelManageScaffold extends StatelessWidget {
  const _TravelManageScaffold({
    required this.title,
    required this.isSaving,
    required this.onAdd,
    required this.onRefresh,
    required this.message,
    required this.isLoading,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.children,
  });

  final String title;
  final bool isSaving;
  final VoidCallback onAdd;
  final Future<void> Function() onRefresh;
  final String? message;
  final bool isLoading;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptySubtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 32),
          onPressed: isSaving ? null : onAdd,
          child: isSaving
              ? const CupertinoActivityIndicator()
              : const Icon(CupertinoIcons.plus),
        ),
      ),
      child: SafeArea(
        child: RefreshableScrollView(
          onRefresh: onRefresh,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            if (message != null) ...[
              _InlineMessage(message: message!),
              const SizedBox(height: 14),
            ],
            if (isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 72),
                child: Center(child: CupertinoActivityIndicator()),
              )
            else if (children.isEmpty)
              _EmptyState(
                icon: emptyIcon,
                title: emptyTitle,
                subtitle: emptySubtitle,
                actionLabel: '추가하기',
                onPressed: onAdd,
              )
            else
              ...children,
          ],
        ),
      ),
    );
  }
}

class _TravelManageRow extends StatelessWidget {
  const _TravelManageRow({
    required this.title,
    required this.leading,
    required this.onEdit,
    required this.onDelete,
    this.onAddChild,
    this.depth = 0,
  });

  final String title;
  final IconData leading;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onAddChild;
  final int depth;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(left: depth == 0 ? 0 : 24, bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: depth == 0
            ? AppColors.darkSurface
            : AppColors.darkSurfaceElevated,
        borderRadius: BorderRadius.circular(depth == 0 ? 18 : 15),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        children: [
          Icon(leading, color: AppColors.darkPrimary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(36, 34),
            onPressed: onEdit,
            child: Icon(
              CupertinoIcons.pencil,
              color: AppColors.darkTextSecondary,
              size: 18,
            ),
          ),
          if (onAddChild != null)
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(36, 34),
              onPressed: onAddChild,
              child: Icon(
                CupertinoIcons.plus_circle,
                color: AppColors.darkTextSecondary,
                size: 18,
              ),
            ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(36, 34),
            onPressed: onDelete,
            child: Icon(
              CupertinoIcons.trash,
              color: AppColors.darkDanger,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

enum _TravelDetailTab { schedule, checklist }

class TravelDetailScreen extends StatefulWidget {
  const TravelDetailScreen({
    super.key,
    required this.family,
    required this.sessionToken,
    required this.trip,
  });

  final AppFamily family;
  final String sessionToken;
  final TravelTrip trip;

  @override
  State<TravelDetailScreen> createState() => _TravelDetailScreenState();
}

class _TravelDetailScreenState extends State<TravelDetailScreen> {
  final _apiClient = ApiClient();

  TravelTripDetail? _detail;
  String? _message;
  String? _draggingItineraryId;
  List<TravelItinerary>? _dragSnapshot;
  bool _dropAccepted = false;
  bool _isLoading = true;
  _TravelDetailTab _selectedTab = _TravelDetailTab.schedule;

  @override
  void initState() {
    super.initState();
    _loadTrip();
  }

  Future<void> _loadTrip() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final detail = await _apiClient.getTravelTripDetail(
        widget.sessionToken,
        familyId: widget.family.id,
        tripId: widget.trip.id,
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

  Future<void> _createItinerary({DateTime? initialDate}) async {
    final created = await Navigator.of(context).push<TravelItinerary>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (context) => _TravelItineraryFormScreen(
          familyId: widget.family.id,
          sessionToken: widget.sessionToken,
          trip: _detail?.trip ?? widget.trip,
          favoriteTags: _detail?.tags ?? const [],
          initialDate: initialDate,
        ),
      ),
    );

    if (created != null && mounted) {
      await _loadTrip();
    }
  }

  Future<void> _editTrip() async {
    final detail = _detail;
    final trip = detail?.trip ?? widget.trip;
    final result = await Navigator.of(context).push<_TravelTripFormResult>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (context) => _TravelTripFormScreen(
          familyId: widget.family.id,
          sessionToken: widget.sessionToken,
          trip: trip,
        ),
      ),
    );

    if (result?.isDeleted == true && mounted) {
      Navigator.of(context).pop(true);
      return;
    }

    final updated = result?.trip;
    if (updated != null && mounted) {
      setState(() {
        _detail = TravelTripDetail(
          trip: updated,
          itineraries: detail?.itineraries ?? const [],
          tags: detail?.tags ?? const [],
          checklistItems: detail?.checklistItems ?? const [],
        );
      });
      await _loadTrip();
    }
  }

  Future<void> _openItinerary(TravelItinerary itinerary) async {
    final changed = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(
        builder: (context) => _TravelItineraryDetailScreen(
          familyId: widget.family.id,
          sessionToken: widget.sessionToken,
          trip: _detail?.trip ?? widget.trip,
          itinerary: itinerary,
          favoriteTags: _detail?.tags ?? const [],
        ),
      ),
    );

    if (changed == true && mounted) {
      await _loadTrip();
    }
  }

  Future<void> _createChecklistItem({TravelTripChecklistItem? parent}) async {
    final name = await _showTravelTextInput(
      context,
      title: parent == null ? '체크리스트 추가' : '${parent.name} 하위 항목 추가',
      placeholder: parent == null ? '예: 여권' : '예: 여권 사본',
      maxLength: 40,
    );

    if (name == null || !mounted) {
      return;
    }

    try {
      final item = await _apiClient.createTravelTripChecklistItem(
        widget.sessionToken,
        familyId: widget.family.id,
        tripId: (_detail?.trip ?? widget.trip).id,
        name: name,
        parentId: parent?.id,
      );

      if (mounted) {
        _setChecklistItems([...?_detail?.checklistItems, item]);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    }
  }

  Future<void> _toggleChecklistItem(TravelTripChecklistItem item) async {
    final detail = _detail;
    if (detail == null) {
      return;
    }

    final nextChecked = !item.isChecked;
    _setChecklistItems(
      detail.checklistItems
          .map(
            (current) => current.id == item.id
                ? current.copyWith(isChecked: nextChecked)
                : current,
          )
          .toList(),
    );

    try {
      final updated = await _apiClient.updateTravelTripChecklistItem(
        widget.sessionToken,
        familyId: widget.family.id,
        tripId: detail.trip.id,
        itemId: item.id,
        isChecked: nextChecked,
      );

      if (mounted) {
        _setChecklistItems(
          (_detail?.checklistItems ?? const [])
              .map((current) => current.id == item.id ? updated : current)
              .toList(),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
        await _loadTrip();
      }
    }
  }

  Future<void> _deleteChecklistItem(TravelTripChecklistItem item) async {
    final detail = _detail;
    if (detail == null) {
      return;
    }

    final confirmed = await _confirmTravelDelete(
      context,
      title: '체크리스트를 삭제할까요?',
      content: '삭제한 항목은 복구할 수 없습니다.',
    );

    if (!confirmed || !mounted) {
      return;
    }

    try {
      await _apiClient.deleteTravelTripChecklistItem(
        widget.sessionToken,
        familyId: widget.family.id,
        tripId: detail.trip.id,
        itemId: item.id,
      );

      if (mounted) {
        _setChecklistItems(
          detail.checklistItems
              .where(
                (current) =>
                    current.id != item.id && current.parentId != item.id,
              )
              .toList(),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    }
  }

  Future<void> _saveChecklistItemsToFavorites() async {
    final detail = _detail;
    if (detail == null || detail.checklistItems.isEmpty) {
      return;
    }

    final confirmed = await _confirmTravelDelete(
      context,
      title: '즐겨찾기를 덮어쓸까요?',
      content: '기존 즐겨찾는 체크리스트가 모두 삭제되고 현재 여행 체크리스트로 대체됩니다.',
      confirmLabel: '덮어쓰기',
    );

    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _message = null;
    });

    try {
      await _apiClient.saveTravelTripChecklistItemsToFavorites(
        widget.sessionToken,
        familyId: widget.family.id,
        tripId: detail.trip.id,
      );

      if (mounted) {
        setState(() {
          _message = '현재 여행 체크리스트를 즐겨찾기에 저장했습니다.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    }
  }

  void _setChecklistItems(List<TravelTripChecklistItem> checklistItems) {
    final detail = _detail;
    if (detail == null) {
      return;
    }

    setState(() {
      _detail = TravelTripDetail(
        trip: detail.trip,
        itineraries: detail.itineraries,
        tags: detail.tags,
        checklistItems: checklistItems,
      );
      _message = null;
    });
  }

  Future<void> _moveItinerary(
    TravelItinerary dragged,
    DateTime targetDate, {
    String? beforeItineraryId,
  }) async {
    final detail = _detail;
    if (detail == null) {
      return;
    }

    if (beforeItineraryId == dragged.id) {
      final hasPreviewChange =
          _dragSnapshot != null &&
          !_hasSameItineraryArrangement(_dragSnapshot!, detail.itineraries);

      if (hasPreviewChange) {
        _dropAccepted = true;
        setState(() {
          _draggingItineraryId = null;
          _dragSnapshot = null;
          _message = null;
        });

        try {
          final updated = await _apiClient.reorderTravelItineraries(
            widget.sessionToken,
            familyId: widget.family.id,
            tripId: detail.trip.id,
            items: detail.itineraries
                .map(
                  (itinerary) => TravelItineraryOrderInput(
                    id: itinerary.id,
                    itineraryDate: itinerary.itineraryDate,
                  ),
                )
                .toList(),
          );

          if (mounted) {
            setState(() {
              _detail = updated;
            });
          }
        } catch (error) {
          if (mounted) {
            setState(() {
              _message = error.toString();
            });
            await _loadTrip();
          }
        }

        return;
      }

      setState(() {
        _draggingItineraryId = null;
        _dragSnapshot = null;
      });
      return;
    }

    _dropAccepted = true;
    final normalized = _repositionItinerary(
      detail.itineraries,
      dragged,
      targetDate,
      beforeItineraryId: beforeItineraryId,
    );

    if (normalized == null) {
      return;
    }

    setState(() {
      _draggingItineraryId = null;
      _dragSnapshot = null;
      _detail = TravelTripDetail(
        trip: detail.trip,
        itineraries: normalized,
        tags: detail.tags,
        checklistItems: detail.checklistItems,
      );
      _message = null;
    });

    try {
      final updated = await _apiClient.reorderTravelItineraries(
        widget.sessionToken,
        familyId: widget.family.id,
        tripId: detail.trip.id,
        items: normalized
            .map(
              (itinerary) => TravelItineraryOrderInput(
                id: itinerary.id,
                itineraryDate: itinerary.itineraryDate,
              ),
            )
            .toList(),
      );

      if (mounted) {
        setState(() {
          _detail = updated;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
        await _loadTrip();
      }
    }
  }

  void _previewMoveItinerary(
    TravelItinerary dragged,
    DateTime targetDate, {
    String? beforeItineraryId,
  }) {
    final detail = _detail;
    if (detail == null || _dropAccepted || beforeItineraryId == dragged.id) {
      return;
    }

    final normalized = _repositionItinerary(
      detail.itineraries,
      dragged,
      targetDate,
      beforeItineraryId: beforeItineraryId,
    );

    if (normalized == null ||
        _hasSameItineraryArrangement(detail.itineraries, normalized)) {
      return;
    }

    setState(() {
      _detail = TravelTripDetail(
        trip: detail.trip,
        itineraries: normalized,
        tags: detail.tags,
        checklistItems: detail.checklistItems,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final trip = detail?.trip ?? widget.trip;

    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          trip.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            inherit: false,
            color: AppColors.darkTextPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      child: SafeArea(
        child: RefreshableScrollView(
          onRefresh: _loadTrip,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
          children: [
            _TripHeader(trip: trip, onEdit: _isLoading ? null : _editTrip),
            const SizedBox(height: 14),
            _TravelDetailSegmentedControl(
              selectedTab: _selectedTab,
              onChanged: (value) {
                setState(() {
                  _selectedTab = value;
                });
              },
            ),
            if (_message != null) ...[
              const SizedBox(height: 14),
              _InlineMessage(message: _message!),
            ],
            const SizedBox(height: 18),
            if (_isLoading && detail == null)
              const Padding(
                padding: EdgeInsets.only(top: 56),
                child: Center(child: CupertinoActivityIndicator()),
              )
            else if (_selectedTab == _TravelDetailTab.schedule)
              ..._buildDaySections(trip, detail?.itineraries ?? [])
            else
              ..._buildChecklistItems(detail?.checklistItems ?? const []),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDaySections(
    TravelTrip trip,
    List<TravelItinerary> itineraries,
  ) {
    final days = _daysBetween(trip.startsOn, trip.endsOn);
    final byDate = <String, List<TravelItinerary>>{};

    for (final itinerary in itineraries) {
      byDate
          .putIfAbsent(_dateKey(itinerary.itineraryDate), () => [])
          .add(itinerary);
    }

    return [
      for (var index = 0; index < days.length; index++) ...[
        _TravelDaySection(
          dayIndex: index + 1,
          date: days[index],
          itineraries: byDate[_dateKey(days[index])] ?? const [],
          onAdd: () => _createItinerary(initialDate: days[index]),
          onOpen: _openItinerary,
          onMove: _moveItinerary,
          onPreviewMove: _previewMoveItinerary,
          onDragStarted: (itinerary) {
            setState(() {
              _draggingItineraryId = itinerary.id;
              _dragSnapshot = itineraries;
              _dropAccepted = false;
            });
          },
          onDragEnded: () {
            if (mounted) {
              setState(() {
                if (!_dropAccepted &&
                    _dragSnapshot != null &&
                    _detail != null) {
                  _detail = TravelTripDetail(
                    trip: _detail!.trip,
                    itineraries: _dragSnapshot!,
                    tags: _detail!.tags,
                    checklistItems: _detail!.checklistItems,
                  );
                }
                _draggingItineraryId = null;
                _dragSnapshot = null;
                _dropAccepted = false;
              });
            }
          },
          draggingItineraryId: _draggingItineraryId,
        ),
        if (index != days.length - 1) const SizedBox(height: 14),
      ],
    ];
  }

  List<Widget> _buildChecklistItems(List<TravelTripChecklistItem> items) {
    if (items.isEmpty) {
      return [
        const _ChecklistEmptyState(),
        _ChecklistAddLink(onPressed: () => _createChecklistItem()),
      ];
    }

    final childrenByParentId = <String, List<TravelTripChecklistItem>>{};
    final parentItems = <TravelTripChecklistItem>[];

    for (final item in items) {
      final parentId = item.parentId;
      if (parentId == null) {
        parentItems.add(item);
      } else {
        childrenByParentId.putIfAbsent(parentId, () => []).add(item);
      }
    }

    final visibleParents = parentItems.isEmpty ? items : parentItems;

    return [
      _ChecklistFavoriteSaveLink(onPressed: _saveChecklistItemsToFavorites),
      for (final item in visibleParents) ...[
        _TravelTripChecklistRow(
          item: item,
          onToggle: () => _toggleChecklistItem(item),
          onDelete: () => _deleteChecklistItem(item),
          onAddChild: () => _createChecklistItem(parent: item),
        ),
        for (final child in childrenByParentId[item.id] ?? const [])
          _TravelTripChecklistRow(
            item: child,
            depth: 1,
            onToggle: () => _toggleChecklistItem(child),
            onDelete: () => _deleteChecklistItem(child),
          ),
      ],
      _ChecklistAddLink(onPressed: () => _createChecklistItem()),
    ];
  }
}

class _TravelDetailSegmentedControl extends StatelessWidget {
  const _TravelDetailSegmentedControl({
    required this.selectedTab,
    required this.onChanged,
  });

  final _TravelDetailTab selectedTab;
  final ValueChanged<_TravelDetailTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: CupertinoSlidingSegmentedControl<_TravelDetailTab>(
        groupValue: selectedTab,
        thumbColor: AppColors.darkPrimary,
        backgroundColor: AppColors.darkSurfaceElevated,
        children: {
          _TravelDetailTab.schedule: _TravelSegmentLabel(
            label: '일정',
            selected: selectedTab == _TravelDetailTab.schedule,
          ),
          _TravelDetailTab.checklist: _TravelSegmentLabel(
            label: '체크리스트',
            selected: selectedTab == _TravelDetailTab.checklist,
          ),
        },
        onValueChanged: (value) {
          if (value != null) {
            onChanged(value);
          }
        },
      ),
    );
  }
}

class _TravelSegmentLabel extends StatelessWidget {
  const _TravelSegmentLabel({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        label,
        style: TextStyle(
          color: selected
              ? AppColors.darkBackground
              : AppColors.darkTextPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _TravelTripChecklistRow extends StatelessWidget {
  const _TravelTripChecklistRow({
    required this.item,
    required this.onToggle,
    required this.onDelete,
    this.onAddChild,
    this.depth = 0,
  });

  final TravelTripChecklistItem item;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback? onAddChild;
  final int depth;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
        left: depth == 0 ? 0 : 24,
        bottom: depth == 0 ? 10 : 8,
      ),
      decoration: BoxDecoration(
        color: depth == 0
            ? AppColors.darkSurface
            : AppColors.darkSurfaceElevated,
        borderRadius: BorderRadius.circular(depth == 0 ? 18 : 15),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        children: [
          CupertinoButton(
            padding: const EdgeInsets.only(left: 14, right: 10),
            minimumSize: const Size(44, 52),
            onPressed: onToggle,
            child: Icon(
              item.isChecked
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              color: item.isChecked
                  ? AppColors.darkPrimary
                  : AppColors.darkTextMuted,
              size: 23,
            ),
          ),
          Expanded(
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.centerLeft,
              onPressed: onToggle,
              child: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: item.isChecked
                      ? AppColors.darkTextMuted
                      : AppColors.darkTextPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  decoration: item.isChecked
                      ? TextDecoration.lineThrough
                      : null,
                  decorationColor: AppColors.darkTextMuted,
                  decorationThickness: 2,
                ),
              ),
            ),
          ),
          if (onAddChild != null)
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(40, 52),
              onPressed: onAddChild,
              child: Icon(
                CupertinoIcons.plus_circle,
                color: AppColors.darkTextSecondary,
                size: 18,
              ),
            ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 52),
            onPressed: onDelete,
            child: Icon(
              CupertinoIcons.trash,
              color: AppColors.darkDanger,
              size: 18,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _ChecklistEmptyState extends StatelessWidget {
  const _ChecklistEmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 44, bottom: 6),
      child: Column(
        children: [
          Icon(
            CupertinoIcons.checkmark_alt_circle,
            color: AppColors.darkTextMuted,
            size: 34,
          ),
          const SizedBox(height: 12),
          Text(
            '체크리스트가 없습니다.',
            style: TextStyle(
              color: AppColors.darkTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '여행 준비물을 하나씩 추가해 보세요.',
            style: TextStyle(color: AppColors.darkTextMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ChecklistFavoriteSaveLink extends StatelessWidget {
  const _ChecklistFavoriteSaveLink({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: CupertinoButton(
        padding: const EdgeInsets.only(bottom: 10),
        minimumSize: Size.zero,
        onPressed: onPressed,
        child: Text(
          '즐겨찾기에 저장',
          style: TextStyle(
            color: AppColors.darkTextMuted,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ChecklistAddLink extends StatelessWidget {
  const _ChecklistAddLink({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 12),
      onPressed: onPressed,
      child: Text(
        '+ 체크리스트 추가하기',
        style: TextStyle(
          color: AppColors.darkTextMuted,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TravelTripFormResult {
  const _TravelTripFormResult._({this.trip, required this.isDeleted});

  const _TravelTripFormResult.saved(TravelTrip trip)
    : this._(trip: trip, isDeleted: false);

  const _TravelTripFormResult.deleted() : this._(isDeleted: true);

  final TravelTrip? trip;
  final bool isDeleted;
}

class _TravelTripFormScreen extends StatefulWidget {
  const _TravelTripFormScreen({
    required this.familyId,
    required this.sessionToken,
    this.trip,
  });

  final String familyId;
  final String sessionToken;
  final TravelTrip? trip;

  @override
  State<_TravelTripFormScreen> createState() => _TravelTripFormScreenState();
}

class _TravelTripFormScreenState extends State<_TravelTripFormScreen> {
  final _apiClient = ApiClient();
  final _titleController = TextEditingController();

  DateTime _startsOn = _dateOnly(DateTime.now());
  DateTime _endsOn = _dateOnly(DateTime.now().add(const Duration(days: 2)));
  bool _isSaving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    final trip = widget.trip;
    if (trip != null) {
      _titleController.text = trip.title;
      _startsOn = trip.startsOn;
      _endsOn = trip.endsOn;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickStartsOn() async {
    final picked = await _pickDate(context, _startsOn);
    if (picked == null) {
      return;
    }

    setState(() {
      _startsOn = picked;
      if (_endsOn.isBefore(_startsOn)) {
        _endsOn = _startsOn;
      }
    });
  }

  Future<void> _pickEndsOn() async {
    final picked = await _pickDate(context, _endsOn);
    if (picked == null) {
      return;
    }

    setState(() {
      _endsOn = picked.isBefore(_startsOn) ? _startsOn : picked;
    });
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();

    if (title.isEmpty) {
      setState(() {
        _message = '여행 제목을 입력해 주세요.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      final existing = widget.trip;
      final trip = existing == null
          ? await _apiClient.createTravelTrip(
              widget.sessionToken,
              familyId: widget.familyId,
              title: title,
              startsOn: _startsOn,
              endsOn: _endsOn,
            )
          : await _apiClient.updateTravelTrip(
              widget.sessionToken,
              familyId: widget.familyId,
              tripId: existing.id,
              title: title,
              startsOn: _startsOn,
              endsOn: _endsOn,
            );

      if (mounted) {
        Navigator.of(context).pop(_TravelTripFormResult.saved(trip));
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _delete() async {
    final trip = widget.trip;
    if (trip == null) {
      return;
    }

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('여행을 삭제할까요?'),
        content: const Text('여행과 여행 안의 모든 일정이 삭제되며 복구할 수 없습니다.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      await _apiClient.deleteTravelTrip(
        widget.sessionToken,
        familyId: widget.familyId,
        tripId: trip.id,
      );

      if (mounted) {
        Navigator.of(context).pop(const _TravelTripFormResult.deleted());
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        middle: Text(widget.trip == null ? '새 여행 만들기' : '여행 수정'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const CupertinoActivityIndicator()
              : const Text('저장'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            if (_message != null) ...[
              _InlineMessage(message: _message!),
              const SizedBox(height: 14),
            ],
            _FormSection(
              children: [
                _LabeledTextField(
                  label: '여행 제목',
                  placeholder: '예: 제주 여행',
                  controller: _titleController,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _DateButton(
                        label: 'From',
                        value: _formatDate(_startsOn),
                        onPressed: _pickStartsOn,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DateButton(
                        label: 'To',
                        value: _formatDate(_endsOn),
                        onPressed: _pickEndsOn,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (widget.trip != null) ...[
              const SizedBox(height: 26),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _isSaving ? null : _delete,
                child: Text(
                  '여행 삭제',
                  style: TextStyle(
                    color: AppColors.darkDanger.withValues(alpha: 0.82),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
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

class _TravelItineraryFormScreen extends StatefulWidget {
  const _TravelItineraryFormScreen({
    required this.familyId,
    required this.sessionToken,
    required this.trip,
    required this.favoriteTags,
    this.initialDate,
    this.itinerary,
  });

  final String familyId;
  final String sessionToken;
  final TravelTrip trip;
  final List<TravelTag> favoriteTags;
  final DateTime? initialDate;
  final TravelItinerary? itinerary;

  @override
  State<_TravelItineraryFormScreen> createState() =>
      _TravelItineraryFormScreenState();
}

class _TravelItineraryFormScreenState
    extends State<_TravelItineraryFormScreen> {
  final _apiClient = ApiClient();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _mapUrlController = TextEditingController();
  final _tagController = TextEditingController();

  late DateTime _itineraryDate;
  late final Set<String> _selectedTagNames;
  final List<String> _customTagNames = [];
  TimeOfDayValue? _startsAt;
  bool _isSaving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    final itinerary = widget.itinerary;
    _itineraryDate = _dateOnly(
      widget.initialDate ?? itinerary?.itineraryDate ?? widget.trip.startsOn,
    );
    _selectedTagNames = {...?itinerary?.tags.map((tag) => tag.name)};

    if (itinerary != null) {
      _titleController.text = itinerary.title;
      _contentController.text = itinerary.content ?? '';
      _mapUrlController.text = itinerary.mapUrl ?? '';
      _startsAt = itinerary.startsAt;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _mapUrlController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await _pickDateInRange(
      context,
      initialDate: _itineraryDate,
      minimumDate: widget.trip.startsOn,
      maximumDate: widget.trip.endsOn,
    );

    if (picked != null) {
      setState(() {
        _itineraryDate = picked;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await _showTimePicker(context, initialTime: _startsAt);

    if (picked != null) {
      setState(() {
        _startsAt = picked;
      });
    }
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();

    if (title.isEmpty) {
      setState(() {
        _message = '일정 제목을 입력해 주세요.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      final existing = widget.itinerary;
      final itinerary = existing == null
          ? await _apiClient.createTravelItinerary(
              widget.sessionToken,
              familyId: widget.familyId,
              tripId: widget.trip.id,
              itineraryDate: _itineraryDate,
              title: title,
              content: _contentController.text.trim(),
              mapUrl: _mapUrlController.text.trim(),
              startsAt: _startsAt,
              tagNames: _selectedTagNames.toList(),
            )
          : await _apiClient.updateTravelItinerary(
              widget.sessionToken,
              familyId: widget.familyId,
              tripId: widget.trip.id,
              itineraryId: existing.id,
              itineraryDate: _itineraryDate,
              title: title,
              content: _contentController.text.trim(),
              mapUrl: _mapUrlController.text.trim(),
              startsAt: _startsAt,
              tagNames: _selectedTagNames.toList(),
            );

      if (mounted) {
        Navigator.of(context).pop(itinerary);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
          _isSaving = false;
        });
      }
    }
  }

  void _toggleTag(String tagName) {
    setState(() {
      if (_selectedTagNames.contains(tagName)) {
        _selectedTagNames.remove(tagName);
      } else {
        _selectedTagNames.add(tagName);
      }
    });
  }

  void _addCustomTag() {
    final tagName = _tagController.text.trim();

    if (tagName.isEmpty) {
      return;
    }

    if (tagName.length > 24) {
      setState(() {
        _message = '태그는 24자 이하로 입력해 주세요.';
      });
      return;
    }

    setState(() {
      if (!_allTagNames.contains(tagName)) {
        _customTagNames.add(tagName);
      }
      _selectedTagNames.add(tagName);
      _tagController.clear();
      _message = null;
    });
  }

  List<String> get _allTagNames {
    return [
      ...{
        ...widget.favoriteTags.map((tag) => tag.name),
        ..._customTagNames,
        ..._selectedTagNames,
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        middle: Text(widget.itinerary == null ? '여행 일정 추가' : '여행 일정 수정'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const CupertinoActivityIndicator()
              : const Text('저장'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            if (_message != null) ...[
              _InlineMessage(message: _message!),
              const SizedBox(height: 14),
            ],
            _FormSection(
              children: [
                _DateButton(
                  label: '날짜',
                  value: _formatDateWithWeekday(_itineraryDate),
                  onPressed: _pickDate,
                ),
                const SizedBox(height: 14),
                _LabeledTextField(
                  label: '제목',
                  placeholder: '예: 공항 도착',
                  controller: _titleController,
                ),
                const SizedBox(height: 14),
                _LabeledTextField(
                  label: '내용',
                  placeholder: '메모할 내용을 입력해 주세요.',
                  controller: _contentController,
                  minLines: 4,
                  maxLines: 8,
                ),
                const SizedBox(height: 14),
                _LabeledTextField(
                  label: '지도',
                  placeholder: '구글맵 링크',
                  controller: _mapUrlController,
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 14),
                _TravelTagPicker(
                  tagNames: _allTagNames,
                  selectedTagNames: _selectedTagNames,
                  controller: _tagController,
                  onToggle: _toggleTag,
                  onAdd: _addCustomTag,
                ),
                const SizedBox(height: 14),
                _TimeButton(
                  value: _startsAt == null ? '선택 안 함' : _formatTime(_startsAt!),
                  onPressed: _pickTime,
                  onClear: _startsAt == null
                      ? null
                      : () => setState(() {
                          _startsAt = null;
                        }),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TravelItineraryDetailScreen extends StatefulWidget {
  const _TravelItineraryDetailScreen({
    required this.familyId,
    required this.sessionToken,
    required this.trip,
    required this.itinerary,
    required this.favoriteTags,
  });

  final String familyId;
  final String sessionToken;
  final TravelTrip trip;
  final TravelItinerary itinerary;
  final List<TravelTag> favoriteTags;

  @override
  State<_TravelItineraryDetailScreen> createState() =>
      _TravelItineraryDetailScreenState();
}

class _TravelItineraryDetailScreenState
    extends State<_TravelItineraryDetailScreen> {
  final _apiClient = ApiClient();

  late TravelItinerary _itinerary;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _itinerary = widget.itinerary;
  }

  Future<void> _openMap() async {
    final mapUrl = _itinerary.mapUrl;
    if (mapUrl == null || mapUrl.trim().isEmpty) {
      return;
    }

    final uri = Uri.tryParse(mapUrl.trim());
    if (uri == null) {
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _edit() async {
    final updated = await Navigator.of(context).push<TravelItinerary>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (context) => _TravelItineraryFormScreen(
          familyId: widget.familyId,
          sessionToken: widget.sessionToken,
          trip: widget.trip,
          initialDate: _itinerary.itineraryDate,
          itinerary: _itinerary,
          favoriteTags: widget.favoriteTags,
        ),
      ),
    );

    if (updated != null && mounted) {
      setState(() {
        _itinerary = updated;
      });
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('일정을 삭제할까요?'),
        content: const Text('삭제한 여행 일정은 복구할 수 없습니다.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isDeleting = true;
    });

    try {
      await _apiClient.deleteTravelItinerary(
        widget.sessionToken,
        familyId: widget.familyId,
        tripId: widget.trip.id,
        itineraryId: _itinerary.id,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
        await showCupertinoDialog<void>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('삭제하지 못했습니다.'),
            content: Text(error.toString()),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('확인'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          _itinerary.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 32),
          onPressed: _isDeleting ? null : _edit,
          child: const Text('수정'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Text(
              _itinerary.title,
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _InfoPill(
                  icon: CupertinoIcons.calendar,
                  label: _formatDateWithWeekday(_itinerary.itineraryDate),
                ),
                if (_itinerary.startsAt != null) ...[
                  const SizedBox(width: 8),
                  _InfoPill(
                    icon: CupertinoIcons.clock,
                    label: _formatTime(_itinerary.startsAt!),
                  ),
                ],
              ],
            ),
            if ((_itinerary.content ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 22),
              _DetailBlock(
                title: '내용',
                child: Text(
                  _itinerary.content!.trim(),
                  style: TextStyle(
                    color: AppColors.darkTextSecondary,
                    fontSize: 16,
                    height: 1.45,
                  ),
                ),
              ),
            ],
            if (_itinerary.tags.isNotEmpty) ...[
              const SizedBox(height: 14),
              _DetailBlock(
                title: '태그',
                child: _TravelTagWrap(
                  tagNames: _itinerary.tags.map((tag) => tag.name).toList(),
                ),
              ),
            ],
            if ((_itinerary.mapUrl ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _openMap,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.darkPrimarySoft,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.darkBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.map,
                        color: AppColors.darkPrimary,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '지도에서 보기',
                          style: TextStyle(
                            color: AppColors.darkTextPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(
                        CupertinoIcons.arrow_up_right,
                        color: AppColors.darkTextMuted,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 26),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _isDeleting ? null : _delete,
              child: Text(
                _isDeleting ? '삭제 중...' : '일정 삭제',
                style: TextStyle(
                  color: AppColors.darkDanger,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TravelTripRow extends StatelessWidget {
  const _TravelTripRow({required this.trip, required this.onTap});

  final TravelTrip trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.brandLavender.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                CupertinoIcons.airplane,
                color: AppColors.brandLavender,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trip.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.darkTextPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${_formatDate(trip.startsOn)} ~ ${_formatDate(trip.endsOn)}',
                    style: TextStyle(
                      color: AppColors.darkTextSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_forward,
              color: AppColors.darkTextMuted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _TripHeader extends StatelessWidget {
  const _TripHeader({required this.trip, required this.onEdit});

  final TravelTrip trip;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.darkSurfaceElevated,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 58),
                child: Text(
                  trip.title,
                  style: TextStyle(
                    color: AppColors.darkTextPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoPill(
                    icon: CupertinoIcons.calendar,
                    label:
                        '${_formatDate(trip.startsOn)} ~ ${_formatDate(trip.endsOn)}',
                  ),
                  _InfoPill(
                    icon: CupertinoIcons.sun_max,
                    label:
                        '${_daysBetween(trip.startsOn, trip.endsOn).length}일',
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: -5,
            right: -6,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              minimumSize: Size.zero,
              onPressed: onEdit,
              child: Text(
                '수정',
                style: TextStyle(
                  color: AppColors.darkPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TravelDaySection extends StatelessWidget {
  const _TravelDaySection({
    required this.dayIndex,
    required this.date,
    required this.itineraries,
    required this.onAdd,
    required this.onOpen,
    required this.onMove,
    required this.onPreviewMove,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.draggingItineraryId,
  });

  final int dayIndex;
  final DateTime date;
  final List<TravelItinerary> itineraries;
  final VoidCallback onAdd;
  final ValueChanged<TravelItinerary> onOpen;
  final void Function(
    TravelItinerary itinerary,
    DateTime targetDate, {
    String? beforeItineraryId,
  })
  onMove;
  final void Function(
    TravelItinerary itinerary,
    DateTime targetDate, {
    String? beforeItineraryId,
  })
  onPreviewMove;
  final ValueChanged<TravelItinerary> onDragStarted;
  final VoidCallback onDragEnded;
  final String? draggingItineraryId;

  @override
  Widget build(BuildContext context) {
    final isDragging = draggingItineraryId != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppColors.darkPrimarySoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'DAY$dayIndex',
                  style: TextStyle(
                    color: AppColors.darkPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _formatDateWithWeekday(date),
                  style: TextStyle(
                    color: AppColors.darkTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(32, 32),
                onPressed: onAdd,
                child: Icon(
                  CupertinoIcons.plus_circle,
                  color: AppColors.brandCoral,
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (itineraries.isEmpty)
            _ItineraryDropZone(
              date: date,
              onMove: onMove,
              onPreviewMove: onPreviewMove,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: onAdd,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.darkSurfaceElevated,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.darkBorder),
                  ),
                  child: Text(
                    isDragging ? '이 DAY로 이동' : '등록된 일정이 없습니다.',
                    style: TextStyle(
                      color: isDragging
                          ? AppColors.darkPrimary
                          : AppColors.darkTextMuted,
                      fontSize: 14,
                      fontWeight: isDragging
                          ? FontWeight.w800
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            )
          else ...[
            for (var index = 0; index < itineraries.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ItineraryReorderTarget(
                  date: date,
                  itinerary: itineraries[index],
                  nextItineraryId: index == itineraries.length - 1
                      ? null
                      : itineraries[index + 1].id,
                  onMove: onMove,
                  onPreviewMove: onPreviewMove,
                  child: _DraggableItineraryRow(
                    itinerary: itineraries[index],
                    isDragging: draggingItineraryId == itineraries[index].id,
                    onTap: () => onOpen(itineraries[index]),
                    onDragStarted: () => onDragStarted(itineraries[index]),
                    onDragEnded: onDragEnded,
                  ),
                ),
              ),
            _ItineraryDropZone(
              date: date,
              onMove: onMove,
              onPreviewMove: onPreviewMove,
              child: SizedBox(
                width: double.infinity,
                height: isDragging ? 18 : 2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ItineraryReorderTarget extends StatelessWidget {
  const _ItineraryReorderTarget({
    required this.date,
    required this.itinerary,
    required this.onMove,
    required this.onPreviewMove,
    required this.child,
    this.nextItineraryId,
  });

  final DateTime date;
  final TravelItinerary itinerary;
  final String? nextItineraryId;
  final void Function(
    TravelItinerary itinerary,
    DateTime targetDate, {
    String? beforeItineraryId,
  })
  onMove;
  final void Function(
    TravelItinerary itinerary,
    DateTime targetDate, {
    String? beforeItineraryId,
  })
  onPreviewMove;
  final Widget child;

  String? _resolveBeforeItineraryId(
    BuildContext context,
    DragTargetDetails<TravelItinerary> details,
  ) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return itinerary.id;
    }

    final localOffset = box.globalToLocal(details.offset);
    return localOffset.dy < box.size.height / 2
        ? itinerary.id
        : nextItineraryId;
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<TravelItinerary>(
      onWillAcceptWithDetails: (_) => true,
      onMove: (details) {
        onPreviewMove(
          details.data,
          date,
          beforeItineraryId: _resolveBeforeItineraryId(context, details),
        );
      },
      onAcceptWithDetails: (details) {
        onMove(
          details.data,
          date,
          beforeItineraryId: _resolveBeforeItineraryId(context, details),
        );
      },
      builder: (context, candidates, rejected) => child,
    );
  }
}

class _DraggableItineraryRow extends StatelessWidget {
  const _DraggableItineraryRow({
    required this.itinerary,
    required this.isDragging,
    required this.onTap,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  final TravelItinerary itinerary;
  final bool isDragging;
  final VoidCallback onTap;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return LongPressDraggable<TravelItinerary>(
          data: itinerary,
          onDragStarted: onDragStarted,
          onDragEnd: (_) => onDragEnded(),
          onDraggableCanceled: (_, _) => onDragEnded(),
          onDragCompleted: onDragEnded,
          feedback: SizedBox(
            width: constraints.maxWidth,
            child: _ItineraryCard(itinerary: itinerary, elevated: true),
          ),
          childWhenDragging: IgnorePointer(
            child: _ItineraryCard(itinerary: itinerary),
          ),
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: isDragging ? null : onTap,
            child: _ItineraryCard(itinerary: itinerary),
          ),
        );
      },
    );
  }
}

class _ItineraryCard extends StatelessWidget {
  const _ItineraryCard({required this.itinerary, this.elevated = false});

  final TravelItinerary itinerary;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: elevated
            ? AppColors.darkPrimarySoft
            : AppColors.darkSurfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: elevated ? Border.all(color: AppColors.darkPrimary) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            if (itinerary.startsAt != null) ...[
              Text(
                _formatTime(itinerary.startsAt!),
                style: TextStyle(
                  color: AppColors.darkPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    itinerary.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.darkTextPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (itinerary.tags.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    _TravelTagWrap(
                      tagNames: itinerary.tags
                          .map((tag) => tag.name)
                          .take(3)
                          .toList(),
                      compact: true,
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_forward,
              color: AppColors.darkTextMuted,
              size: 15,
            ),
          ],
        ),
      ),
    );
  }
}

class _ItineraryDropZone extends StatelessWidget {
  const _ItineraryDropZone({
    required this.date,
    required this.onMove,
    required this.onPreviewMove,
    required this.child,
  });

  final DateTime date;
  final void Function(
    TravelItinerary itinerary,
    DateTime targetDate, {
    String? beforeItineraryId,
  })
  onMove;
  final void Function(
    TravelItinerary itinerary,
    DateTime targetDate, {
    String? beforeItineraryId,
  })
  onPreviewMove;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DragTarget<TravelItinerary>(
      onWillAcceptWithDetails: (_) => true,
      onMove: (details) {
        onPreviewMove(details.data, date);
      },
      onAcceptWithDetails: (details) {
        onMove(details.data, date);
      },
      builder: (context, candidates, rejected) {
        return child;
      },
    );
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _LabeledTextField extends StatelessWidget {
  const _LabeledTextField({
    required this.label,
    required this.placeholder,
    required this.controller,
    this.minLines = 1,
    this.maxLines = 1,
    this.keyboardType,
  });

  final String label;
  final String placeholder;
  final TextEditingController controller;
  final int minLines;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.darkTextSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        CupertinoTextField(
          controller: controller,
          minLines: minLines,
          maxLines: maxLines,
          keyboardType: keyboardType,
          placeholder: placeholder,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: AppColors.darkSurfaceElevated,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: AppColors.darkBorder),
          ),
          style: TextStyle(color: AppColors.darkTextPrimary, fontSize: 16),
          placeholderStyle: TextStyle(
            color: AppColors.darkTextMuted,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

class _TravelTagPicker extends StatelessWidget {
  const _TravelTagPicker({
    required this.tagNames,
    required this.selectedTagNames,
    required this.controller,
    required this.onToggle,
    required this.onAdd,
  });

  final List<String> tagNames;
  final Set<String> selectedTagNames;
  final TextEditingController controller;
  final ValueChanged<String> onToggle;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '태그',
          style: TextStyle(
            color: AppColors.darkTextSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (tagNames.isNotEmpty)
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final tagName in tagNames)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: () => onToggle(tagName),
                  child: _TravelTagChip(
                    label: tagName,
                    selected: selectedTagNames.contains(tagName),
                  ),
                ),
            ],
          ),
        if (tagNames.isNotEmpty) const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: controller,
                placeholder: '직접입력',
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onAdd(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.darkSurfaceElevated,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: AppColors.darkBorder),
                ),
                style: TextStyle(
                  color: AppColors.darkTextPrimary,
                  fontSize: 15,
                ),
                placeholderStyle: TextStyle(
                  color: AppColors.darkTextMuted,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 8),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(42, 42),
              onPressed: onAdd,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.darkPrimary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  CupertinoIcons.plus,
                  color: AppColors.darkBackground,
                  size: 19,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TravelTagWrap extends StatelessWidget {
  const _TravelTagWrap({required this.tagNames, this.compact = false});

  final List<String> tagNames;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: compact ? 5 : 7,
      runSpacing: compact ? 5 : 7,
      children: [
        for (final tagName in tagNames)
          _TravelTagChip(label: tagName, compact: compact),
      ],
    );
  }
}

class _TravelTagChip extends StatelessWidget {
  const _TravelTagChip({
    required this.label,
    this.selected = false,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.darkPrimary
            : AppColors.darkPrimarySoft.withValues(alpha: compact ? 0.45 : 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected ? AppColors.darkPrimary : AppColors.darkBorder,
        ),
      ),
      child: Text(
        '#$label',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: selected
              ? AppColors.darkBackground
              : AppColors.darkTextPrimary,
          fontSize: compact ? 11 : 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final String label;
  final String value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.darkSurfaceElevated,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: AppColors.darkTextMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.value,
    required this.onPressed,
    required this.onClear,
  });

  final String value;
  final VoidCallback onPressed;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _DateButton(label: '시간', value: value, onPressed: onPressed),
        ),
        if (onClear != null) ...[
          const SizedBox(width: 10),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(42, 42),
            onPressed: onClear,
            child: Icon(
              CupertinoIcons.xmark_circle_fill,
              color: AppColors.darkTextMuted,
            ),
          ),
        ],
      ],
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppColors.darkTextMuted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.darkPrimarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.darkPrimary, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: AppColors.darkTextPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.brandCoral.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brandCoral.withValues(alpha: 0.4)),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: AppColors.darkTextPrimary,
          fontSize: 13,
          height: 1.3,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 54),
      child: Column(
        children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              color: AppColors.darkPrimarySoft,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(icon, color: AppColors.darkPrimary, size: 34),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.darkTextPrimary,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.darkTextSecondary,
              fontSize: 14,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 22),
          CupertinoButton.filled(
            borderRadius: BorderRadius.circular(16),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            onPressed: onPressed,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _FeatureFamilyTitle extends StatelessWidget {
  const _FeatureFamilyTitle({
    required this.family,
    required this.featureName,
    required this.canSwitch,
    required this.onPressed,
  });

  final AppFamily family;
  final String featureName;
  final bool canSwitch;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final title = '${family.name} $featureName';

    if (!canSwitch) {
      return Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          inherit: false,
          color: AppColors.darkTextPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      );
    }

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 32),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                inherit: false,
                color: AppColors.darkTextPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(CupertinoIcons.chevron_down, size: 15),
        ],
      ),
    );
  }
}

Future<DateTime?> _pickDate(BuildContext context, DateTime initialDate) {
  return _pickDateInRange(
    context,
    initialDate: initialDate,
    minimumDate: DateTime(2000),
    maximumDate: DateTime(2100),
  );
}

Future<DateTime?> _pickDateInRange(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime minimumDate,
  required DateTime maximumDate,
}) async {
  var selected = _dateOnly(initialDate);

  return showCupertinoModalPopup<DateTime>(
    context: context,
    builder: (context) {
      return Container(
        height: 320,
        color: AppColors.darkSurface,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              SizedBox(
                height: 52,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('취소'),
                    ),
                    CupertinoButton(
                      onPressed: () => Navigator.of(context).pop(selected),
                      child: const Text('선택'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: selected,
                  minimumDate: minimumDate,
                  maximumDate: maximumDate,
                  onDateTimeChanged: (value) {
                    selected = _dateOnly(value);
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<String?> _showTravelTextInput(
  BuildContext context, {
  required String title,
  required String placeholder,
  String? initialValue,
  required int maxLength,
}) async {
  final controller = TextEditingController(text: initialValue ?? '');
  String? errorText;

  final result = await showCupertinoDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        return CupertinoAlertDialog(
          title: Text(title),
          content: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              children: [
                CupertinoTextField(
                  controller: controller,
                  autofocus: true,
                  placeholder: placeholder,
                  maxLength: maxLength,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    final value = controller.text.trim();
                    if (value.isEmpty || value.length > maxLength) {
                      setDialogState(() {
                        errorText = '$maxLength자 이하로 입력해 주세요.';
                      });
                      return;
                    }
                    Navigator.of(context).pop(value);
                  },
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorText!,
                    style: TextStyle(color: AppColors.darkDanger, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty || value.length > maxLength) {
                  setDialogState(() {
                    errorText = '$maxLength자 이하로 입력해 주세요.';
                  });
                  return;
                }
                Navigator.of(context).pop(value);
              },
              child: const Text('저장'),
            ),
          ],
        );
      },
    ),
  );

  controller.dispose();
  return result;
}

Future<bool> _confirmTravelDelete(
  BuildContext context, {
  required String title,
  required String content,
  String confirmLabel = '삭제',
}) async {
  final confirmed = await showCupertinoDialog<bool>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        CupertinoDialogAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  return confirmed == true;
}

Future<TimeOfDayValue?> _showTimePicker(
  BuildContext context, {
  required TimeOfDayValue? initialTime,
}) async {
  var selected = DateTime(
    2000,
    1,
    1,
    initialTime?.hour ?? 9,
    initialTime?.minute ?? 0,
  );

  return showCupertinoModalPopup<TimeOfDayValue>(
    context: context,
    builder: (context) {
      return Container(
        height: 300,
        color: AppColors.darkSurface,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              SizedBox(
                height: 52,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('취소'),
                    ),
                    CupertinoButton(
                      onPressed: () => Navigator.of(context).pop(
                        TimeOfDayValue(
                          hour: selected.hour,
                          minute: selected.minute,
                        ),
                      ),
                      child: const Text('선택'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: selected,
                  use24hFormat: false,
                  minuteInterval: 1,
                  onDateTimeChanged: (value) {
                    selected = value;
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

List<TravelItinerary>? _repositionItinerary(
  List<TravelItinerary> itineraries,
  TravelItinerary dragged,
  DateTime targetDate, {
  String? beforeItineraryId,
}) {
  final nextItineraries = [...itineraries];
  final sourceIndex = nextItineraries.indexWhere(
    (itinerary) => itinerary.id == dragged.id,
  );

  if (sourceIndex < 0) {
    return null;
  }

  final moving = nextItineraries
      .removeAt(sourceIndex)
      .copyWith(itineraryDate: _dateOnly(targetDate));
  final insertIndex = _resolveDropIndex(
    nextItineraries,
    targetDate,
    beforeItineraryId: beforeItineraryId,
  );
  nextItineraries.insert(insertIndex, moving);

  return _normalizeItinerarySortOrders(nextItineraries);
}

int _resolveDropIndex(
  List<TravelItinerary> itineraries,
  DateTime targetDate, {
  String? beforeItineraryId,
}) {
  if (beforeItineraryId != null) {
    final beforeIndex = itineraries.indexWhere(
      (itinerary) => itinerary.id == beforeItineraryId,
    );

    if (beforeIndex >= 0) {
      return beforeIndex;
    }
  }

  final targetKey = _dateKey(targetDate);
  var lastTargetDateIndex = -1;

  for (var index = 0; index < itineraries.length; index++) {
    if (_dateKey(itineraries[index].itineraryDate) == targetKey) {
      lastTargetDateIndex = index;
    }
  }

  if (lastTargetDateIndex >= 0) {
    return lastTargetDateIndex + 1;
  }

  for (var index = 0; index < itineraries.length; index++) {
    if (_dateOnly(
      itineraries[index].itineraryDate,
    ).isAfter(_dateOnly(targetDate))) {
      return index;
    }
  }

  return itineraries.length;
}

bool _hasSameItineraryArrangement(
  List<TravelItinerary> a,
  List<TravelItinerary> b,
) {
  if (a.length != b.length) {
    return false;
  }

  for (var index = 0; index < a.length; index++) {
    if (a[index].id != b[index].id ||
        !_isSameDate(a[index].itineraryDate, b[index].itineraryDate)) {
      return false;
    }
  }

  return true;
}

List<TravelItinerary> _normalizeItinerarySortOrders(
  List<TravelItinerary> itineraries,
) {
  final sortOrderByDate = <String, int>{};

  return itineraries.map((itinerary) {
    final dateKey = _dateKey(itinerary.itineraryDate);
    final sortOrder = (sortOrderByDate[dateKey] ?? 0) + 1;
    sortOrderByDate[dateKey] = sortOrder;

    return itinerary.copyWith(sortOrder: sortOrder);
  }).toList();
}

List<DateTime> _daysBetween(DateTime startsOn, DateTime endsOn) {
  final start = _dateOnly(startsOn);
  final end = _dateOnly(endsOn);
  final dayCount = end.difference(start).inDays + 1;

  return List.generate(dayCount, (index) => start.add(Duration(days: index)));
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _dateKey(DateTime value) {
  final date = _dateOnly(value);
  return '${date.year}-${_twoDigits(date.month)}-${_twoDigits(date.day)}';
}

String _formatDate(DateTime value) {
  final date = _dateOnly(value);
  return '${date.year}.${_twoDigits(date.month)}.${_twoDigits(date.day)}';
}

String _formatDateWithWeekday(DateTime value) {
  return '${_formatDate(value)} (${_weekdayLabel(value)})';
}

String _weekdayLabel(DateTime value) {
  const labels = ['월', '화', '수', '목', '금', '토', '일'];
  return labels[value.weekday - 1];
}

String _formatTime(TimeOfDayValue value) {
  final isAm = value.hour < 12;
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  return '${isAm ? '오전' : '오후'} $hour:${_twoDigits(value.minute)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
