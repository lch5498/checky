import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/coupon.dart';
import '../../core/group_refresh.dart';
import '../../design_system/app_colors.dart';
import '../../shared/refreshable_scroll_view.dart';

String couponError(Object error) {
  if (error is ApiException) {
    if (error.statusCode == 409) {
      return '다른 구성원이 쿠폰을 변경했어요. 최신 내용을 확인한 뒤 다시 시도해 주세요.';
    }
    if (error.statusCode == 413) return '이미지는 2MB 이하로 선택해 주세요.';
    if (error.errorCode == 'coupon_image_invalid') {
      return 'JPG, PNG, WebP 이미지를 선택해 주세요.';
    }
    if (error.statusCode == 403) return '이 쿠폰에 접근할 권한이 없어요.';
    if (error.statusCode == 404) return '삭제되었거나 찾을 수 없는 쿠폰이에요.';
    if (error.statusCode == 401) return '로그인이 만료되었어요. 다시 로그인해 주세요.';
  }
  return '쿠폰을 처리하지 못했어요. 잠시 후 다시 시도해 주세요.';
}

class CouponContent extends StatefulWidget {
  const CouponContent({
    super.key,
    required this.family,
    required this.sessionToken,
    this.apiClient,
  });
  final AppFamily family;
  final String sessionToken;
  final ApiClient? apiClient;
  @override
  State<CouponContent> createState() => _CouponContentState();
}

class _CouponContentState extends State<CouponContent>
    with GroupRefreshListener<CouponContent>, WidgetsBindingObserver {
  late final _api = widget.apiClient ?? ApiClient();
  List<Coupon> _coupons = [];
  bool _loading = true;
  String? _error;
  CouponFilter _filter = CouponFilter.available;
  CouponSort _sort = CouponSort.expiry;
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
    _recoverImage();
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
      _scheduleMidnight();
    }
  }

  // Android may kill the activity while the system photo picker is open.
  Future<void> _recoverImage() async {
    if (!Platform.isAndroid) return;
    try {
      final lost = await ImagePicker().retrieveLostData();
      if (!mounted || lost.isEmpty) return;
      if (lost.files?.isNotEmpty == true) {
        await Navigator.of(context).push(
          CupertinoPageRoute<void>(
            builder: (_) => CouponEditorScreen(
              family: widget.family,
              sessionToken: widget.sessionToken,
              recoveredImage: lost.files!.first,
            ),
          ),
        );
        if (mounted) await _load();
      } else if (lost.exception != null) {
        setState(() => _error = '사진을 다시 선택해 주세요.');
      }
    } catch (_) {
      /* Recoverable: the user can choose the image again. */
    }
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
      final items = await _api.getCoupons(
        widget.sessionToken,
        widget.family.id,
      );
      if (isCurrentGroupLoad(version)) {
        setState(() {
          _coupons = items;
          _error = null;
        });
      }
    } catch (e) {
      if (isCurrentGroupLoad(version)) setState(() => _error = couponError(e));
    } finally {
      if (isCurrentGroupLoad(version)) setState(() => _loading = false);
    }
  }

  Future<void> _open(Coupon coupon) async {
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => CouponDetailScreen(
          family: widget.family,
          sessionToken: widget.sessionToken,
          coupon: coupon,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final items = visibleCoupons(_coupons, _filter, _sort, now);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final entry in const {
                        CouponFilter.available: '사용 가능',
                        CouponFilter.used: '사용 완료',
                        CouponFilter.expired: '만료',
                        CouponFilter.all: '전체',
                      }.entries)
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          onPressed: () => setState(() => _filter = entry.key),
                          child: Text(
                            entry.value,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _filter == entry.key
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: _filter == entry.key
                                  ? AppColors.darkPrimary
                                  : AppColors.darkTextMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.only(left: 8),
                onPressed: () async {
                  final sort = await showCupertinoModalPopup<CouponSort>(
                    context: context,
                    builder: (c) => CupertinoActionSheet(
                      title: const Text('쿠폰 정렬'),
                      actions: [
                        CupertinoActionSheetAction(
                          onPressed: () => Navigator.pop(c, CouponSort.expiry),
                          child: const Text('만료일순 · 가까운 날짜부터'),
                        ),
                        CupertinoActionSheetAction(
                          onPressed: () => Navigator.pop(c, CouponSort.newest),
                          child: const Text('최신 등록순'),
                        ),
                      ],
                      cancelButton: CupertinoActionSheetAction(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('취소'),
                      ),
                    ),
                  );
                  if (mounted && sort != null) setState(() => _sort = sort);
                },
                child: Text(
                  _sort == CouponSort.expiry ? '만료일순 ▾' : '최신순 ▾',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CupertinoActivityIndicator())
              : RefreshableScrollView(
                  onRefresh: _load,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: TextStyle(color: AppColors.darkDanger),
                      ),
                      CupertinoButton(
                        onPressed: _load,
                        child: const Text('다시 불러오기'),
                      ),
                    ],
                    if (items.isEmpty && _error == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: Column(
                          children: [
                            Icon(
                              CupertinoIcons.gift,
                              size: 36,
                              color: AppColors.darkTextMuted,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              _coupons.isEmpty
                                  ? '함께 쓸 쿠폰을 모아보세요'
                                  : '해당하는 쿠폰이 없어요',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _coupons.isEmpty
                                  ? '위의 + 버튼으로 쿠폰 이미지를 등록해 주세요.'
                                  : '다른 상태의 쿠폰도 확인해 보세요.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.darkTextMuted,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    for (final coupon in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.darkSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.darkBorder),
                          ),
                          child: CupertinoButton(
                            padding: const EdgeInsets.all(16),
                            onPressed: () => _open(coupon),
                            child: Row(
                              children: [
                                Icon(
                                  CupertinoIcons.gift,
                                  color:
                                      coupon.usedAt != null ||
                                          coupon.isExpired(now)
                                      ? AppColors.darkTextMuted
                                      : AppColors.darkPrimary,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        coupon.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.darkTextPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        coupon.expiresOn == null
                                            ? '만료일 없음'
                                            : '${couponDate(coupon.expiresOn!).replaceAll('-', '.')}까지',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: coupon.isExpired(now)
                                              ? AppColors.darkDanger
                                              : AppColors.darkTextSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  coupon.status(now),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.darkTextMuted,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  CupertinoIcons.chevron_right,
                                  size: 14,
                                  color: AppColors.darkTextMuted,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class CouponDetailScreen extends StatefulWidget {
  const CouponDetailScreen({
    super.key,
    required this.family,
    required this.sessionToken,
    required this.coupon,
  });
  final AppFamily family;
  final String sessionToken;
  final Coupon coupon;
  @override
  State<CouponDetailScreen> createState() => _CouponDetailScreenState();
}

class _CouponDetailScreenState extends State<CouponDetailScreen> {
  final _api = ApiClient();
  late Coupon _coupon = widget.coupon;
  bool _busy = false;
  bool _ready = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final coupon = await _api.getCoupon(
        widget.sessionToken,
        widget.family.id,
        _coupon.id,
      );
      if (mounted) {
        setState(() {
          _coupon = coupon;
          _ready = true;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = couponError(e);
          _ready = false;
        });
      }
    }
  }

  Future<void> _change({bool delete = false}) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (c) => CupertinoAlertDialog(
        title: Text(
          delete
              ? '쿠폰을 삭제할까요?'
              : _coupon.usedAt == null
              ? '사용 완료로 표시할까요?'
              : '사용 완료를 취소할까요?',
        ),
        content: Text(delete ? '쿠폰 이미지도 함께 삭제됩니다.' : '그룹 구성원 모두에게 반영됩니다.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('취소'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: delete,
            onPressed: () => Navigator.pop(c, true),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (delete) {
        await _api.deleteCoupon(widget.sessionToken, widget.family.id, _coupon);
        GroupRefresh.notify(widget.family.id);
        if (mounted) Navigator.pop(context);
      } else {
        final updated = await _api.setCouponUsed(
          widget.sessionToken,
          widget.family.id,
          _coupon,
          _coupon.usedAt == null,
        );
        GroupRefresh.notify(widget.family.id);
        if (mounted) setState(() => _coupon = updated);
      }
    } catch (e) {
      if (e is ApiException && e.statusCode == 409) await _reload();
      if (mounted) setState(() => _error = couponError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: AppColors.darkBackground,
    navigationBar: CupertinoNavigationBar(
      middle: const Text('쿠폰'),
      trailing: _coupon.canManage
          ? CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _busy || !_ready
                  ? null
                  : () async {
                      await Navigator.push(
                        context,
                        CupertinoPageRoute<void>(
                          builder: (_) => CouponEditorScreen(
                            family: widget.family,
                            sessionToken: widget.sessionToken,
                            existing: _coupon,
                          ),
                        ),
                      );
                      if (mounted) await _reload();
                    },
              child: const Text('수정'),
            )
          : null,
    ),
    child: SafeArea(
      child: RefreshableScrollView(
        onRefresh: _reload,
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _coupon.title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.family.name} · ${_coupon.status(DateTime.now())}',
            style: TextStyle(color: AppColors.darkPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            _coupon.expiresOn == null
                ? '만료일 없음'
                : '${couponDate(_coupon.expiresOn!).replaceAll('-', '.')}까지',
          ),
          const SizedBox(height: 16),
          if (_ready)
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                CupertinoPageRoute<void>(
                  builder: (_) => CupertinoPageScaffold(
                    backgroundColor: CupertinoColors.white,
                    navigationBar: const CupertinoNavigationBar(
                      middle: Text('쿠폰 이미지'),
                    ),
                    child: SafeArea(
                      child: InteractiveViewer(
                        minScale: 1,
                        maxScale: 5,
                        child: Center(child: _image()),
                      ),
                    ),
                  ),
                ),
              ),
              child: Container(
                color: CupertinoColors.white,
                padding: const EdgeInsets.all(8),
                child: _image(),
              ),
            ),
          if (_ready)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '이미지를 누르면 확대할 수 있어요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ),
          if (_coupon.memo.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(_coupon.memo),
            ),
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: AppColors.darkDanger)),
            CupertinoButton(
              onPressed: _busy ? null : _reload,
              child: const Text('다시 불러오기'),
            ),
          ],
          if (_busy) const Center(child: CupertinoActivityIndicator()),
          const SizedBox(height: 16),
          CupertinoButton.filled(
            onPressed: _busy || !_ready ? null : () => _change(),
            child: Text(_coupon.usedAt == null ? '사용 완료' : '사용 완료 취소'),
          ),
          if (_coupon.canManage)
            CupertinoButton(
              onPressed: _busy || !_ready ? null : () => _change(delete: true),
              child: Text(
                '쿠폰 삭제',
                style: TextStyle(color: AppColors.darkDanger),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _image() => Image.network(
    _api.couponImageUrl(widget.family.id, _coupon.id),
    headers: {'Authorization': 'Bearer ${widget.sessionToken}'},
    fit: BoxFit.contain,
    loadingBuilder: (_, child, loading) => loading == null
        ? child
        : const SizedBox(
            height: 200,
            child: Center(child: CupertinoActivityIndicator()),
          ),
    errorBuilder: (_, error, stack) => SizedBox(
      height: 160,
      child: Center(
        child: Text(
          '이미지를 불러오지 못했어요.',
          style: TextStyle(color: AppColors.lightTextPrimary),
        ),
      ),
    ),
  );
}

class CouponEditorScreen extends StatefulWidget {
  const CouponEditorScreen({
    super.key,
    required this.family,
    required this.sessionToken,
    this.existing,
    this.recoveredImage,
  });
  final AppFamily family;
  final String sessionToken;
  final Coupon? existing;
  final XFile? recoveredImage;
  @override
  State<CouponEditorScreen> createState() => _CouponEditorScreenState();
}

class _CouponEditorScreenState extends State<CouponEditorScreen> {
  final _api = ApiClient(timeout: const Duration(seconds: 30));
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _memo = TextEditingController(text: widget.existing?.memo ?? '');
  late DateTime? _expires = widget.existing?.expiresOn;
  Uint8List? _image;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    if (widget.recoveredImage != null) _readImage(widget.recoveredImage!);
  }

  @override
  void dispose() {
    _title.dispose();
    _memo.dispose();
    super.dispose();
  }

  Future<void> _readImage(XFile file) async {
    try {
      if (await file.length() > 2 * 1024 * 1024) {
        if (mounted) setState(() => _error = '이미지는 2MB 이하로 선택해 주세요.');
        return;
      }
      final bytes = await file.readAsBytes();
      if (mounted) {
        setState(() {
          _image = bytes;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '사진을 읽지 못했어요. 다시 선택해 주세요.');
    }
  }

  Future<void> _pick() async {
    setState(() => _busy = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 95,
        requestFullMetadata: false,
      );
      if (image != null) await _readImage(image);
    } catch (_) {
      if (mounted) setState(() => _error = '사진을 선택하지 못했어요. 사진 접근 권한을 확인해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    var selected = _expires ?? DateTime.now();
    final picked = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (c) => Container(
        height: 330 + MediaQuery.paddingOf(c).bottom,
        color: CupertinoColors.systemBackground.resolveFrom(c),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('취소'),
                  ),
                  CupertinoButton(
                    onPressed: () => Navigator.pop(c, selected),
                    child: const Text('선택'),
                  ),
                ],
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: selected,
                  onDateTimeChanged: (value) => selected = value,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted && picked != null) setState(() => _expires = picked);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty ||
        (widget.existing == null && _image == null)) {
      setState(() => _error = '쿠폰 이름과 이미지를 입력해 주세요.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.saveCoupon(
        widget.sessionToken,
        widget.family.id,
        existing: widget.existing,
        title: _title.text.trim(),
        memo: _memo.text.trim(),
        expiresOn: _expires,
        imageBytes: _image,
      );
      GroupRefresh.notify(widget.family.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = couponError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.existing == null ? '쿠폰 등록' : '쿠폰 수정'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _busy ? null : _save,
          child: const Text('저장'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${widget.family.name}에 공유',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.darkTextSecondary,
              ),
            ),
            const SizedBox(height: 20),
            const Text('쿠폰 이름'),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: _title,
              placeholder: '예: 카페 아메리카노',
              maxLength: 100,
              enabled: !_busy,
              padding: const EdgeInsets.all(14),
            ),
            const SizedBox(height: 16),
            if (widget.existing == null) ...[
              if (_image != null)
                SizedBox(
                  height: 220,
                  child: Image.memory(
                    _image!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, error, stack) =>
                        const Center(child: Text('지원하지 않는 이미지예요. 다시 선택해 주세요.')),
                  ),
                ),
              CupertinoButton(
                onPressed: _busy ? null : _pick,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(CupertinoIcons.photo),
                    const SizedBox(width: 8),
                    Text(_image == null ? '쿠폰 이미지 선택' : '다른 이미지 선택'),
                  ],
                ),
              ),
              Text(
                'QR·바코드가 선명한 JPG, PNG, WebP · 최대 2MB',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.darkTextMuted),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                const Text('만료일'),
                const Spacer(),
                CupertinoButton(
                  onPressed: _busy ? null : _pickDate,
                  child: Text(
                    _expires == null ? '선택 안 함' : couponDate(_expires!),
                  ),
                ),
                if (_expires != null)
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _busy
                        ? null
                        : () => setState(() => _expires = null),
                    child: const Icon(CupertinoIcons.clear_circled, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('메모'),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: _memo,
              placeholder: '사용처나 유의사항 (선택)',
              maxLength: 1000,
              minLines: 3,
              maxLines: 5,
              enabled: !_busy,
              padding: const EdgeInsets.all(14),
            ),
            const SizedBox(height: 20),
            if (_error != null)
              Text(_error!, style: TextStyle(color: AppColors.darkDanger)),
            if (_busy) const Center(child: CupertinoActivityIndicator()),
          ],
        ),
      ),
    ),
  );
}
