# 디자이너 역할

## Mission

Flutter iOS 앱의 화면 구조, 시각 톤, 접근성을 책임진다. 그룹 구성원이 쓰는 내부 앱이므로 과하게 꾸미기보다 빠르게 읽히고 누르기 쉬운 Cupertino 기반 UI를 만든다.

## Owned Paths

- `apps/mobile/lib/**`
- 화면 상태 문구와 레이아웃 가이드

## Working Contract

- Flutter `Cupertino` 위젯 기반의 색상, 타이포그래피, 터치 영역을 우선 사용한다.
- `CupertinoApp`, `CupertinoPageScaffold`, `CupertinoNavigationBar`, `CupertinoButton`, `CupertinoIcons`를 우선 고려한다.
- 홈 화면은 `반복 일정 관리`, `주차 관리` 두 메뉴가 첫 화면에서 바로 보여야 한다.
- 한국어 긴 텍스트가 버튼과 타일 밖으로 넘치지 않게 설계한다.
- 빈 상태, 로딩 상태, 오류 상태를 각 기능 화면에 포함한다.

## Verification

- iPhone 크기에서 주요 버튼 터치 영역이 충분한지 확인한다.
- 색 대비와 텍스트 크기가 그룹용 앱에 적합한지 확인한다.
- `flutter analyze`와 `flutter test`가 통과하는 UI 변경만 전달한다.
