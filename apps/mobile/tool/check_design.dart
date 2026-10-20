import 'dart:io';

/// Run from apps/mobile: dart tool/check_design.dart
void main() {
  final patterns = <RegExp, String>{
    RegExp(r'\b(?:fontSize|fontWeight|letterSpacing)\s*:'):
        'AppTypography 토큰을 사용하세요.',
    RegExp(r'\bTextStyle\s*\('): 'AppTypography 토큰에서 스타일을 가져오세요.',
    RegExp(r'AppColors\.(?:dark|light)[A-Z]'): '밝기에 독립적인 색상 역할을 사용하세요.',
    RegExp(r'\binherit\s*:\s*false'): '선택한 글꼴을 앱 테마에서 상속하세요.',
    RegExp(r'\bfontFamily(?:Fallback)?\s*:'):
        '글꼴은 앱 테마에서 상속하고 미리보기는 AppFontPreset.applyTo를 사용하세요.',
  };
  var violations = 0;
  for (final root in ['lib/features', 'lib/shared']) {
    for (final file in Directory(
      root,
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        for (final entry in patterns.entries) {
          if (entry.key.hasMatch(lines[index])) {
            stderr.writeln('${file.path}:${index + 1}: ${entry.value}');
            violations++;
          }
        }
      }
    }
  }
  if (violations > 0) {
    exitCode = 1;
  } else {
    stdout.writeln('디자인 토큰 검사 통과');
  }
}
