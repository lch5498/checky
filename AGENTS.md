# AGENTS.md

이 문서는 House Keeping 모노레포에서 작업하는 사람과 AI agent를 위한 공통 작업 지침이다. 기존 구현을 존중하고, 작은 단위로 변경하며, 인증과 iOS 앱 경험을 먼저 안정화한다.

## 프로젝트 목표

가족만 사용하는 iOS 우선 housekeeping 앱을 만든다. 현재 우선순위는 카카오 로그인, 자체 사용자/session 구조, 이후 학원 일정 관리와 주차 관리 기능이다.

## 저장소 구조

```text
apps/
  api/       Next.js App Router API 서버
  mobile/    Flutter iOS 앱
packages/
  contracts/ 공유 TypeScript schema
supabase/
  migrations/ Supabase migration
docs/
  product-plan.md
  harness-engineering.md
harness/
  planner.md
  designer.md
  app-developer.md
  backend-developer.md
```

## 역할

### 기획자

- `docs/product-plan.md`와 기능 수용 기준을 관리한다.
- 가족용 MVP 범위를 작게 유지한다.
- 기능을 추가할 때 사용자 시나리오, 필수 입력값, 완료 기준을 먼저 정리한다.

### 디자이너

- 앱 화면 구조, 상태별 UX, 접근성을 책임진다.
- iOS 앱은 Flutter `Cupertino` 위젯 중심으로 설계한다.
- 터치 영역, 텍스트 대비, 긴 한국어 문구, 빈 상태와 오류 상태를 확인한다.

### 앱개발자

- `apps/mobile/**`를 주로 수정한다.
- iOS 우선 Flutter 앱을 구현한다.
- API client, 인증 흐름, secure storage, 화면 상태를 책임진다.
- 변경 후 `flutter analyze`와 `flutter test`를 실행한다.

### 백엔드개발자

- `apps/api/**`, `packages/contracts/**`, `supabase/**`를 주로 수정한다.
- Next.js Route Handler, Supabase migration, 환경변수, 인증 API를 책임진다.
- 변경 후 `npm run typecheck`와 필요 시 `npm --workspace apps/api run build`를 실행한다.

## Flutter 앱 지침

### Cupertino 우선

- 앱 전반은 Flutter `Cupertino` 위젯을 우선 사용한다.
- 앱 루트는 `CupertinoApp`을 사용한다.
- 화면은 `CupertinoPageScaffold`를 사용한다.
- 상단 바는 `CupertinoNavigationBar`를 사용한다.
- 버튼은 `CupertinoButton`을 우선 사용한다.
- 화면 전환은 `CupertinoPageRoute`를 사용한다.
- 아이콘은 가능한 `CupertinoIcons`를 사용한다.
- 로딩은 `CupertinoActivityIndicator`를 사용한다.

Material 위젯은 대체가 어렵거나 명확한 이유가 있을 때만 사용한다. Material 위젯을 새로 도입할 때는 왜 필요한지 코드 주변 맥락으로 설명 가능해야 한다.

### 디자인 톤

- iOS 기본 앱처럼 조용하고 넉넉한 여백을 둔다.
- 과한 카드 중첩, 장식용 그래디언트, 불필요한 설명 문구를 피한다.
- 핵심 액션은 한 화면에서 명확히 보이게 한다.
- 로그인 화면은 `카카오로 계속하기` 단일 CTA를 유지한다.
- 홈 화면은 `학원 일정 관리`, `주차 관리` 두 메뉴가 즉시 보이게 한다.
- 카드 radius는 과하게 둥글게 만들지 말고, 현재 iOS 톤과 맞는 범위에서 유지한다.

### 인증 흐름

Flutter 앱은 카카오 Flutter SDK로 로그인한다.

```text
Flutter Kakao SDK
→ Kakao access token 획득
→ POST /api/mobile/auth/kakao
→ Next.js 서버가 Kakao user/me 검증
→ users/authentications upsert
→ 자체 session token 반환
```

Flutter 앱에는 Supabase secret key를 절대 넣지 않는다. 앱은 Next.js API만 호출한다.

### iOS 카카오 설정

- `--dart-define=KAKAO_NATIVE_APP_KEY=...`는 Dart 런타임에서 `KakaoSdk.init(...)`에 쓰이는 값이다.
- iOS 카카오 앱 복귀 URL Scheme은 `ios/Runner/Info.plist`의 `kakao$(KAKAO_NATIVE_APP_KEY)`가 사용한다.
- `Info.plist` 치환 값은 Dart `--dart-define`으로 채워지지 않는다. 각 빌드 설정의 xcconfig에 따로 있어야 한다.
- `ios/Flutter/Debug.xcconfig`, `ios/Flutter/Profile.xcconfig`, `ios/Flutter/Release.xcconfig`의 `KAKAO_NATIVE_APP_KEY` 값을 모두 맞춘다.
- 디버그에서 카카오 로그인이 되는데 릴리즈에서 카카오톡이 앱으로 돌아오지 않으면, 먼저 `Release.xcconfig`의 `KAKAO_NATIVE_APP_KEY`와 최종 URL Scheme이 `kakao<Native App Key>` 형태인지 확인한다.
- 카카오 개발자 콘솔 iOS 플랫폼의 Bundle ID는 Xcode `PRODUCT_BUNDLE_IDENTIFIER`와 일치해야 한다.

### 로컬 실행

iOS Simulator에서는 기본 API 주소로 `http://localhost:3000`을 사용한다.

```bash
cd apps/mobile
flutter run -d "iPhone 17 Pro" \
  --dart-define=KAKAO_NATIVE_APP_KEY=<kakao-native-app-key>
```

Next.js가 다른 포트로 뜨면 `API_BASE_URL`을 지정한다.

```bash
flutter run -d "iPhone 17 Pro" \
  --dart-define=KAKAO_NATIVE_APP_KEY=<kakao-native-app-key> \
  --dart-define=API_BASE_URL=http://localhost:3001
```

## Next.js API 지침

- API 서버는 `apps/api`의 Next.js App Router를 사용한다.
- API는 `app/api/**/route.ts`에 Route Handler로 구현한다.
- Pages Router API나 Express/Fastify 같은 별도 서버 프레임워크를 도입하지 않는다.
- 서버 전용 secret은 Next.js 서버 환경변수에서만 사용한다.
- Flutter 앱에서 필요한 인증 API는 `/api/mobile/**` 아래에 둔다.

현재 주요 인증 API:

```text
POST /api/mobile/auth/kakao
GET  /api/mobile/auth/me
POST /api/mobile/auth/logout
```

## Supabase 지침

- Supabase migration은 `supabase/migrations`에 SQL 파일로 남긴다.
- 현재는 로그인용 `users`, `authentications` schema만 유지한다.
- 가족 구성원, 학원 일정, 주차 관련 schema는 나중에 설계한다.
- `users`는 우리 서비스의 사용자 테이블이다.
- `authentications`는 Kakao, Google 등 OAuth provider 연결을 위한 1:N 테이블이다.
- RLS는 켠다. 서버는 secret key로 접근하고, 앱은 DB에 직접 접근하지 않는다.

환경변수는 새 Supabase API key 체계를 사용한다.

```bash
SUPABASE_URL=
SUPABASE_SECRET_KEY=
SUPABASE_PUBLISHABLE_KEY=
```

`SUPABASE_SECRET_KEY`는 서버 전용이다. Flutter 앱에 넣지 않는다.

## 환경변수

루트 `.env.local`에는 로컬 API 서버 실행에 필요한 값을 둔다.

```bash
SUPABASE_URL=
SUPABASE_SECRET_KEY=
SUPABASE_PUBLISHABLE_KEY=
KAKAO_REST_API_KEY=
KAKAO_CLIENT_SECRET=
KAKAO_REDIRECT_URI=http://localhost:3000/api/auth/kakao/callback
SESSION_SECRET=
```

secret 값은 커밋하지 않는다.

## 검증

백엔드 변경 후:

```bash
npm run typecheck
npm --workspace apps/api run build
```

Flutter 변경 후:

```bash
cd apps/mobile
flutter analyze
flutter test
```

전체적으로 중요한 변경 후:

```bash
npm run typecheck
npm run mobile:analyze
npm run mobile:test
```

## 작업 원칙

- 기존 사용자 변경을 되돌리지 않는다.
- 큰 리팩터링보다 작은 기능 단위 변경을 선호한다.
- 기능 schema, API, 앱 화면은 같은 계약을 기준으로 맞춘다.
- 불필요한 패키지 도입을 피한다.
- 생성 산출물은 커밋 대상에서 제외한다.
- `.env.local`, `.next`, `build`, `.dart_tool`, `node_modules`, `*.tsbuildinfo`는 커밋하지 않는다.
