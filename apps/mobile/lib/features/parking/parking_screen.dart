import 'package:flutter/cupertino.dart';

import '../../core/api_client.dart';

class ParkingScreen extends StatefulWidget {
  const ParkingScreen({
    super.key,
    required this.family,
    required this.sessionToken,
  });

  final AppFamily family;
  final String sessionToken;

  @override
  State<ParkingScreen> createState() => _ParkingScreenState();
}

class _ParkingScreenState extends State<ParkingScreen> {
  final _apiClient = ApiClient();

  ParkingDashboard? _dashboard;
  String? _message;
  bool _isLoading = true;

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
    _loadParking();
  }

  Future<void> _loadParking() async {
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
          familyId: widget.family.id,
          nickname: input.nickname,
          plateNumber: input.plateNumber,
        );
      } else {
        await _apiClient.updateVehicle(
          widget.sessionToken,
          familyId: widget.family.id,
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
        familyId: widget.family.id,
        vehicleId: vehicle.id,
      );
      await _loadParking();
    });
  }

  Future<void> _openPresetManagement() async {
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => ParkingPresetScreen(
          family: widget.family,
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

    final selected = await showCupertinoModalPopup<_ParkingLocationInput>(
      context: context,
      builder: (_) => _LocationPickerSheet(presets: dashboard.presets),
    );

    if (selected == null) {
      return;
    }

    await _runTask(() async {
      await _apiClient.createParkingRecord(
        widget.sessionToken,
        familyId: widget.family.id,
        vehicleId: vehicle.id,
        presetId: selected.presetId,
        locationText: selected.locationText,
      );
      await _loadParking();
    });
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String actionText,
  }) async {
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
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
    final dashboard = _dashboard;

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      navigationBar: CupertinoNavigationBar(
        middle: const Text('주차 관리'),
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
            _ParkingHeader(
              familyName: widget.family.name,
              canManage: dashboard?.canManage ?? false,
              onManagePresets: _openPresetManagement,
            ),
            if (_message != null) ...[
              const SizedBox(height: 14),
              _InlineMessage(message: _message!),
            ],
            const SizedBox(height: 18),
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
                (vehicle) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _VehicleCard(
                    vehicle: vehicle,
                    currentLocation: _currentLocationsByVehicleId[vehicle.id],
                    canManage: dashboard.canManage,
                    onRegisterLocation: () => _registerParkingLocation(vehicle),
                    onEdit: () => _openVehicleForm(vehicle: vehicle),
                    onDelete: () => _deleteVehicle(vehicle),
                  ),
                ),
              ),
          ],
        ),
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

  Future<void> _openPresetForm({ParkingLocationPreset? preset}) async {
    final name = await showCupertinoDialog<String>(
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
          name: name,
        );
      } else {
        await _apiClient.updateParkingLocationPreset(
          widget.sessionToken,
          familyId: widget.family.id,
          presetId: preset.id,
          name: name,
        );
      }

      await _loadPresets();
    });
  }

  Future<void> _deletePreset(ParkingLocationPreset preset) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('즐겨찾기 삭제'),
        content: Text('${preset.name} 위치를 삭제할까요?'),
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
                onPressed: _isLoading ? null : () => _openPresetForm(),
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
              '예: 지하1층, 지하2층, 101동 앞처럼 자주 쓰는 위치를 등록해 둡니다.',
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
            else if (_presets.isEmpty)
              _EmptyState(
                title: '등록된 즐겨찾기가 없습니다.',
                subtitle: widget.canManage
                    ? '오른쪽 위 + 버튼으로 위치를 추가해 주세요.'
                    : '대표 또는 공동대표가 위치를 등록하면 볼 수 있습니다.',
                actionLabel: '위치 추가',
                onPressed: widget.canManage ? () => _openPresetForm() : null,
              )
            else
              ..._presets.map(
                (preset) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PresetTile(
                    preset: preset,
                    canManage: widget.canManage,
                    onEdit: () => _openPresetForm(preset: preset),
                    onDelete: () => _deletePreset(preset),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ParkingHeader extends StatelessWidget {
  const _ParkingHeader({
    required this.familyName,
    required this.canManage,
    required this.onManagePresets,
  });

  final String familyName;
  final bool canManage;
  final VoidCallback onManagePresets;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$familyName 가족',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF6E6E73),
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '차량과 주차 위치를 관리하세요.',
            style: TextStyle(
              color: Color(0xFF111111),
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.12,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 44,
            child: CupertinoButton(
              color: const Color(0xFFFFF0E5),
              borderRadius: BorderRadius.circular(12),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              onPressed: onManagePresets,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.location_solid,
                    color: CupertinoColors.systemOrange,
                    size: 18,
                  ),
                  SizedBox(width: 6),
                  Text(
                    '주차 위치 즐겨찾기',
                    style: TextStyle(
                      color: CupertinoColors.systemOrange,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!canManage) ...[
            const SizedBox(height: 10),
            const Text(
              '구성원 권한은 조회만 가능합니다.',
              style: TextStyle(
                color: Color(0xFF6E6E73),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
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
    required this.canManage,
    required this.onRegisterLocation,
    required this.onEdit,
    required this.onDelete,
  });

  final Vehicle vehicle;
  final ParkingRecord? currentLocation;
  final bool canManage;
  final VoidCallback onRegisterLocation;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final currentLocation = this.currentLocation;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0E5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  CupertinoIcons.car_detailed,
                  color: CupertinoColors.systemOrange,
                ),
              ),
              const SizedBox(width: 12),
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
                  onPressed: onEdit,
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
                Text(
                  currentLocation?.locationText ?? '아직 등록된 위치가 없습니다.',
                  style: TextStyle(
                    color: currentLocation == null
                        ? const Color(0xFF8E8E93)
                        : const Color(0xFF111111),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
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
                      onPressed: onRegisterLocation,
                      child: const Text(
                        '위치 등록',
                        style: TextStyle(
                          fontSize: 16,
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
                  onPressed: onDelete,
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

class _LocationPickerSheet extends StatelessWidget {
  const _LocationPickerSheet({required this.presets});

  final List<ParkingLocationPreset> presets;

  Future<void> _openDirectInput(BuildContext context) async {
    final locationText = await showCupertinoDialog<String>(
      context: context,
      builder: (_) => const _TextInputDialog(
        title: '직접 입력',
        placeholder: '예: 지하2층 A-12',
        maxLength: 80,
      ),
    );

    if (locationText == null || !context.mounted) {
      return;
    }

    Navigator.of(
      context,
    ).pop(_ParkingLocationInput(locationText: locationText));
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoActionSheet(
      title: const Text('주차 위치 등록'),
      message: const Text('즐겨찾기 위치를 고르거나 직접 입력하세요.'),
      actions: [
        for (final preset in presets)
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(
              _ParkingLocationInput(
                presetId: preset.id,
                locationText: preset.name,
              ),
            ),
            child: Text(preset.name),
          ),
        CupertinoActionSheetAction(
          onPressed: () => _openDirectInput(context),
          child: const Text('직접 입력'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('취소'),
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
                    fontSize: 16,
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
  const _ParkingLocationInput({this.presetId, required this.locationText});

  final String? presetId;
  final String locationText;
}
