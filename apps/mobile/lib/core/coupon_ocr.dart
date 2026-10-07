import 'dart:async';

import 'package:flutter/services.dart';

class CouponOcrLine {
  const CouponOcrLine(
    this.text, {
    this.top = 0,
    this.left = 0,
    this.height = 0,
  });
  final String text;
  final double top;
  final double left;
  final double height;
}

class CouponSuggestions {
  const CouponSuggestions({this.title, this.expiresOn, this.memo});
  final String? title;
  final DateTime? expiresOn;
  final String? memo;
  bool get isEmpty => title == null && expiresOn == null && memo == null;
}

class CouponOcr {
  static const _channel = MethodChannel('checky/coupon_text');

  Future<CouponSuggestions> recognize(Uint8List bytes) async {
    final result = await _channel
        .invokeListMethod<Object?>('recognize', bytes)
        .timeout(const Duration(seconds: 20));
    final lines = (result ?? []).map((item) {
      final line = item as Map<Object?, Object?>;
      return CouponOcrLine(
        line['text'] as String? ?? '',
        top: (line['top'] as num?)?.toDouble() ?? 0,
        left: (line['left'] as num?)?.toDouble() ?? 0,
        height: (line['height'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
    return parseCouponText(lines);
  }
}

final _expiryLabel = RegExp(
  r'유효\s*기간|사용\s*기한|사용\s*기간|교환\s*기간|만료\s*일|까지|valid\s*(?:until|thru)|exp(?:iry|ires)?\b',
  caseSensitive: false,
);
final _otherDateLabel = RegExp(r'발급\s*일|구매\s*일|주문\s*일|등록\s*일|결제\s*일');
final _memoLabel = RegExp(
  r'사용\s*처|교환\s*처|이용\s*안내|사용\s*안내|유의\s*사항|주의\s*사항|사용\s*조건',
);
final _titleLabel = RegExp(r'^(?:상품\s*명|쿠폰\s*명|제품\s*명)\s*[:：]?\s*');
final _metadata = RegExp(
  r'유효|만료|기한|발급|구매일|주문|쿠폰\s*번호|인증\s*번호|바코드|교환\s*처|사용\s*처|수신|수신자|보낸\s*사람|받는\s*사람|고객\s*센터|전화|환불|사용\s*완료',
);

/// Deterministic suggestions, not a generative model. Ambiguous dates stay blank.
CouponSuggestions parseCouponText(List<CouponOcrLine> input) {
  final lines =
      input
          .map(
            (line) => CouponOcrLine(
              line.text.trim().replaceAll(RegExp(r'[ \t]+'), ' '),
              top: line.top,
              left: line.left,
              height: line.height,
            ),
          )
          .where((line) => line.text.isNotEmpty)
          .toList()
        ..sort((a, b) {
          final byTop = a.top.compareTo(b.top);
          return byTop == 0 ? a.left.compareTo(b.left) : byTop;
        });
  String? title;
  for (var i = 0; i < lines.length; i++) {
    if (!_titleLabel.hasMatch(lines[i].text)) continue;
    final text = lines[i].text.replaceFirst(_titleLabel, '');
    if (_isTitle(text)) {
      title = text;
      break;
    }
    if (text.isEmpty && i + 1 < lines.length && _isTitle(lines[i + 1].text)) {
      title = lines[i + 1].text;
      break;
    }
  }
  if (title == null) {
    final candidates =
        lines.where((line) => line.top < 0.8 && _isTitle(line.text)).toList()
          ..sort((a, b) {
            final size = b.height.compareTo(a.height);
            return size != 0 ? size : a.top.compareTo(b.top);
          });
    if (candidates.isNotEmpty) title = candidates.first.text;
  }

  final expiries = <String, DateTime>{};
  for (var i = 0; i < lines.length; i++) {
    if (!_expiryLabel.hasMatch(lines[i].text)) continue;
    var dates = _dates(lines[i].text);
    if (dates.isNotEmpty &&
        RegExp(r'[~～–-]\s*$').hasMatch(lines[i].text) &&
        i + 1 < lines.length) {
      dates = [...dates, ..._dates(lines[i + 1].text)];
    }
    if (dates.isEmpty) {
      for (var j = i + 1; j < lines.length && j <= i + 2; j++) {
        if (_otherDateLabel.hasMatch(lines[j].text) ||
            _memoLabel.hasMatch(lines[j].text)) {
          break;
        }
        dates = _dates(lines[j].text);
        if (dates.isNotEmpty) break;
      }
    }
    if (dates.isNotEmpty) {
      // A date range's right endpoint is the expiry; never use purchase dates.
      final date = dates.last;
      expiries[date.toIso8601String()] = date;
    }
  }

  final memo = <String>[];
  var collecting = false;
  for (final line in lines) {
    final text = line.text;
    if (_memoLabel.hasMatch(text)) collecting = true;
    if (_expiryLabel.hasMatch(text) ||
        _otherDateLabel.hasMatch(text) ||
        RegExp(r'쿠폰\s*번호|인증\s*번호|바코드|수신|보낸\s*사람|받는\s*사람').hasMatch(text)) {
      collecting = false;
    }
    if (collecting && text != title && !RegExp(r'^[\d\s-]+$').hasMatch(text)) {
      memo.add(text);
    }
  }
  final memoText = memo.join('\n');
  return CouponSuggestions(
    title: title == null ? null : _limit(title, 100),
    expiresOn: expiries.length == 1 ? expiries.values.single : null,
    memo: memoText.isEmpty ? null : _limit(memoText, 1000),
  );
}

bool _isTitle(String text) =>
    text.length >= 2 &&
    text.length <= 100 &&
    RegExp(r'[가-힣A-Za-z]').hasMatch(text) &&
    !_metadata.hasMatch(text) &&
    !_expiryLabel.hasMatch(text) &&
    !_memoLabel.hasMatch(text) &&
    !RegExp(
      r'^(?:쿠폰|쿠폰\s*정보|교환권|선물|선물하기|기프티콘|기프티쇼|모바일\s*쿠폰|사용하기|저장|다운로드|취소|확인|자세히\s*보기)$',
    ).hasMatch(text) &&
    !RegExp(r'https?://|www\.|\d{2,4}[-.]\d{3,4}[-.]\d{4}').hasMatch(text);

List<DateTime> _dates(String text) {
  final matches = RegExp(
    r'(?<!\d)(20\d{2})\s*[.\-/년]\s*(\d{1,2})\s*[.\-/월]\s*(\d{1,2})(?:\s*일)?(?!\d)|(?<!\d)(20\d{2})(\d{2})(\d{2})(?!\d)',
  ).allMatches(text);
  final result = <DateTime>[];
  for (final match in matches) {
    final year = int.parse(match.group(1) ?? match.group(4)!);
    final month = int.parse(match.group(2) ?? match.group(5)!);
    final day = int.parse(match.group(3) ?? match.group(6)!);
    final date = DateTime(year, month, day);
    if (date.year == year && date.month == month && date.day == day) {
      result.add(date);
    }
  }
  return result;
}

String _limit(String text, int limit) {
  if (text.length <= limit) return text;
  var end = limit;
  if (text.codeUnitAt(end - 1) >= 0xD800 &&
      text.codeUnitAt(end - 1) <= 0xDBFF) {
    end--;
  }
  return text.substring(0, end);
}
