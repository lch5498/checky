import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/coupon.dart';
import '../../core/coupon_ocr.dart';
import '../../core/group_refresh.dart';
import '../../design_system/app_colors.dart';
import '../../shared/refreshable_scroll_view.dart';

String couponError(Object error) {
  if (error is ApiException) {
    if (error.errorCode == 'coupon_limit_reached') {
      return '그룹당 쿠폰 이미지는 최대 100장까지 보관할 수 있어요. 기존 쿠폰을 삭제한 뒤 다시 등록해 주세요.';
    }
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
                                      if (coupon.completionLabel != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          coupon.completionLabel!,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.darkTextSecondary,
                                          ),
                                        ),
                                      ],
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
    this.apiClient,
  });
  final AppFamily family;
  final String sessionToken;
  final Coupon coupon;
  final ApiClient? apiClient;
  @override
  State<CouponDetailScreen> createState() => _CouponDetailScreenState();
}

class _CouponDetailScreenState extends State<CouponDetailScreen> {
  late final _api = widget.apiClient ?? ApiClient();
  late Coupon _coupon = widget.coupon;
  bool _busy = false;
  bool _ready = false;
  bool _loadingDetail = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loadingDetail = true);
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
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
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
          if (_coupon.completionLabel != null) ...[
            const SizedBox(height: 6),
            Text(
              _coupon.completionLabel!,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.darkTextSecondary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            _coupon.expiresOn == null
                ? '만료일 없음'
                : '${couponDate(_coupon.expiresOn!).replaceAll('-', '.')}까지',
          ),
          if (_coupon.couponNumber.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('쿠폰 번호: ${_coupon.couponNumber}'),
          ],
          const SizedBox(height: 16),
          if (!_ready && _loadingDetail) const _CouponImageLoading(),
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
    // A null chunk event can mean we're still waiting for response headers.
    // Wait for the first decoded frame, covering request, transfer and decoding.
    frameBuilder: (_, child, frame, synchronous) =>
        synchronous || frame != null ? child : const _CouponImageLoading(),
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

class _CouponImageLoading extends StatelessWidget {
  const _CouponImageLoading();

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('coupon-image-loading'),
    height: 200,
    width: double.infinity,
    color: CupertinoColors.white,
    child: Semantics(
      label: '쿠폰 이미지 불러오는 중',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CupertinoActivityIndicator(radius: 14, color: AppColors.lightPrimary),
          const SizedBox(height: 12),
          Text(
            '이미지를 불러오고 있어요',
            style: TextStyle(fontSize: 13, color: AppColors.lightTextSecondary),
          ),
        ],
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
    this.ocr,
  });
  final AppFamily family;
  final String sessionToken;
  final Coupon? existing;
  final XFile? recoveredImage;
  final CouponOcr? ocr;
  @override
  State<CouponEditorScreen> createState() => _CouponEditorScreenState();
}

class _CouponEditorScreenState extends State<CouponEditorScreen> {
  final _api = ApiClient(timeout: const Duration(seconds: 30));
  late final _ocr = widget.ocr ?? CouponOcr();
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _couponNumber = TextEditingController(
    text: widget.existing?.couponNumber ?? '',
  );
  late final _memo = TextEditingController(text: widget.existing?.memo ?? '');
  late DateTime? _expires = widget.existing?.expiresOn;
  Uint8List? _image;
  bool _busy = false;
  String? _error;
  bool _analyzing = false;
  int _analysisVersion = 0;
  String? _analysisMessage;
  String? _autoTitle;
  DateTime? _autoExpiry;
  bool _expiryEdited = false;
  @override
  void initState() {
    super.initState();
    if (widget.recoveredImage != null) _readImage(widget.recoveredImage!);
  }

  @override
  void dispose() {
    _title.dispose();
    _couponNumber.dispose();
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
          // Replacing an image clears only untouched suggestions from the old image.
          if (_title.text == _autoTitle) _title.clear();
          if (!_expiryEdited && _expires == _autoExpiry) _expires = null;
          _autoTitle = null;
          _autoExpiry = null;
          _image = bytes;
          _error = null;
        });
        unawaited(_analyze(bytes));
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

  Future<void> _analyze(Uint8List bytes) async {
    final version = ++_analysisVersion;
    setState(() {
      _analyzing = true;
      _analysisMessage = null;
    });
    try {
      final suggestions = await _ocr.recognize(bytes);
      if (!mounted || version != _analysisVersion) return;
      setState(() {
        if (_title.text.trim().isEmpty && suggestions.title != null) {
          _title.text = suggestions.title!;
          _autoTitle = _title.text;
        }
        if (_expires == null &&
            !_expiryEdited &&
            suggestions.expiresOn != null) {
          _expires = suggestions.expiresOn;
          _autoExpiry = _expires;
        }
        _analysisMessage = suggestions.isEmpty
            ? '쿠폰 정보를 찾지 못했어요. 직접 입력해 주세요.'
            : '사진에서 찾은 정보를 채웠어요. 이름과 만료일을 꼭 확인해 주세요.';
      });
    } catch (error) {
      if (!mounted || version != _analysisVersion) return;
      final unsupported =
          error is MissingPluginException ||
          (error is PlatformException && error.code == 'ocr_unsupported');
      setState(
        () => _analysisMessage = unsupported
            ? '이 기기에서는 한국어 자동 입력을 지원하지 않아요. 직접 입력해 주세요.'
            : '사진의 글자를 읽지 못했어요. 직접 입력하거나 다른 사진을 선택해 주세요.',
      );
    } finally {
      if (mounted && version == _analysisVersion) {
        setState(() => _analyzing = false);
      }
    }
  }

  void _stopAnalysis() {
    _analysisVersion++;
    setState(() {
      _analyzing = false;
      _analysisMessage = '쿠폰 정보를 직접 입력해 주세요.';
    });
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
    if (mounted && picked != null) {
      setState(() {
        _expires = picked;
        _expiryEdited = true;
      });
    }
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
        couponNumber: _couponNumber.text.trim(),
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
          onPressed: _busy || _analyzing ? null : _save,
          child: const Text('저장'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              '쿠폰 이미지',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (_image != null || widget.existing != null)
              Container(
                width: double.infinity,
                margin: EdgeInsets.only(
                  bottom: widget.existing == null ? 10 : 0,
                ),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.darkSurface,
                  border: Border.all(color: AppColors.darkBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _image != null
                    ? Image.memory(
                        _image!,
                        width: double.infinity,
                        fit: BoxFit.fitWidth,
                        errorBuilder: (_, error, stack) => const SizedBox(
                          height: 160,
                          child: Center(
                            child: Text('지원하지 않는 이미지예요. 다시 선택해 주세요.'),
                          ),
                        ),
                      )
                    : Image.network(
                        _api.couponImageUrl(
                          widget.family.id,
                          widget.existing!.id,
                        ),
                        key: const ValueKey('coupon-editor-existing-image'),
                        headers: {
                          'Authorization': 'Bearer ${widget.sessionToken}',
                        },
                        width: double.infinity,
                        fit: BoxFit.fitWidth,
                        frameBuilder: (_, child, frame, synchronous) =>
                            synchronous || frame != null
                            ? child
                            : SizedBox(
                                height: 200,
                                child: Center(
                                  child: CupertinoActivityIndicator(
                                    color: AppColors.darkPrimary,
                                  ),
                                ),
                              ),
                        errorBuilder: (_, error, stack) => const SizedBox(
                          height: 160,
                          child: Center(child: Text('이미지를 불러오지 못했어요.')),
                        ),
                      ),
              ),
            if (widget.existing == null) ...[
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _busy ? null : _pick,
                child: Container(
                  width: double.infinity,
                  height: _image == null ? 132 : 48,
                  decoration: BoxDecoration(
                    color: AppColors.darkPrimarySoft,
                    border: Border.all(
                      color: AppColors.darkPrimary.withValues(alpha: 0.65),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _image == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.arrow_up_doc,
                              size: 30,
                              color: AppColors.darkPrimary,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '이미지 업로드',
                              style: TextStyle(
                                color: AppColors.darkPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.photo,
                              size: 19,
                              color: AppColors.darkPrimary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '다른 이미지 선택',
                              style: TextStyle(
                                color: AppColors.darkPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              if (_analyzing)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CupertinoActivityIndicator(),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        '사진에서 쿠폰 정보를 찾고 있어요',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    CupertinoButton(
                      onPressed: _stopAnalysis,
                      child: const Text(
                        '직접 입력',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              if (_analysisMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _analysisMessage!,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.darkTextSecondary,
                    ),
                  ),
                ),
            ],
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
                        : () => setState(() {
                            _expires = null;
                            _expiryEdited = true;
                          }),
                    child: const Icon(CupertinoIcons.clear_circled, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('쿠폰 번호 (선택)'),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: _couponNumber,
              placeholder: '번호가 있는 경우에만 입력',
              maxLength: 128,
              enabled: !_busy,
              padding: const EdgeInsets.all(14),
            ),
            const SizedBox(height: 16),
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
