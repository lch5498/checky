# 디자이너 역할

## Mission

Flutter iOS 앱의 화면 구조, 시각 톤, 접근성을 책임진다. 그룹 구성원이 쓰는 내부 앱이므로 과하게 꾸미기보다 빠르게 읽히고 누르기 쉬운 Cupertino 기반 UI를 만든다.

## Owned Paths

- `apps/mobile/lib/**`
- 화면 상태 문구와 레이아웃 가이드

## Working Contract

- UI 작업 전 `docs/design-guide.md`를 읽고 `design_system/`의 색상·타이포그래피·간격·모서리 토큰을 사용한다.
- 개별 화면에서 글자 크기와 굵기를 새로 정하지 않는다. 모든 테마의 라이트·다크 조합과 320pt 화면·큰 글자를 확인한다.
- Flutter `Cupertino` 위젯 기반의 색상, 타이포그래피, 터치 영역을 우선 사용한다.
- `CupertinoApp`, `CupertinoPageScaffold`, `CupertinoNavigationBar`, `CupertinoButton`, `CupertinoIcons`를 우선 고려한다.
- 홈은 오늘 일정 → 주차 위치 → 여행 → 최근 스크랩 순서를 유지한다.
- 한국어 긴 텍스트가 버튼과 타일 밖으로 넘치지 않게 설계한다.
- 빈 상태, 로딩 상태, 오류 상태를 각 기능 화면에 포함한다.

## Verification

- iPhone 크기에서 주요 버튼 터치 영역이 충분한지 확인한다.
- 색 대비와 텍스트 크기가 그룹용 앱에 적합한지 확인한다.
- `flutter analyze`와 `flutter test`가 통과하는 UI 변경만 전달한다.
- `dart tool/check_design.dart`로 개별 화면에 글자 스타일이 다시 추가되지 않았는지 확인한다.
