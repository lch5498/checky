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
    final created = await Navigator.of(context).push<TravelTrip>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (context) => _TravelTripFormScreen(
          familyId: _family.id,
          sessionToken: widget.sessionToken,
        ),
      ),
    );

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

  void _openTrip(TravelTrip trip) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (context) => TravelDetailScreen(
          family: _family,
          sessionToken: widget.sessionToken,
          trip: trip,
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
  bool _isLoading = true;

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
          initialDate: initialDate,
        ),
      ),
    );

    if (created != null && mounted) {
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
        ),
      ),
    );

    if (changed == true && mounted) {
      await _loadTrip();
    }
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
      setState(() {
        _draggingItineraryId = null;
      });
      return;
    }

    final nextItineraries = [...detail.itineraries];
    final sourceIndex = nextItineraries.indexWhere(
      (itinerary) => itinerary.id == dragged.id,
    );

    if (sourceIndex < 0) {
      return;
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

    final normalized = _normalizeItinerarySortOrders(nextItineraries);

    setState(() {
      _draggingItineraryId = null;
      _detail = TravelTripDetail(trip: detail.trip, itineraries: normalized);
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
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 32),
          onPressed: _isLoading ? null : () => _createItinerary(),
          child: const Icon(CupertinoIcons.plus),
        ),
      ),
      child: SafeArea(
        child: RefreshableScrollView(
          onRefresh: _loadTrip,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
          children: [
            _TripHeader(trip: trip),
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
            else
              ..._buildDaySections(trip, detail?.itineraries ?? []),
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
          onDragStarted: (itinerary) {
            setState(() {
              _draggingItineraryId = itinerary.id;
            });
          },
          onDragEnded: () {
            if (mounted) {
              setState(() {
                _draggingItineraryId = null;
              });
            }
          },
          draggingItineraryId: _draggingItineraryId,
        ),
        if (index != days.length - 1) const SizedBox(height: 14),
      ],
    ];
  }
}

class _TravelTripFormScreen extends StatefulWidget {
  const _TravelTripFormScreen({
    required this.familyId,
    required this.sessionToken,
  });

  final String familyId;
  final String sessionToken;

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
      final trip = await _apiClient.createTravelTrip(
        widget.sessionToken,
        familyId: widget.familyId,
        title: title,
        startsOn: _startsOn,
        endsOn: _endsOn,
      );

      if (mounted) {
        Navigator.of(context).pop(trip);
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
        middle: const Text('새 여행 만들기'),
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
                  placeholder: '예: 제주 가족여행',
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
    this.initialDate,
    this.itinerary,
  });

  final String familyId;
  final String sessionToken;
  final TravelTrip trip;
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

  late DateTime _itineraryDate;
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
  });

  final String familyId;
  final String sessionToken;
  final TravelTrip trip;
  final TravelItinerary itinerary;

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
  const _TripHeader({required this.trip});

  final TravelTrip trip;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            trip.title,
            style: TextStyle(
              color: AppColors.darkTextPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              height: 1.15,
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
                label: '${_daysBetween(trip.startsOn, trip.endsOn).length}일',
              ),
            ],
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
            ...itineraries.map(
              (itinerary) => _ItineraryDropZone(
                date: date,
                beforeItineraryId: itinerary.id,
                onMove: onMove,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _DraggableItineraryRow(
                    itinerary: itinerary,
                    isDragging: draggingItineraryId == itinerary.id,
                    onTap: () => onOpen(itinerary),
                    onDragStarted: () => onDragStarted(itinerary),
                    onDragEnded: onDragEnded,
                  ),
                ),
              ),
            ),
            _ItineraryDropZone(
              date: date,
              onMove: onMove,
              compact: true,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: double.infinity,
                height: isDragging ? 34 : 4,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDragging
                      ? AppColors.darkPrimarySoft
                      : CupertinoColors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isDragging
                      ? Border.all(color: AppColors.darkBorder)
                      : null,
                ),
                child: isDragging
                    ? Text(
                        '이 DAY 마지막으로 이동',
                        style: TextStyle(
                          color: AppColors.darkPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : null,
              ),
            ),
          ],
        ],
      ),
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
    return LongPressDraggable<TravelItinerary>(
      data: itinerary,
      onDragStarted: onDragStarted,
      onDragEnd: (_) => onDragEnded(),
      onDraggableCanceled: (_, _) => onDragEnded(),
      onDragCompleted: onDragEnded,
      feedback: SizedBox(
        width: 280,
        child: _ItineraryCard(itinerary: itinerary, elevated: true),
      ),
      childWhenDragging: Opacity(
        opacity: 0.34,
        child: _ItineraryCard(itinerary: itinerary),
      ),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: isDragging ? null : onTap,
        child: _ItineraryCard(itinerary: itinerary),
      ),
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
            Icon(
              CupertinoIcons.line_horizontal_3,
              color: AppColors.darkTextMuted,
              size: 16,
            ),
            const SizedBox(width: 8),
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
              child: Text(
                itinerary.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.darkTextPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
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
    required this.child,
    this.beforeItineraryId,
    this.compact = false,
  });

  final DateTime date;
  final String? beforeItineraryId;
  final void Function(
    TravelItinerary itinerary,
    DateTime targetDate, {
    String? beforeItineraryId,
  })
  onMove;
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DragTarget<TravelItinerary>(
      onWillAcceptWithDetails: (details) =>
          details.data.id != beforeItineraryId,
      onAcceptWithDetails: (details) {
        onMove(details.data, date, beforeItineraryId: beforeItineraryId);
      },
      builder: (context, candidates, rejected) {
        final isActive = candidates.isNotEmpty;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: EdgeInsets.only(
            top: isActive ? 6 : 0,
            bottom: isActive ? 6 : 0,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: isActive
                ? Border.all(color: AppColors.darkPrimary, width: 1.4)
                : null,
          ),
          child: compact && !isActive ? child : child,
        );
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
