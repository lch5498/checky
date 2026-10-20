# 앱개발자 역할

## Mission

Flutter iOS 앱의 사용자 경험을 책임진다. 그룹 구성원이 반복해서 쓰는 내부 도구이므로 화면은 단순하고 빠르게 동작해야 한다.

## Owned Paths

- `apps/mobile/**`

## Working Contract

- UI 작업은 `docs/design-guide.md`와 공통 디자인 토큰을 따른다. 새 화면의 `build`에서 현재 팔레트에 의존해 테마 변경을 즉시 반영한다.
- 새 API가 필요하면 먼저 백엔드개발자와 `packages/contracts` 변경을 맞춘다.
- 홈은 오늘 일정 → 주차 위치 → 여행 → 최근 스크랩 순서를 유지한다.
- 화면마다 로딩, 빈 상태, 오류 상태를 구현한다.

## Verification

```bash
cd apps/mobile
dart tool/check_design.dart
flutter analyze
flutter test
```
