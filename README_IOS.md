# 파비스 iOS 배포 가이드

이 문서는 iOS 앱 배포를 처음 진행하는 사람 기준으로, Apple Developer Program 가입부터 TestFlight/App Store 제출까지의 흐름을 정리한 가이드입니다.

파비스 앱 기준 주요 값은 아래와 같습니다.

- 앱 이름: `파비스` / `Favis`
- iOS Bundle ID: `com.family.favis.mobile`
- Kakao Native App Key: `b337431d556984d924b2945179a29d9d`
- 배포 API URL: 배포 환경에 맞게 `API_BASE_URL`로 주입

## 전체 흐름

1. Apple Developer Program 가입
2. Xcode에서 개발자 계정과 Team 설정
3. App Store Connect에 앱 레코드 생성
4. Flutter iOS release/archive 빌드
5. App Store Connect에 빌드 업로드
6. TestFlight로 내부/외부 테스트
7. App Store 공개 심사 제출

## 1. Apple Developer Program 가입

Apple Developer Program에 가입해야 App Store Connect, TestFlight, App Store 배포를 사용할 수 있습니다.

공식 가입 페이지:

- https://developer.apple.com/programs/enroll/

개인 개발자라면 보통 `Individual` 가입이 가장 쉽습니다.

개인 가입 시 필요한 것:

- Apple Account
- Apple Account 2단계 인증
- 법적 실명
- 이메일
- 전화번호
- 주소
- 연회비 결제 수단

주의할 점:

- 개인 가입 시 App Store의 판매자 이름에 개인 실명이 표시됩니다.
- 조직으로 가입하면 회사/단체명이 판매자 이름으로 표시되지만, D-U-N-S Number, 조직 웹사이트, 법적 권한 확인 등이 필요합니다.
- Apple Developer Program은 연 단위 유료 멤버십입니다. Apple 안내 기준 99 USD per membership year이며, 지역별 통화로 표시될 수 있습니다.

가입 순서:

1. Apple ID 준비
2. iPhone 또는 Mac에서 Apple ID 2단계 인증 켜기
3. Apple Developer 등록 페이지 접속
4. `Start your enrollment` 선택
5. `Individual` 또는 `Organization` 선택
6. 실명/주소/전화번호 등 정보 입력
7. 계약 동의
8. 결제
9. 승인 대기

## 2. Xcode 계정과 서명 설정

Apple Developer 가입이 승인되면 Xcode에 계정을 연결합니다.

1. Xcode 실행
2. `Xcode > Settings > Accounts`
3. Apple ID 로그인
4. Team이 표시되는지 확인
5. 필요 시 `Manage Certificates`에서 iOS Development / iOS Distribution 인증서 생성

파비스 프로젝트 열기:

```bash
cd /Users/changhwanlee/Documents/project/favis/apps/mobile
open ios/Runner.xcworkspace
```

Xcode 설정:

1. 왼쪽에서 `Runner` 프로젝트 선택
2. `Runner` target 선택
3. `Signing & Capabilities` 탭 선택
4. Team을 본인 Apple Developer Team으로 선택
5. `Automatically manage signing` 체크
6. Bundle Identifier 확인

```text
com.family.favis.mobile
```

## 3. 카카오 디벨로퍼스 설정 확인

iOS release/TestFlight/App Store 빌드에서도 카카오 로그인이 정상 동작하려면 Kakao Developers 설정이 맞아야 합니다.

확인할 값:

- Native App Key: `b337431d556984d924b2945179a29d9d`
- iOS Bundle ID: `com.family.favis.mobile`

카카오 디벨로퍼스에서 확인할 항목:

1. 내 애플리케이션 > 파비스 앱 선택
2. 앱 설정 > 플랫폼 > iOS
3. Bundle ID가 `com.family.favis.mobile`인지 확인
4. 카카오 로그인 활성화 확인

## 4. App Store Connect 앱 생성

공식 안내:

- https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/

앱 레코드는 빌드를 업로드하기 전에 만들어야 합니다.

1. https://appstoreconnect.apple.com 접속
2. `Apps` 선택
3. `+` 버튼 선택
4. `New App` 선택
5. Platform: `iOS`
6. Name: `파비스` 또는 `Favis`
7. Primary Language: `Korean`
8. Bundle ID: `com.family.favis.mobile`
9. SKU 입력

예시 SKU:

```text
favis-ios
```

## 5. Flutter iOS release 빌드

배포 빌드는 로컬 서버가 아니라 운영 API를 바라봐야 합니다.

예시:

```bash
cd /Users/changhwanlee/Documents/project/favis/apps/mobile

flutter build ipa --release \
  --dart-define=KAKAO_NATIVE_APP_KEY=b337431d556984d924b2945179a29d9d \
  --dart-define=API_BASE_URL=https://house-keeping-api.vercel.app
```

현재 실제 운영 API 도메인이 다르면 `API_BASE_URL`을 운영 도메인으로 바꿔야 합니다.

빌드/서명 문제가 나면 Xcode Archive 방식으로 진행합니다.

1. `open ios/Runner.xcworkspace`
2. 상단 기기 선택을 `Any iOS Device (arm64)`로 변경
3. `Product > Archive`
4. Archive 완료 후 Organizer에서 `Distribute App`
5. `App Store Connect`
6. `Upload`

## 6. TestFlight 테스트

공식 안내:

- https://developer.apple.com/testflight/

TestFlight는 App Store 공개 전에 가족/내부 테스터가 앱을 설치해볼 수 있는 베타 배포 기능입니다.

기본 흐름:

1. App Store Connect > 파비스 앱 선택
2. `TestFlight` 탭 선택
3. 업로드된 빌드 처리 완료 대기
4. 테스트 정보 입력
5. 내부 테스터 추가
6. iPhone에 TestFlight 앱 설치
7. 초대 수락
8. 파비스 설치

내부 테스트:

- 개발자 계정 팀 멤버를 내부 테스터로 추가할 수 있습니다.
- 빠르게 내 폰에서 설치 확인하기에 좋습니다.

외부 테스트:

- 가족처럼 팀 멤버가 아닌 사람에게 배포하려면 외부 테스터 그룹을 사용합니다.
- 외부 테스트는 첫 빌드가 TestFlight App Review를 통과해야 합니다.

## 7. App Store 공개 심사 전 준비물

App Store 공개 배포를 하려면 앱 메타데이터와 심사용 정보가 필요합니다.

준비할 것:

- 앱 이름
- 부제목
- 설명
- 키워드
- 카테고리
- 지원 URL
- 개인정보처리방침 URL
- 앱 아이콘
- 스크린샷
- 연령 등급
- 앱 개인정보 라벨
- 암호화 사용 여부
- 심사용 계정 또는 데모 모드
- 심사 메모

Apple 심사 전 체크:

- 앱이 크래시 없이 동작해야 합니다.
- 백엔드 서버가 켜져 있어야 합니다.
- 로그인 기반 앱이면 심사자가 앱 기능을 볼 수 있어야 합니다.
- 계정 기반 기능이 있으면 심사용 계정 또는 완전한 데모 모드를 제공해야 합니다.

공식 가이드:

- https://developer.apple.com/app-store/review/guidelines/

파비스 심사용 계정 예시:

```text
심사용 계정:
로그인 방식: Apple 로그인 또는 카카오 로그인
테스트 가족명: 리뷰용 가족
테스트 구성원: 부모, 아이
테스트 차량: 리뷰용 차량
테스트 일정: 학원 일정 1~2개
테스트 주차 위치: 건물/층/상세위치 preset 포함
```

## 8. 카카오 로그인만 있을 때의 심사 리스크

현재 파비스는 카카오 로그인 기반입니다.

Apple App Review Guideline 4.8에 따르면 앱이 제3자/소셜 로그인으로 사용자의 기본 계정을 만들거나 인증하는 경우, 동등한 대체 로그인 옵션을 제공해야 합니다.

공식 가이드:

- https://developer.apple.com/app-store/review/guidelines/

따라서 공개 App Store 제출 전에는 `Sign in with Apple`을 추가하는 것을 권장합니다.

선택지는 두 가지입니다.

1. TestFlight까지만 먼저 올려서 내부 테스트
2. App Store 공개 제출 전 Sign in with Apple 추가

권장 방향:

- TestFlight 내부 테스트는 지금 구조로 먼저 진행
- 공개 심사 전에 Sign in with Apple 추가

## 9. 파비스 배포 전 체크리스트

### 계정/서명

- [ ] Apple Developer Program 가입 완료
- [ ] Xcode에 Apple ID 로그인
- [ ] Xcode Team 선택 완료
- [ ] `Automatically manage signing` 체크
- [ ] Bundle ID `com.family.favis.mobile` 확인

### 백엔드

- [ ] Vercel 운영 API 배포 완료
- [ ] Supabase 운영 DB 스키마 적용
- [ ] 운영 환경 변수 설정 완료
- [ ] 앱에서 운영 `API_BASE_URL` 사용

### 로그인

- [ ] 카카오 Native App Key 확인
- [ ] 카카오 iOS Bundle ID 확인
- [ ] release/TestFlight에서 카카오 로그인 복귀 확인
- [ ] 공개 심사 전 Sign in with Apple 추가 여부 결정

### App Store Connect

- [ ] 앱 레코드 생성
- [ ] 앱 이름/설명/키워드 입력
- [ ] 지원 URL 준비
- [ ] 개인정보처리방침 URL 준비
- [ ] 스크린샷 준비
- [ ] 앱 개인정보 라벨 입력
- [ ] 심사용 계정 또는 데모 모드 준비

### TestFlight

- [ ] Archive 또는 `flutter build ipa` 완료
- [ ] App Store Connect에 빌드 업로드
- [ ] TestFlight 빌드 처리 완료
- [ ] 내부 테스트 설치 확인
- [ ] 가족/외부 테스터 테스트 확인

## 10. 자주 막히는 포인트

### No valid code signing certificates

Xcode에 Apple Developer 계정이 연결되지 않았거나 Team이 선택되지 않은 상태입니다.

해결:

1. Xcode > Settings > Accounts 로그인
2. Runner target > Signing & Capabilities
3. Team 선택
4. Automatically manage signing 체크

### 카카오톡 로그인 후 앱으로 돌아오지 않음

대부분 아래 중 하나입니다.

- Kakao Native App Key가 잘못됨
- Kakao Developers의 iOS Bundle ID가 앱 Bundle ID와 다름
- release 빌드에 `--dart-define=KAKAO_NATIVE_APP_KEY=...` 누락
- iOS URL Scheme 설정이 앱 키와 맞지 않음

### App Store 심사에서 로그인 문제

심사자가 앱 기능을 볼 수 없으면 리젝될 수 있습니다.

준비:

- 심사용 계정
- 리뷰용 가족/차량/일정 데이터
- 필요한 경우 App Review Notes에 사용 방법 작성

### 카카오 로그인만 있어서 리젝 가능성

소셜 로그인으로 기본 계정을 만들면 Apple 로그인 같은 대체 옵션이 필요할 수 있습니다.

권장:

- 공개 App Store 제출 전 Sign in with Apple 추가

