# Harness Engineering

이 프로젝트에서는 작업을 `기획자`, `디자이너`, `앱개발자`, `백엔드개발자` 역할로 나눠 진행한다. 역할은 사람 또는 AI agent가 맡을 수 있지만, 모든 변경은 같은 계약과 검증 루프를 통과해야 한다.

## 공통 원칙

- 작은 PR 단위로 진행한다.
- 기획자는 기능 범위와 우선순위를 먼저 정리한다.
- 디자이너는 화면 상태, 접근성, 정보 밀도를 먼저 검토한다.
- API request/response는 `packages/contracts`의 schema를 먼저 갱신한다.
- Flutter 앱에는 서버 secret을 넣지 않는다.
- DB migration, API, 앱 화면은 한 기능 단위로 함께 검증한다.

## 기획자

- 소유 영역: `docs/product-plan.md`, 기능 요구사항, 수용 기준
- 책임:
  - 그룹용 MVP 범위를 작게 유지
  - 반복 일정/주차 관리의 우선순위 결정
  - 사용자 시나리오와 완료 기준 작성
  - 다음 개발 단위가 앱/백엔드에 명확히 전달되도록 정리

## 디자이너

- 소유 영역: 화면 구조, UI 상태, 접근성 기준
- 책임:
  - Flutter Cupertino 위젯 중심의 iOS 화면 톤 유지
  - 홈 화면의 두 핵심 메뉴가 즉시 보이도록 정보 구조 정리
  - 빈 상태, 오류 상태, 로딩 상태의 문구와 레이아웃 설계
  - 터치 영역, 대비, 긴 한국어 텍스트 대응 확인

## 앱개발자

- 소유 영역: `apps/mobile`
- 책임:
  - iOS 우선 Flutter 화면 구현
  - API client와 상태 관리 추가
  - 접근성, 빈 상태, 로딩, 오류 상태 처리
  - `flutter analyze`, `flutter test` 통과

## 백엔드개발자

- 소유 영역: `apps/api`, `packages/contracts`, `supabase`
- 책임:
  - Supabase schema와 migration 관리
  - Vercel Functions API 구현
  - 환경변수와 secret 관리
  - API payload schema, 오류 형식, 기본 테스트 유지

## 기능 개발 Harness

1. 기획자가 요구사항을 `docs/product-plan.md`의 MVP 범위와 비교한다.
2. 디자이너가 화면 구조와 상태별 UX를 정의한다.
3. 필요한 schema를 `packages/contracts`에 먼저 정의한다.
4. 백엔드는 Supabase migration과 Vercel Function을 구현한다.
5. 앱은 contract를 기준으로 화면과 client를 구현한다.
6. 검증:
   - `npm run typecheck`
   - `npm run mobile:analyze`
   - `npm run mobile:test`
7. 실제 Supabase/Vercel 연결 후 API에서 DB까지 한 번에 확인한다.

## 완료 기준

- 사용자가 홈에서 기능으로 진입할 수 있다.
- 실패 상태가 앱 화면에 표시된다.
- API는 잘못된 payload에 `400`을 반환한다.
- secret은 `.env.local` 또는 Vercel env에만 존재한다.
