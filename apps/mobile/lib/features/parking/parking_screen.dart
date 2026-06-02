import 'package:flutter/cupertino.dart';

import '../../core/api_client.dart';

const _parkingPresetTypeFloor = 'floor';
const _parkingPresetTypeSpot = 'spot';
const _defaultFloorChoices = ['B1', 'B2', 'B3', 'B4'];
const _defaultSpotChoices = ['101동', '107동', '가운데'];

class ParkingScreen extends StatefulWidget {
  const ParkingScreen({
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
  State<ParkingScreen> createState() => _ParkingScreenState();
}

class _ParkingScreenState extends State<ParkingScreen> {
  final _apiClient = ApiClient();

  late AppFamily _family;
  ParkingDashboard? _dashboard;
  String? _message;
  bool _isLoading = true;
  final Set<String> _registeringLocationVehicleIds = {};

  Map<String, ParkingRecord> get _currentLocationsByVehicleId {
    final dashboard = _dashboard;

    if (dashboard == null) {
      return const {};
    }

    return {
      for (final record in dashboard.currentLocations) record.vehicleId: record,
    };
  }

  @override
  void initState() {
    super.initState();
    _family = widget.family;
    _loadParking();
  }

  @override
  void didUpdateWidget(covariant ParkingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.family.id != widget.family.id) {
      _family = widget.family;
      _loadParking();
    }
  }

  Future<void> _loadParking() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final dashboard = await _apiClient.getParkingDashboard(
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

  Future<void> _runTask(Future<void> Function() task) async {
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

  Future<void> _openVehicleForm({Vehicle? vehicle}) async {
    final input = await showCupertinoDialog<_VehicleInput>(
      context: context,
      builder: (_) => _VehicleDialog(vehicle: vehicle),
    );

    if (input == null) {
      return;
    }

    await _runTask(() async {
      if (vehicle == null) {
        await _apiClient.createVehicle(
          widget.sessionToken,
          familyId: _family.id,
          nickname: input.nickname,
          plateNumber: input.plateNumber,
        );
      } else {
        await _apiClient.updateVehicle(
          widget.sessionToken,
          familyId: _family.id,
          vehicleId: vehicle.id,
          nickname: input.nickname,
          plateNumber: input.plateNumber,
        );
      }

      await _loadParking();
    });
  }

  Future<void> _deleteVehicle(Vehicle vehicle) async {
    final confirmed = await _confirm(
      title: '차량 삭제',
      message: '${vehicle.nickname} 차량을 삭제할까요? 주차 기록도 함께 삭제됩니다.',
      actionText: '삭제',
    );

    if (!confirmed) {
      return;
    }

    await _runTask(() async {
      await _apiClient.deleteVehicle(
        widget.sessionToken,
        familyId: _family.id,
        vehicleId: vehicle.id,
      );
      await _loadParking();
    });
  }

  Future<void> _openPresetManagement() async {
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => ParkingPresetScreen(
          family: _family,
          sessionToken: widget.sessionToken,
          canManage: _dashboard?.canManage ?? false,
        ),
      ),
    );
    await _loadParking();
  }

  Future<void> _registerParkingLocation(Vehicle vehicle) async {
    final dashboard = _dashboard;

    if (dashboard == null) {
      return;
    }

    final currentLocation = _currentLocationsByVehicleId[vehicle.id];
    final selected = await showCupertinoModalPopup<_ParkingLocationInput>(
      context: context,
      builder: (_) => _LocationPickerSheet(
        presets: dashboard.presets,
        currentLocation: currentLocation,
      ),
    );

    if (selected == null) {
      return;
    }

    setState(() {
      _message = null;
      _registeringLocationVehicleIds.add(vehicle.id);
    });

    try {
      await _apiClient.createParkingRecord(
        widget.sessionToken,
        familyId: _family.id,
        vehicleId: vehicle.id,
        floorPresetId: selected.floorPresetId,
        spotPresetId: selected.spotPresetId,
        floorText: selected.floorText,
        spotText: selected.spotText,
      );
      await _loadParking();
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _registeringLocationVehicleIds.remove(vehicle.id);
        });
      }
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String actionText,
  }) async {
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(actionText),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<void> _switchFamily() async {
    if (widget.families.length < 2) {
      return;
    }

    final selectedFamilyId = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('가족 전환'),
        actions: widget.families
            .map(
              (family) => CupertinoActionSheetAction(
                isDefaultAction: family.id == _family.id,
                onPressed: () => Navigator.of(sheetContext).pop(family.id),
                child: Text(family.name),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('취소'),
        ),
      ),
    );

    if (selectedFamilyId == null) {
      return;
    }

    final selectedFamily = widget.families.firstWhere(
      (family) => family.id == selectedFamilyId,
    );

    setState(() {
      _family = selectedFamily;
      _dashboard = null;
    });
    await widget.onSelectFamily(selectedFamily);
    await _loadParking();
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = _dashboard;

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      navigationBar: CupertinoNavigationBar(
        leading: dashboard == null
            ? null
            : CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(32, 32),
                onPressed: _isLoading ? null : _openPresetManagement,
                child: const Icon(
                  CupertinoIcons.star_fill,
                  color: CupertinoColors.systemOrange,
                  size: 20,
                ),
              ),
        middle: _FeatureFamilyTitle(
          family: _family,
          featureName: '주차',
          canSwitch: widget.families.length > 1,
          onPressed: _switchFamily,
        ),
        trailing: dashboard?.canManage == true
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(32, 32),
                onPressed: _isLoading ? null : () => _openVehicleForm(),
                child: const Icon(CupertinoIcons.plus),
              )
            : null,
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            if (_message != null) ...[
              _InlineMessage(message: _message!),
              const SizedBox(height: 18),
            ],
            if (_isLoading && dashboard == null)
              const Padding(
                padding: EdgeInsets.only(top: 72),
                child: Center(child: CupertinoActivityIndicator()),
              )
            else if (dashboard == null)
              _EmptyState(
                title: '주차 정보를 불러오지 못했습니다.',
                subtitle: '잠시 후 다시 시도해 주세요.',
                actionLabel: '다시 불러오기',
                onPressed: _loadParking,
              )
            else if (dashboard.vehicles.isEmpty)
              _EmptyState(
                title: '등록된 차량이 없습니다.',
                subtitle: dashboard.canManage
                    ? '차량을 먼저 등록하면 주차 위치를 기록할 수 있습니다.'
                    : '대표 또는 공동대표가 차량을 등록하면 주차 위치를 볼 수 있습니다.',
                actionLabel: '차량 등록',
                onPressed: dashboard.canManage
                    ? () => _openVehicleForm()
                    : null,
              )
            else
              ...dashboard.vehicles.map(
                (vehicle) => _VehicleCard(
                  vehicle: vehicle,
                  currentLocation: _currentLocationsByVehicleId[vehicle.id],
                  isRegisteringLocation: _registeringLocationVehicleIds
                      .contains(vehicle.id),
                  canManage: dashboard.canManage,
                  onRegisterLocation: () => _registerParkingLocation(vehicle),
                  onEdit: () => _openVehicleForm(vehicle: vehicle),
                  onDelete: () => _deleteVehicle(vehicle),
                ),
              ),
          ],
        ),
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
        style: const TextStyle(
          inherit: false,
          color: Color(0xFF111111),
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
              style: const TextStyle(
                inherit: false,
                color: Color(0xFF111111),
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

class ParkingPresetScreen extends StatefulWidget {
  const ParkingPresetScreen({
    super.key,
    required this.family,
    required this.sessionToken,
    required this.canManage,
  });

  final AppFamily family;
  final String sessionToken;
  final bool canManage;

  @override
  State<ParkingPresetScreen> createState() => _ParkingPresetScreenState();
}

class _ParkingPresetScreenState extends State<ParkingPresetScreen> {
  final _apiClient = ApiClient();

  List<ParkingLocationPreset> _presets = const [];
  List<ParkingLocationPreset> get _floorPresets => _presets
      .where((preset) => preset.presetType == _parkingPresetTypeFloor)
      .toList();
  List<ParkingLocationPreset> get _spotPresets => _presets
      .where((preset) => preset.presetType == _parkingPresetTypeSpot)
      .toList();
  String? _message;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPresets();
  }

  Future<void> _loadPresets() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final dashboard = await _apiClient.getParkingDashboard(
        widget.sessionToken,
        familyId: widget.family.id,
      );

      if (mounted) {
        setState(() {
          _presets = dashboard.presets;
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

  Future<void> _runTask(Future<void> Function() task) async {
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

  Future<void> _openPresetForm({
    required String presetType,
    ParkingLocationPreset? preset,
  }) async {
    final name = preset == null
        ? await _pickPresetName(presetType)
        : await showCupertinoDialog<String>(
            context: context,
            builder: (_) => _PresetDialog(preset: preset),
          );

    if (name == null) {
      return;
    }

    await _runTask(() async {
      if (preset == null) {
        await _apiClient.createParkingLocationPreset(
          widget.sessionToken,
          familyId: widget.family.id,
          presetType: presetType,
          name: name,
        );
      } else {
        await _apiClient.updateParkingLocationPreset(
          widget.sessionToken,
          familyId: widget.family.id,
          presetId: preset.id,
          presetType: presetType,
          name: name,
        );
      }

      await _loadPresets();
    });
  }

  Future<void> _openPresetTypePicker() async {
    final presetType = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('즐겨찾기 추가'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.of(sheetContext).pop(_parkingPresetTypeFloor),
            child: const Text('자주 쓰는 층수'),
          ),
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.of(sheetContext).pop(_parkingPresetTypeSpot),
            child: const Text('자주 쓰는 위치'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('취소'),
        ),
      ),
    );

    if (presetType == null) {
      return;
    }

    await _openPresetForm(presetType: presetType);
  }

  Future<String?> _pickPresetName(String presetType) async {
    final defaults = presetType == _parkingPresetTypeFloor
        ? _defaultFloorChoices
        : _defaultSpotChoices;
    final title = presetType == _parkingPresetTypeFloor
        ? '자주 쓰는 층수'
        : '자주 쓰는 위치';

    return showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text(title),
        actions: [
          for (final value in defaults)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(popupContext).pop(value),
              child: Text(value),
            ),
          CupertinoActionSheetAction(
            onPressed: () async {
              final custom = await showCupertinoDialog<String>(
                context: popupContext,
                builder: (_) => _TextInputDialog(
                  title: '$title 직접 입력',
                  placeholder: presetType == _parkingPresetTypeFloor
                      ? '예: B5'
                      : '예: 105동',
                  maxLength: 40,
                ),
              );

              if (custom != null && popupContext.mounted) {
                Navigator.of(popupContext).pop(custom);
              }
            },
            child: const Text('직접 입력'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: const Text('취소'),
        ),
      ),
    );
  }

  Future<void> _deletePreset(ParkingLocationPreset preset) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('즐겨찾기 삭제'),
        content: Text('${preset.name} 즐겨찾기를 삭제할까요?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await _runTask(() async {
      await _apiClient.deleteParkingLocationPreset(
        widget.sessionToken,
        familyId: widget.family.id,
        presetId: preset.id,
      );
      await _loadPresets();
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      navigationBar: CupertinoNavigationBar(
        middle: const Text('주차 위치 즐겨찾기'),
        trailing: widget.canManage
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(32, 32),
                onPressed: _isLoading ? null : _openPresetTypePicker,
                child: const Icon(CupertinoIcons.plus),
              )
            : null,
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            const Text(
              '자주 쓰는 주차 위치',
              style: TextStyle(
                color: Color(0xFF111111),
                fontSize: 28,
                fontWeight: FontWeight.w800,
                height: 1.12,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '층수와 위치를 나눠 등록해 두면 주차 위치를 빠르게 기록할 수 있습니다.',
              style: TextStyle(
                color: Color(0xFF6E6E73),
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 14),
              _InlineMessage(message: _message!),
            ],
            const SizedBox(height: 18),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 56),
                child: Center(child: CupertinoActivityIndicator()),
              )
            else ...[
              _PresetSection(
                title: '자주 쓰는 층수',
                presets: _floorPresets,
                canManage: widget.canManage,
                emptyText: '등록된 층수가 없습니다.',
                onAdd: () =>
                    _openPresetForm(presetType: _parkingPresetTypeFloor),
                onEdit: (preset) => _openPresetForm(
                  presetType: _parkingPresetTypeFloor,
                  preset: preset,
                ),
                onDelete: _deletePreset,
              ),
              const SizedBox(height: 14),
              _PresetSection(
                title: '자주 쓰는 위치',
                presets: _spotPresets,
                canManage: widget.canManage,
                emptyText: '등록된 위치가 없습니다.',
                onAdd: () =>
                    _openPresetForm(presetType: _parkingPresetTypeSpot),
                onEdit: (preset) => _openPresetForm(
                  presetType: _parkingPresetTypeSpot,
                  preset: preset,
                ),
                onDelete: _deletePreset,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PresetSection extends StatelessWidget {
  const _PresetSection({
    required this.title,
    required this.presets,
    required this.canManage,
    required this.emptyText,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final String title;
  final List<ParkingLocationPreset> presets;
  final bool canManage;
  final String emptyText;
  final VoidCallback onAdd;
  final ValueChanged<ParkingLocationPreset> onEdit;
  final ValueChanged<ParkingLocationPreset> onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF111111),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (canManage)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(34, 34),
                  onPressed: onAdd,
                  child: const Icon(CupertinoIcons.plus_circle_fill, size: 22),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (presets.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                emptyText,
                style: const TextStyle(
                  color: Color(0xFF8E8E93),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            )
          else
            for (final preset in presets) ...[
              _PresetTile(
                preset: preset,
                canManage: canManage,
                onEdit: () => onEdit(preset),
                onDelete: () => onDelete(preset),
              ),
              if (preset != presets.last) const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.vehicle,
    required this.currentLocation,
    required this.isRegisteringLocation,
    required this.canManage,
    required this.onRegisterLocation,
    required this.onEdit,
    required this.onDelete,
  });

  final Vehicle vehicle;
  final ParkingRecord? currentLocation;
  final bool isRegisteringLocation;
  final bool canManage;
  final VoidCallback onRegisterLocation;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final currentLocation = this.currentLocation;
    final locationText = isRegisteringLocation
        ? '위치 등록 중...'
        : currentLocation?.locationText ?? '아직 등록된 위치가 없습니다.';
    final locationColor = isRegisteringLocation
        ? CupertinoColors.systemOrange
        : currentLocation == null
        ? const Color(0xFF8E8E93)
        : const Color(0xFF111111);

    return Container(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E5EA))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF111111),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      vehicle.plateNumber,
                      style: const TextStyle(
                        color: Color(0xFF6E6E73),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              if (canManage)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(38, 38),
                  onPressed: isRegisteringLocation ? null : onEdit,
                  child: const Icon(CupertinoIcons.pencil, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '현재 위치',
                  style: TextStyle(
                    color: Color(0xFF6E6E73),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (isRegisteringLocation) ...[
                      const Icon(
                        CupertinoIcons.hourglass,
                        color: CupertinoColors.systemOrange,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        locationText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: locationColor,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (canManage) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: CupertinoButton.filled(
                      borderRadius: BorderRadius.circular(12),
                      onPressed: isRegisteringLocation
                          ? null
                          : onRegisterLocation,
                      child: Text(
                        isRegisteringLocation ? '등록 중' : '위치 등록',
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  color: const Color(0xFFFFE8E8),
                  borderRadius: BorderRadius.circular(12),
                  onPressed: isRegisteringLocation ? null : onDelete,
                  child: const Icon(
                    CupertinoIcons.trash,
                    color: CupertinoColors.destructiveRed,
                    size: 20,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  final ParkingLocationPreset preset;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.location_solid,
            color: CupertinoColors.systemOrange,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              preset.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF111111),
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          if (canManage) ...[
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(38, 38),
              onPressed: onEdit,
              child: const Icon(CupertinoIcons.pencil, size: 19),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(38, 38),
              onPressed: onDelete,
              child: const Icon(
                CupertinoIcons.minus_circle,
                color: CupertinoColors.destructiveRed,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LocationPickerSheet extends StatefulWidget {
  const _LocationPickerSheet({required this.presets, this.currentLocation});

  final List<ParkingLocationPreset> presets;
  final ParkingRecord? currentLocation;

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  _ParkingLocationChoice? _floor;
  _ParkingLocationChoice? _spot;

  @override
  void initState() {
    super.initState();

    final currentLocation = widget.currentLocation;
    if (currentLocation == null) {
      return;
    }

    _floor = _choiceFromCurrentLocation(
      presetType: _parkingPresetTypeFloor,
      presetId: currentLocation.floorPresetId,
      text: currentLocation.floorText,
    );
    _spot = _choiceFromCurrentLocation(
      presetType: _parkingPresetTypeSpot,
      presetId: currentLocation.spotPresetId,
      text: currentLocation.spotText,
    );
  }

  List<_ParkingLocationChoice> _choicesFor(String presetType) {
    final presets = widget.presets
        .where((preset) => preset.presetType == presetType)
        .map(
          (preset) =>
              _ParkingLocationChoice(presetId: preset.id, text: preset.name),
        )
        .toList();
    final defaults = presetType == _parkingPresetTypeFloor
        ? _defaultFloorChoices
        : _defaultSpotChoices;
    final presetNames = presets.map((choice) => choice.text).toSet();

    return [
      ...presets,
      for (final value in defaults)
        if (!presetNames.contains(value)) _ParkingLocationChoice(text: value),
    ];
  }

  _ParkingLocationChoice? _choiceFromCurrentLocation({
    required String presetType,
    required String? presetId,
    required String text,
  }) {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      return null;
    }

    final choices = _choicesFor(presetType);
    for (final choice in choices) {
      if (presetId != null && choice.presetId == presetId) {
        return choice;
      }
    }

    for (final choice in choices) {
      if (choice.text == normalizedText) {
        return choice;
      }
    }

    return _ParkingLocationChoice(text: normalizedText);
  }

  Future<void> _openDirectInput({required bool isFloor}) async {
    final title = isFloor ? '층 직접 입력' : '위치 직접 입력';
    final value = await showCupertinoDialog<String>(
      context: context,
      builder: (_) => _TextInputDialog(
        title: title,
        placeholder: isFloor ? '예: B5' : '예: 105동',
        maxLength: 40,
      ),
    );

    if (value == null || !mounted) {
      return;
    }

    setState(() {
      final choice = _ParkingLocationChoice(text: value);

      if (isFloor) {
        _floor = choice;
      } else {
        _spot = choice;
      }
    });
  }

  void _submit() {
    final floor = _floor;
    final spot = _spot;

    if (floor == null || spot == null) {
      return;
    }

    Navigator.of(context).pop(
      _ParkingLocationInput(
        floorPresetId: floor.presetId,
        spotPresetId: spot.presetId,
        floorText: floor.text,
        spotText: spot.text,
      ),
    );
  }

  Widget _buildChoiceSection({
    required String title,
    required String presetType,
    required _ParkingLocationChoice? selected,
    required ValueChanged<_ParkingLocationChoice> onSelected,
  }) {
    final choices = _choicesFor(presetType);
    final isFloor = presetType == _parkingPresetTypeFloor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF111111),
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final choice in choices)
              _LocationChoiceButton(
                label: choice.text,
                isSelected:
                    selected?.presetId == choice.presetId &&
                    selected?.text == choice.text,
                onPressed: () => onSelected(choice),
              ),
            _LocationChoiceButton(
              label: '직접 입력',
              isSelected:
                  selected?.presetId == null &&
                  selected != null &&
                  !choices.any((choice) => choice.text == selected.text),
              onPressed: () => _openDirectInput(isFloor: isFloor),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _floor != null && _spot != null;

    return SafeArea(
      top: false,
      child: CupertinoPopupSurface(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          color: CupertinoColors.systemBackground.resolveFrom(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '주차 위치 등록',
                      style: TextStyle(
                        color: Color(0xFF111111),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(34, 34),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Icon(CupertinoIcons.xmark_circle_fill),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildChoiceSection(
                title: '층',
                presetType: _parkingPresetTypeFloor,
                selected: _floor,
                onSelected: (choice) => setState(() => _floor = choice),
              ),
              const SizedBox(height: 18),
              _buildChoiceSection(
                title: '위치',
                presetType: _parkingPresetTypeSpot,
                selected: _spot,
                onSelected: (choice) => setState(() => _spot = choice),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: CupertinoButton.filled(
                  borderRadius: BorderRadius.circular(12),
                  onPressed: canSubmit ? _submit : null,
                  child: const Text(
                    '등록',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
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

class _LocationChoiceButton extends StatelessWidget {
  const _LocationChoiceButton({
    required this.label,
    required this.isSelected,
    required this.onPressed,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      minimumSize: Size.zero,
      color: isSelected ? CupertinoColors.activeBlue : const Color(0xFFF2F2F7),
      borderRadius: BorderRadius.circular(999),
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? CupertinoColors.white : const Color(0xFF111111),
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _VehicleDialog extends StatefulWidget {
  const _VehicleDialog({this.vehicle});

  final Vehicle? vehicle;

  @override
  State<_VehicleDialog> createState() => _VehicleDialogState();
}

class _VehicleDialogState extends State<_VehicleDialog> {
  late final TextEditingController _nicknameController;
  late final TextEditingController _plateNumberController;
  String? _message;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.vehicle?.nickname);
    _plateNumberController = TextEditingController(
      text: widget.vehicle?.plateNumber,
    );
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _plateNumberController.dispose();
    super.dispose();
  }

  void _submit() {
    final nickname = _nicknameController.text.trim();
    final plateNumber = _plateNumberController.text.trim();

    if (nickname.isEmpty || plateNumber.isEmpty) {
      setState(() {
        _message = '차량 닉네임과 차량번호를 모두 입력해 주세요.';
      });
      return;
    }

    Navigator.of(
      context,
    ).pop(_VehicleInput(nickname: nickname, plateNumber: plateNumber));
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Text(widget.vehicle == null ? '차량 등록' : '차량 수정'),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            CupertinoTextField(
              controller: _nicknameController,
              autofocus: true,
              placeholder: '차량 닉네임',
              maxLength: 30,
            ),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: _plateNumberController,
              placeholder: '차량번호',
              maxLength: 30,
              onSubmitted: (_) => _submit(),
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(
                _message!,
                style: const TextStyle(
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
          child: const Text('취소'),
        ),
        CupertinoDialogAction(onPressed: _submit, child: const Text('저장')),
      ],
    );
  }
}

class _PresetDialog extends StatelessWidget {
  const _PresetDialog({this.preset});

  final ParkingLocationPreset? preset;

  @override
  Widget build(BuildContext context) {
    return _TextInputDialog(
      title: preset == null ? '즐겨찾기 추가' : '즐겨찾기 수정',
      placeholder: '예: 지하1층',
      initialValue: preset?.name,
      maxLength: 40,
    );
  }
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.placeholder,
    required this.maxLength,
    this.initialValue,
  });

  final String title;
  final String placeholder;
  final int maxLength;
  final String? initialValue;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller;
  String? _message;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();

    if (value.isEmpty) {
      setState(() {
        _message = '값을 입력해 주세요.';
      });
      return;
    }

    Navigator.of(context).pop(value);
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
              placeholder: widget.placeholder,
              maxLength: widget.maxLength,
              onSubmitted: (_) => _submit(),
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(
                _message!,
                style: const TextStyle(
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
          child: const Text('취소'),
        ),
        CupertinoDialogAction(onPressed: _submit, child: const Text('저장')),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Column(
        children: [
          const Icon(
            CupertinoIcons.car_detailed,
            color: CupertinoColors.systemGrey,
            size: 34,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF111111),
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF6E6E73),
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
          if (onPressed != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 46,
              child: CupertinoButton.filled(
                borderRadius: BorderRadius.circular(12),
                onPressed: onPressed,
                child: Text(
                  actionLabel,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          ],
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          message,
          style: const TextStyle(
            color: Color(0xFFB42318),
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

class _VehicleInput {
  const _VehicleInput({required this.nickname, required this.plateNumber});

  final String nickname;
  final String plateNumber;
}

class _ParkingLocationInput {
  const _ParkingLocationInput({
    this.floorPresetId,
    this.spotPresetId,
    required this.floorText,
    required this.spotText,
  });

  final String? floorPresetId;
  final String? spotPresetId;
  final String floorText;
  final String spotText;
}

class _ParkingLocationChoice {
  const _ParkingLocationChoice({this.presetId, required this.text});

  final String? presetId;
  final String text;
}
