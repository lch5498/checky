# 모바일 빌드·스토어 업로드

`scripts/release-mobile.sh` 하나로 iOS·Android를 선택해 빌드하고 업로드한다. 현재 맥의 Xcode 서명, Android upload keystore를 그대로 사용한다. 별도 CI 서버는 필요 없다.

- iOS: IPA → App Store Connect 업로드까지만. Apple 처리 완료를 기다리지 않고 종료한다. App Store 버전 생성·메타데이터 변경·심사 제출·외부 TestFlight 배포는 하지 않는다. 기존 TestFlight 그룹의 자동 배포 설정은 App Store Connect 설정을 따른다.
- Android: AAB → **내부 테스트(`internal`)** 트랙의 `completed` 릴리스. 내부 테스터에게 배포하는 단계이며 프로덕션 출시·트랙 승격·스토어 설명/이미지/릴리스 노트 변경은 하지 않는다. 내부 테스터와 참여 링크는 기존 Play Console 설정을 사용한다. 필요한 Google 심사나 처리 시간은 생략할 수 없다.
- 기본은 두 플랫폼 모두다. 서명·키 파일 존재를 먼저 검사하고, 의존성 설치·디자인 검사·분석·테스트 후 양쪽 빌드가 모두 성공해야 업로드를 시작한다. 인증키 권한·인증서 유효성은 실제 서비스/빌드 응답으로 확인한다.

## 1. 도구 준비 (최초 한 번)

Flutter·Xcode·Android SDK와 기존 서명이 준비된 맥에서:

```bash
brew install fastlane
fastlane --version
```

이미 설치돼 있으면 `brew upgrade fastlane`으로 갱신할 수 있다. Homebrew 패키지의 Ruby를 사용하므로 macOS 기본 Ruby에 `sudo gem install`할 필요는 없다. 스크립트가 도구를 몰래 설치하거나 시스템 설정을 바꾸지는 않는다.

## 2. Apple 인증키

1. App Store Connect → 사용자 및 액세스(Users and Access) → 통합(Integrations) → App Store Connect API → **Team Keys**에서 키를 생성한다. API 접근이 비활성화돼 있으면 계정 소유자가 먼저 요청한다.
2. 업로드 권한이 있는 `Developer` 역할을 선택한다. 이 스크립트는 심사 제출용 App Manager 권한을 요구하지 않는다.
3. **Key ID**, **Issuer ID**를 기록하고 `.p8` 파일을 내려받는다. 이 문서는 Issuer ID가 있는 팀 키 기준이다.
4. 예: `~/.config/checky/AuthKey_XXXXXXXXXX.p8`에 보관한다. 개인 키는 한 번만 내려받을 수 있으므로 안전하게 백업한다.

이 키는 **업로드 인증**이다. 앱·위젯·공유 확장 서명용 인증서와 provisioning profile은 기존 Xcode/키체인 설정이 계속 필요하다. Apple 계약 갱신, 만료된 배포 인증서, App Group 프로비저닝 문제는 별도로 해결해야 한다.

## 3. Google Play 인증키

1. Google Cloud 프로젝트에서 **Google Play Android Developer API**를 활성화한다. 기존 Firebase 프로젝트를 사용해도 되지만 자동 배포 전용 서비스 계정 생성이 권장된다.
2. IAM 및 관리자 → 서비스 계정에서 배포용 계정을 만든다. Keys → Add key → Create new key → JSON으로 내려받는다. 조직 정책이 키 발급을 막는 경우 관리자의 승인이 필요하다.
3. Google Play Console → 사용자 및 권한에서 그 서비스 계정의 이메일을 초대한다.
4. 접근 앱을 **체키(`com.family.checky.mobile`)**로 제한하고 앱 정보 조회 및 **테스트 트랙으로 앱 출시(Release apps to testing tracks)** 권한을 부여한다. 프로덕션 출시·금융·주문 관리·전체 관리자 권한은 부여하지 않는다. 테스터 목록은 사람이 기존 Console에서 관리한다.
5. JSON은 예: `~/.config/checky/google-play-service-account.json`에 보관한다. Cloud IAM 권한만 부여하는 것으로는 충분하지 않고 **Play Console 초대/앱 권한**이 필요하다.

기존에 한 번 이상 Play Console로 업로드한 앱이 대상이다. Android `apps/mobile/android/key.properties`와 upload keystore는 그대로 유지한다.

## 4. 인증 정보 로드

저장소 루트에서 예제를 저장소 **밖으로** 복사하고 실제 값과 파일 경로를 입력한다.

```bash
mkdir -p "$HOME/.config/checky"
cp scripts/release.env.example "$HOME/.config/checky/release.env"
chmod 600 "$HOME/.config/checky/release.env"
vi "$HOME/.config/checky/release.env"
```

```bash
ASC_KEY_ID=실제_Key_ID
ASC_ISSUER_ID=실제_Issuer_ID
ASC_KEY_FILE="$HOME/.config/checky/AuthKey_실제KeyID.p8"
GOOGLE_PLAY_JSON_KEY="$HOME/.config/checky/google-play-service-account.json"
```

키 파일도 `chmod 600`으로 제한한다. 실행할 터미널에서 로드한다. 예제 파일 그대로는 인증되지 않는다.

```bash
set -a
source "$HOME/.config/checky/release.env"
set +a
```

한쪽만 업로드하면 해당 플랫폼 키만 필요하다. 키 내용은 채팅·Git·Dart define에 넣지 않는다. 스크립트는 설정 파일을 임의로 찾아 실행하지 않는다. 신뢰하는 파일만 직접 `source`한다.

## 5. 실행

두 플랫폼 빌드 + 업로드:

```bash
cd /Users/changhwanlee/Documents/project/checky
./scripts/release-mobile.sh --platform all --clean --build-name 1.7.0 --build-number 70
```

`70`은 예시다. **양쪽 스토어에 아직 사용하지 않은 번호**로 바꾼다. 플랫폼별로 실행하려면:

```bash
./scripts/release-mobile.sh --platform ios --build-name 1.7.0 --build-number 70
./scripts/release-mobile.sh --platform android --build-name 1.7.0 --build-number 70
```

옵션 없이 실행하면 버전 이름은 `pubspec.yaml`에서 읽고 빌드 번호는 `max(pubspec 번호, 로컬 마지막 예약 번호)+1`로 지정한다. `pubspec.yaml`은 편집하지 않는다. `.release-state/build-number`에 예약 번호를 보관하며 실패해도 번호를 소비한다. `--clean`으로 지워지지 않는다. **스토어의 최신 번호는 조회하지 않으므로**, 다른 맥/수동 업로드가 있었다면 첫 실행에 더 높은 `--build-number`를 지정한다. 같은 버전을 양쪽에 따로 올릴 때는 같은 번호를 명시한다. `--no-increment`는 pubspec 번호를 그대로 쓰는 옵션이다.

기본 API 주소·카카오 Native 키는 기존 Android 스크립트와 같다. 바꾸려면 `--api-base-url`, `--kakao-native-app-key` 또는 `API_BASE_URL`, `KAKAO_NATIVE_APP_KEY` 환경변수를 사용한다. iOS 카카오 복귀 Scheme의 xcconfig 값은 별도이므로 키를 변경했다면 함께 맞춘다.

실행 계획만 확인 (키·fastlane 없이 가능, 빌드/업로드/번호 예약 없음):

```bash
./scripts/release-mobile.sh --platform all --dry-run --build-name 1.7.0 --build-number 70
```

빌드만 하거나 내부 테스트 초안만 만들기:

```bash
./scripts/release-mobile.sh --platform all --build-only --clean
./scripts/release-mobile.sh --platform android --android-status draft
```

`--build-only`는 스토어 키·fastlane을 요구하지 않는다. `--clean`은 선택 사항이다. 검사 생략은 `--no-analyze`, `--no-test`를 사용한다. iOS 서명 export 옵션이 필요하면 `--export-options-plist /절대경로/ExportOptions.plist`를 지정한다.

기존 명령도 그대로 유지된다. **이 진입점은 계속 빌드만 하며 자동 업로드하지 않는다.** 기존처럼 번호 생략 시 pubspec 번호를 그대로 사용하고 테스트는 생략한다.

```bash
./scripts/build-android.sh --clean --build-name 1.6.0 --build-number 41
./scripts/build-android.sh --mode debug --format apk
```

## 6. 업로드만 재시도

일부 플랫폼 업로드 성공 후 다른 쪽이 실패하면 이미 올라간 빌드는 되돌리지 않는다. 터미널 마지막 요약을 보고 **실패한 플랫폼만** 재시도한다. 아래 경로는 실제 만들어진 파일로 바꾼다.

```bash
./scripts/release-mobile.sh --platform ios --upload-only \
  --ipa apps/mobile/build/ios/ipa/Checky.ipa

./scripts/release-mobile.sh --platform android --upload-only \
  --aab apps/mobile/build/app/outputs/bundle/release/app-release.aab
```

`--upload-only`는 버전을 변경/예약하지 않고 명시한 기존 파일을 올린다. `--clean`, `--build-name`, `--build-number`를 함께 사용할 수 없다. 업로드 응답을 받기 전 통신이 끊겼다면 이미 수신됐을 수 있으므로 **Console에서 같은 번호가 있는지 먼저 확인**한다. 빌드 번호는 파일 안에 들어 있어 다시 업로드한다고 바뀌지 않는다.

정상 빌드 모드는 생성 시간이 새롭고 비어 있지 않은 파일만 업로드한다. Flutter가 0으로 종료돼도 IPA export가 실패했거나 옛 파일만 남으면 업로드하지 않는다. IPA 폴더에 파일이 여러 개면 모호하므로 중단한다. 해당 경우 `--clean` 후 다시 빌드하거나 올바른 파일을 명시해 업로드한다.

동시 실행은 `.release-state/lock`으로 막는다. 강제 종료 후 잠금만 남았다면 다른 배포 프로세스가 없는지 먼저 확인한 뒤 `rmdir .release-state/lock`으로 비운다. `build-number` 파일은 삭제하지 않는다.

Google이 변경사항 검토/초기 앱 설정 때문에 커밋을 거부하면 자동으로 정책을 바꾸거나 production으로 재시도하지 않는다. Play Console에서 오류 원인을 처리하고 다시 실행한다. 업로드 성공은 Apple 처리·Google 정책 검토 완료까지 보장하지 않는다.

## 검증

스토어에 접근하지 않는 모의 실행 테스트:

```bash
npm run mobile:release:test
bash -n scripts/release-mobile.sh scripts/build-android.sh
ruby -c scripts/fastlane/Fastfile
```

테스트는 Python 3와 Ruby가 필요하지만 배포 스크립트 자체는 Python을 요구하지 않는다. 실제 IPA/AAB 빌드와 인증키를 사용하는 업로드는 위 최초 설정 완료 후 실행한다.

공식 참고: [fastlane 설치](https://docs.fastlane.tools/getting-started/ios/setup/), [Apple API 키](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/), [iOS 업로드](https://docs.fastlane.tools/actions/pilot/), [Google API 설정](https://developers.google.com/android-publisher/getting_started), [내부 테스트 업로드 옵션](https://docs.fastlane.tools/actions/supply/).
