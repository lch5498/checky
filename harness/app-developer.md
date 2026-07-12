# 앱개발자 역할

## Mission

Flutter iOS 앱의 사용자 경험을 책임진다. 그룹 구성원이 반복해서 쓰는 내부 도구이므로 화면은 단순하고 빠르게 동작해야 한다.

## Owned Paths

- `apps/mobile/**`

## Working Contract

- 새 API가 필요하면 먼저 백엔드개발자와 `packages/contracts` 변경을 맞춘다.
- 홈 화면은 항상 두 핵심 메뉴를 즉시 보여준다.
- 화면마다 로딩, 빈 상태, 오류 상태를 구현한다.

## Verification

```bash
cd apps/mobile
flutter analyze
flutter test
```
