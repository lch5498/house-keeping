# 체키 (Checky)

그룹 내 구성원과 공유해서 사용하는 Checky 앱입니다. Flutter 앱은 iOS와 Android에서 하단 탭으로 홈, 일정, 주차, 스크랩, 여행을 구분합니다.

- 홈: 오늘 일정, 현재 주차 위치, 출발 7일 전부터의 여행 체크리스트 완료율, 최근 스크랩 브리핑
- 홈 위젯: Android와 iOS에서 오늘 일정을 캘린더형 목록으로 표시합니다. 2×2/작은 위젯은 최대 2개, 넓은 위젯은 최대 5개를 표시하고 남은 일정 수를 안내합니다.
- 일정: 종일 옵션을 포함한 그룹 구성원별 일정·반복 일정·기념일 관리, 여행 일정 필터 캘린더, 다가오는 공휴일·연휴·징검다리 조회
- 주차: 차량과 주차 위치 관리
- 그룹 활동: 최근 7일간의 일정·주차·스크랩·여행 활동을 유형별로 조회
- 여행: 여행별 일정·장소 링크와 체크리스트 관리(완료자·완료 시각 표시), 기간 축소 시 기간 밖 일정 삭제 확인

백엔드는 Supabase + Next.js API 서버를 Vercel에 배포하는 구조로 구성하고, 앱은 Flutter 기반으로 iOS와 Android를 지원합니다.

## 폴더 구조

```text
apps/
  api/       Next.js App Router 기반 백엔드 API
  mobile/    Flutter iOS/Android 앱
packages/
  contracts/ API 요청/응답 스키마
supabase/
  migrations/ Supabase DB migration
docs/
  product-plan.md
  harness-engineering.md
  supabase-cron.md
harness/
  app-developer.md
  backend-developer.md
```

## 사전 준비

로컬에서 실행하려면 아래 도구가 필요합니다.

- Node.js 22 이상
- npm
- Flutter 3.41 이상
- Xcode
- iOS Simulator
- Android Studio
- Android SDK
- Vercel CLI 또는 `npx vercel`
- Supabase 프로젝트

현재 프로젝트는 macOS에서 iOS 우선으로 개발을 시작했고, Android 빌드 타겟도 함께 구성되어 있습니다.

## 현재 완료된 상태

2026년 5월 25일 기준으로 아래 흐름까지 확인했습니다.

- GitHub `main` 브랜치 push 완료
- Next.js API 서버 Vercel Production 배포 완료
- Vercel Production API health check 확인 완료
- Supabase `users`, `authentications` 로그인 schema 준비
- Supabase `families`, `family_members`, `family_invitations` 그룹 관리 schema 준비
- 카카오 웹 로그인 테스트 완료
- Flutter 카카오 SDK 로그인 테스트 완료
- Flutter 앱에서 카카오 access token을 Next.js API로 전달하는 모바일 로그인 흐름 구현
- 최초 가입 시 닉네임 입력 및 프로필 닉네임 수정 구현
- 그룹 생성, 수정, 삭제, 구성원 조회, 구성원 닉네임 기반 추가, 구성원별 초대/수락, 구성원 삭제 구현
- iOS 공유 시트로 그룹 초대 링크 공유 구현
- 주차 관리 schema/API/Flutter 화면 구현
- 차량 등록, 수정, 삭제 구현
- 주차 위치 즐겨찾기를 층수와 위치로 분리해 등록, 수정, 삭제 구현
- 차량별 현재 주차 위치 등록 구현, 기존 위치가 있으면 층/위치 자동 선택
- 반복 일정 관리 schema/API/Flutter 화면 구현, 등록 시 캘린더 자동 일정 생성
- 그룹 구성원별 일정 등록, 수정, 삭제, 상세 조회 구현
- 일정 일간/주간/월간 캘린더 화면 구현
- 일간/주간 캘린더는 시간축 기반으로 표시하고 일정이 있는 시간대로 자동 이동
- 일정 관리 구성원별 필터 구현
- 홈 화면 하단 탭 구조 구현
- 홈 화면에서 오늘 일정과 현재 주차 위치 브리핑 카드 구현
- 홈 브리핑 카드 클릭 시 일정 또는 주차 탭으로 이동
- Flutter 앱을 iOS Simulator와 실제 iPhone 네이티브 환경에서 실행 확인
- Flutter Android debug APK 빌드 확인
- 앱 UI는 Flutter Cupertino 위젯 중심으로 정리

현재 Production API 주소는 아래와 같습니다.

```text
https://favis.vercel.app
```

health check:

```bash
curl https://favis.vercel.app/api/health
```

## 빠르게 앱만 실행해보기

앱 로그인을 확인하려면 먼저 로컬 Next.js API 서버를 실행합니다.

```bash
cd /Users/changhwanlee/Documents/project/favis
npm run dev:api
```

기본 주소는 `http://localhost:3000`입니다. 그 다음 카카오 네이티브 앱 키를 iOS 설정에 넣습니다.

카카오 개발자 콘솔의 iOS 플랫폼 Bundle ID에는 아래 값을 등록합니다.

```text
com.family.checky.mobile
```

```bash
cd /Users/changhwanlee/Documents/project/favis/apps/mobile
perl -pi -e 's/^KAKAO_NATIVE_APP_KEY=.*/KAKAO_NATIVE_APP_KEY=여기에_카카오_NATIVE_APP_KEY/' ios/Flutter/Debug.xcconfig
```

Flutter 실행 시에도 같은 네이티브 앱 키를 `--dart-define`으로 전달합니다.

```bash
cd /Users/changhwanlee/Documents/project/favis/apps/mobile
flutter pub get
```

iOS는 먼저 Simulator를 실행해야 합니다.

```bash
flutter emulators
flutter emulators --launch apple_ios_simulator
```

Simulator가 열린 뒤 사용 가능한 기기 목록을 확인합니다.

```bash
flutter devices
```

예를 들어 `iPhone 17 Pro`가 보이면 아래처럼 실행합니다.

```bash
flutter run -d "iPhone 17 Pro" --dart-define=KAKAO_NATIVE_APP_KEY=여기에_카카오_NATIVE_APP_KEY
```

기기 이름으로 실행이 안 되면 `flutter devices`에 표시된 device id를 사용합니다.

```bash
flutter run -d <device-id>
```

참고로 `flutter run -d ios`는 보통 동작하지 않습니다. `ios`는 플랫폼 이름이고, Flutter가 실행 대상으로 인식하는 실제 기기 이름이나 device id가 필요합니다.

정상 실행되면 `카카오로 계속하기` 버튼이 있는 로그인 화면이 표시됩니다.

현재 Flutter 앱의 기본 API 주소는 iOS Simulator 기준 `http://localhost:3000`입니다. 다른 포트나 실제 iPhone에서 테스트하려면 실행 시 `API_BASE_URL`을 지정합니다.

```bash
flutter run -d "iPhone 17 Pro" \
  --dart-define=KAKAO_NATIVE_APP_KEY=여기에_카카오_NATIVE_APP_KEY \
  --dart-define=API_BASE_URL=http://localhost:3001

flutter run -d "iPhone 17 Pro" \
  --dart-define=KAKAO_NATIVE_APP_KEY=여기에_카카오_NATIVE_APP_KEY \
  --dart-define=API_BASE_URL=http://192.168.x.x:3000
```

Vercel에 배포된 API를 바라보게 하려면 아래처럼 실행합니다.

```bash
flutter run -d "iPhone 17 Pro" \
  --dart-define=KAKAO_NATIVE_APP_KEY=여기에_카카오_NATIVE_APP_KEY \
  --dart-define=API_BASE_URL=https://favis.vercel.app
```

앱 첫 화면에서 `카카오로 계속하기`를 누르면 카카오 로그인 후 SDK가 받은 access token을 Next.js `/api/mobile/auth/kakao`로 전달합니다. 서버는 `users`와 `authentications`를 생성 또는 갱신하고 자체 session token을 반환합니다.

### iOS Simulator가 보이지 않을 때

현재 기기에 설치된 iOS Simulator 목록은 아래 명령으로 확인할 수 있습니다.

```bash
xcrun simctl list devices available
```

Simulator가 설치되어 있는데 모두 `Shutdown` 상태라면 하나를 직접 부팅할 수 있습니다.

```bash
xcrun simctl boot "iPhone 17 Pro"
open -a Simulator
flutter devices
flutter run -d "iPhone 17 Pro"
```

그래도 iOS 기기가 나오지 않으면 Xcode에서 `Settings > Platforms`로 이동해 iOS Simulator runtime이 설치되어 있는지 확인합니다.

### 실제 iPhone에서 실행하기

실제 iPhone에서 실행하려면 Simulator와 달리 Apple 코드사이닝 설정이 필요합니다.

먼저 iPhone을 USB 또는 Wi-Fi로 연결하고, 기기에서 신뢰 팝업을 승인합니다. `flutter devices`에서 실제 기기가 보이는지 확인합니다.

```bash
cd /Users/changhwanlee/Documents/project/favis/apps/mobile
flutter devices
```

기기가 `unpaired` 상태로 보이면 Xcode에서 페어링을 완료합니다.

1. Xcode 실행
2. `Window > Devices and Simulators`
3. 연결된 iPhone 선택
4. Pairing 요청 승인
5. iPhone 화면의 신뢰 또는 개발자 모드 안내 승인

그 다음 Flutter iOS 프로젝트를 Xcode로 엽니다.

```bash
cd /Users/changhwanlee/Documents/project/favis/apps/mobile
open ios/Runner.xcworkspace
```

Xcode에서 아래 설정을 확인합니다.

- `Runner` project 선택
- `Runner` target 선택
- `Signing & Capabilities` 탭 이동
- `Automatically manage signing` 체크
- `Team`에 본인 Apple ID 또는 Apple Developer Team 선택
- Bundle ID가 카카오 개발자 콘솔의 iOS 플랫폼 Bundle ID와 같은지 확인

무료 Apple ID로도 실기기 디버그 실행은 가능하지만, Xcode가 Development Certificate와 Provisioning Profile을 자동 생성해야 합니다.

설정이 끝나면 다시 Flutter에서 실행합니다.

```bash
flutter run -d "iPhone 이름 또는 device id" \
  --dart-define=KAKAO_NATIVE_APP_KEY=여기에_카카오_NATIVE_APP_KEY \
  --dart-define=API_BASE_URL=https://favis.vercel.app
```

처음 설치한 뒤 iPhone에서 개발자 인증서를 신뢰해야 할 수 있습니다.

```text
설정 > 일반 > VPN 및 기기 관리 > Developer App > 신뢰
```

실제 iPhone은 Mac의 `localhost`를 바라볼 수 없습니다. 실기기에서는 Vercel Production API를 사용하거나, 같은 Wi-Fi에서 Mac의 내부 IP 주소를 `API_BASE_URL`로 넘겨야 합니다.

### Android Emulator 또는 Android 기기에서 실행하기

Android 실행을 위해서는 Android Studio와 Android SDK가 필요합니다.

1. Android Studio 설치
2. Android Studio에서 `Settings > Languages & Frameworks > Android SDK` 확인
3. SDK Platform과 Android SDK Command-line Tools 설치
4. Android Emulator를 만들거나 실제 Android 기기를 USB 디버깅으로 연결

Flutter에서 Android toolchain 상태를 확인합니다.

```bash
flutter doctor -v
flutter devices
```

카카오 개발자 콘솔의 Android 플랫폼에는 아래 패키지명을 등록합니다.

```text
com.family.checky.mobile
```

Android 카카오 로그인은 패키지명 외에 키 해시도 필요합니다. 개발용 debug keystore 기준 키 해시는 아래처럼 확인할 수 있습니다.

```bash
cd /Users/changhwanlee/Documents/project/favis/apps/mobile
keytool -exportcert -alias androiddebugkey \
  -keystore ~/.android/debug.keystore \
  -storepass android -keypass android \
  | openssl sha1 -binary | openssl base64
```

출력된 값을 카카오 개발자 콘솔의 Android 플랫폼 `키 해시`에 추가합니다. 나중에 Play Store 배포용 release keystore를 만들면 release keystore의 키 해시도 별도로 추가해야 합니다.

Android Emulator에서 로컬 API 서버를 바라볼 때는 Mac의 `localhost` 대신 `10.0.2.2`를 사용합니다.

```bash
cd /Users/changhwanlee/Documents/project/favis/apps/mobile
flutter run -d <android-device-id> \
  --dart-define=KAKAO_NATIVE_APP_KEY=여기에_카카오_NATIVE_APP_KEY \
  --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

실제 Android 기기는 Mac의 `localhost`를 직접 볼 수 없습니다. 실제 기기에서는 Vercel Production API를 쓰는 것이 가장 간단합니다.

```bash
flutter run -d <android-device-id> \
  --dart-define=KAKAO_NATIVE_APP_KEY=여기에_카카오_NATIVE_APP_KEY \
  --dart-define=API_BASE_URL=https://favis.vercel.app
```

Android 빌드는 루트 스크립트를 사용하는 것을 권장합니다.

```bash
cd /Users/changhwanlee/Documents/project/favis
scripts/build-android.sh
```

기본값은 Play Console 업로드에 사용하는 release app bundle입니다.

```text
apps/mobile/build/app/outputs/bundle/release/app-release.aab
```

debug APK만 빌드하려면:

```bash
scripts/build-android.sh --format apk --mode debug
```

또는 npm script로도 실행할 수 있습니다.

```bash
npm run mobile:build:android
```

주요 옵션:

```bash
scripts/build-android.sh \
  --format appbundle \
  --mode release \
  --build-name 1.0.0 \
  --build-number 2 \
  --kakao-native-app-key 여기에_카카오_NATIVE_APP_KEY \
  --api-base-url https://favis.vercel.app
```

### Android release 서명 준비

Play Console에 업로드할 `release` 빌드는 debug key가 아니라 upload keystore로 서명해야 합니다.

먼저 upload keystore를 만듭니다.

```bash
cd /Users/changhwanlee/Documents/project/favis/apps/mobile/android
keytool -genkey -v \
  -keystore favis-upload-key.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias favis-upload
```

그 다음 `key.properties`를 만듭니다.

```bash
cp key.properties.example key.properties
```

`apps/mobile/android/key.properties` 값을 실제 비밀번호와 파일명으로 채웁니다.

```properties
storePassword=업로드키_비밀번호
keyPassword=업로드키_비밀번호
keyAlias=favis-upload
storeFile=favis-upload-key.jks
```

`key.properties`와 `*.jks` 파일은 비밀 파일이라 git에 커밋하지 않습니다.

설정 후 Play Console용 AAB를 다시 빌드합니다.

```bash
cd /Users/changhwanlee/Documents/project/favis
scripts/build-android.sh --format appbundle --mode release
```

release 키 해시는 아래처럼 확인해 카카오 Developers Android 플랫폼에 추가합니다.

```bash
cd /Users/changhwanlee/Documents/project/favis/apps/mobile/android
keytool -exportcert -alias favis-upload \
  -keystore favis-upload-key.jks \
  | openssl sha1 -binary | openssl base64
```

debug APK 결과물은 아래에 생성됩니다.

```text
apps/mobile/build/app/outputs/flutter-apk/app-debug.apk
```

현재 Android 앱 설정:

- Application ID: `com.family.checky.mobile`
- 앱 이름: `체키`
- 카카오 redirect scheme: `kakao{KAKAO_NATIVE_APP_KEY}`
- Android manifest는 `--dart-define=KAKAO_NATIVE_APP_KEY=...` 값을 읽어 카카오 콜백 scheme에 반영합니다.

### 홈 위젯 iOS 서명 설정

iOS 홈 위젯은 앱과 `group.com.family.checky.mobile` App Group을 공유해 오늘 일정을 표시합니다. 작은 위젯은 최대 2개, 넓은 위젯은 최대 5개를 표시하며 추가 일정은 `더 보기 +N개`로 안내합니다. 실제 기기·TestFlight·App Store 빌드 전 Apple Developer의 Identifiers에서 아래 두 App ID에 **App Groups** capability를 켜고 같은 그룹을 연결해야 합니다.

- `com.family.checky.mobile`
- `com.family.checky.mobile.CheckyHomeWidget`

연결 후 Xcode에서 `Runner`와 `CheckyHomeWidget` target의 Signing & Capabilities에 `group.com.family.checky.mobile`가 보이는지 확인합니다. iOS와 Android 모두 오늘 일정만 간략하게 표시합니다.

## 전체 프로젝트 설치

루트에서 Node 의존성을 설치합니다.

```bash
cd /Users/changhwanlee/Documents/project/favis
npm install
```

Flutter 의존성은 모바일 앱 폴더에서 받습니다.

```bash
cd /Users/changhwanlee/Documents/project/favis/apps/mobile
flutter pub get
```

## 환경변수

API 서버는 `apps/api`를 Next.js 프로젝트 루트로 실행하므로, 루트의 `.env.example`을 기준으로 `apps/api/.env.local`에 환경변수를 준비합니다.

```bash
SUPABASE_URL=
SUPABASE_SECRET_KEY=
SUPABASE_PUBLISHABLE_KEY=
KAKAO_REST_API_KEY=
KAKAO_CLIENT_SECRET=
KAKAO_REDIRECT_URI=http://localhost:3000/api/auth/kakao/callback
SESSION_SECRET=
WEB_INVITE_BASE_URL=https://favis.vercel.app/invite
CRON_SECRET=
KASI_SERVICE_KEY=
```

중요한 규칙:

- `SUPABASE_SECRET_KEY`는 서버 전용입니다.
- Flutter 앱에는 secret key를 절대 넣지 않습니다.
- `SUPABASE_PUBLISHABLE_KEY`는 공개 가능한 키이지만, 현재 Flutter 앱은 Next.js API만 호출하므로 아직 사용하지 않습니다.
- 실제 secret 값은 `.env.local`이나 Vercel Environment Variables에만 저장합니다.
- `.env.local`은 커밋하지 않습니다.
- `KAKAO_CLIENT_SECRET`은 카카오 개발자 콘솔에서 client secret이 활성화된 경우 넣습니다.
- `SESSION_SECRET`은 모바일 앱용 자체 세션 토큰 서명에 사용합니다. 충분히 긴 랜덤 문자열을 사용합니다.
- `WEB_INVITE_BASE_URL`은 그룹 초대 공유용 HTTPS 링크 생성에 사용합니다. 미설정 시 Vercel 도메인 기반 `/invite` 경로를 사용합니다. 카카오톡 공유 안정성을 위해 `checky://...` 같은 커스텀 scheme을 직접 공유하지 않습니다.
- `CRON_SECRET`은 Supabase Cron이 일정 알림 발송 API를 호출할 때 사용하는 Bearer token입니다. Vercel과 Supabase Cron 설정에 같은 값을 넣고, repo에는 커밋하지 않습니다.
- `KASI_SERVICE_KEY`는 한국천문연구원 특일 정보 API의 공공데이터포털 서비스 키입니다. 서버에서만 공휴일을 동기화할 때 사용하며, 앱에 넣거나 커밋하지 않습니다.

로컬에서 직접 환경변수 파일을 만들려면:

```bash
cd /Users/changhwanlee/Documents/project/checky/apps/api
cp ../../.env.example .env.local
```

그 다음 `apps/api/.env.local`에 Supabase 값과 필요한 API 키를 채웁니다. 특히 공휴일 동기화에는 `KASI_SERVICE_KEY`가 필요합니다.

Vercel 프로젝트를 연결한 뒤 환경변수를 내려받으려면:

```bash
cd /Users/changhwanlee/Documents/project/checky/apps/api
npx vercel link
npx vercel env pull .env.local --yes
```

## Supabase DB 준비

Supabase 프로젝트를 만든 뒤 migration 파일을 적용합니다.

```text
supabase/migrations/202606260001_initial_schema.sql
```

가장 간단한 방법은 Supabase Dashboard에서 SQL Editor를 열고 migration SQL을 실행하는 것입니다.

Supabase CLI를 사용하는 경우에는 프로젝트 연결 후 migration을 적용합니다.

```bash
cd /Users/changhwanlee/Documents/project/favis
supabase link --project-ref <project-ref>
supabase db push
```

현재 schema에는 아래 테이블이 포함됩니다.

- `users`
- `authentications`
- `families`
- `family_members`
- `family_invitations`
- `vehicles`
- `parking_location_presets`
- `parking_records`
- `schedules`
- `education_programs`

Row Level Security는 켜져 있습니다. 현재 Vercel API는 서버에서 Supabase secret key를 사용하므로 모바일 앱이 DB에 직접 접근하지 않습니다.

그룹 권한은 아래처럼 동작합니다.

- `owner`: 대표. 그룹 안의 추가, 수정, 삭제, 조회 가능
- `member`: 구성원. 그룹과 구성원 조회만 가능

그룹 구성원은 로그인 계정 없이도 먼저 닉네임과 권한으로 추가할 수 있습니다. 어린 자녀처럼 앱에 가입하지 않는 구성원도 일정과 반복 일정 담당자로 바로 사용할 수 있습니다. 초대가 필요한 경우 대표가 특정 구성원에 대한 난수 초대 토큰을 만들고, 앱에서 초대 링크를 복사하거나 공유 시트로 카카오톡/문자 등에 전달합니다. 초대받은 사용자가 그룹 관리 화면의 `초대 링크 수락`에서 링크나 코드를 입력하면 해당 구성원의 `user_id`에 로그인 계정이 연결됩니다. 초대 링크는 기본 7일 동안 유효합니다.

주차, 일정, 반복 일정 데이터도 모두 `family_id`를 기준으로 저장합니다. 일정과 반복 일정은 `family_member_id`를 함께 저장해 그룹 구성원 중 누구의 일정인지 지정합니다.

## 백엔드 API 실행

백엔드는 Next.js API 서버로 실행합니다. 루트에서 API dev server를 실행합니다.

```bash
cd /Users/changhwanlee/Documents/project/favis
npm run dev:api
```

또는 API 앱 폴더에서 직접 실행할 수 있습니다.

```bash
cd /Users/changhwanlee/Documents/project/favis/apps/api
npm run dev
```

기본 Next.js dev server 주소는 `http://localhost:3000`입니다. 이미 3000번 포트가 사용 중이면 Next.js가 `http://localhost:3001`처럼 다른 포트를 안내합니다.

현재 API 앱은 로컬 dev에서 `next dev --webpack`을 사용합니다. Next.js가 상위 홈 디렉터리의 lockfile을 workspace root로 잘못 추론하거나 Turbopack dev server가 서버 패키지를 찾지 못하는 문제를 피하기 위한 설정입니다.

health check는 아래처럼 확인합니다.

```bash
curl http://localhost:3000/api/health
```

예상 응답:

```json
{
  "ok": true,
  "service": "favis-api",
  "framework": "nextjs"
}
```

## 카카오 로그인 실행

카카오 개발자 콘솔에서 앱을 만든 뒤 아래 값을 확인합니다.

- REST API 키
- Client Secret 사용 여부
- Redirect URI

로컬 테스트용 Redirect URI는 카카오 개발자 콘솔에 아래 값으로 등록합니다.

```text
http://localhost:3000/api/auth/kakao/callback
```

그 다음 `apps/api/.env.local`에 값을 넣습니다.

```bash
KAKAO_REST_API_KEY=<카카오 REST API 키>
KAKAO_CLIENT_SECRET=<client secret 사용 시 입력>
KAKAO_REDIRECT_URI=http://localhost:3000/api/auth/kakao/callback
```

API 서버를 실행합니다.

```bash
cd /Users/changhwanlee/Documents/project/favis
npm run dev:api
```

브라우저에서 아래 주소를 엽니다.

```text
http://localhost:3000
```

`카카오로 로그인` 버튼을 누르면 카카오 로그인 화면으로 이동합니다. 로그인 후 돌아오면 Next.js 서버가 카카오 `user/me` API를 호출하고, 홈 화면에 사용자 정보를 표시합니다.

## Flutter 앱 인증 API

Flutter 앱은 카카오 Flutter SDK로 카카오 access token을 받은 뒤, Next.js 서버에 전달합니다. 서버는 다시 카카오 `user/me`를 호출해 토큰을 검증하고, `users`와 `authentications` 테이블을 생성 또는 갱신한 뒤 자체 session token을 반환합니다.

신규 사용자는 첫 로그인 시 바로 `users`를 만들지 않고 `profile_required` 응답을 받습니다. Flutter 앱은 닉네임 입력 화면을 표시하고, 입력한 닉네임과 카카오 access token을 다시 보내 가입을 완료합니다. 기존 사용자의 닉네임은 카카오 프로필로 덮어쓰지 않고 프로필 화면에서만 수정합니다.

로그인:

```http
POST /api/mobile/auth/kakao
content-type: application/json

{
  "accessToken": "<kakao access token>"
}
```

응답:

```json
{
  "tokenType": "Bearer",
  "accessToken": "<Checky session token>",
  "expiresIn": 2592000,
  "isNewUser": true,
  "user": {
    "id": "uuid",
    "nickname": "nickname",
    "last_login_at": "2026-05-18T00:00:00.000Z",
    "created_at": "2026-05-18T00:00:00.000Z",
    "updated_at": "2026-05-18T00:00:00.000Z"
  }
}
```

신규 사용자에게 닉네임 입력이 필요한 경우:

```json
{
  "error": "profile_required",
  "provider": "kakao",
  "providerId": "1348234"
}
```

닉네임을 포함해 가입 완료:

```http
POST /api/mobile/auth/kakao
content-type: application/json

{
  "accessToken": "<kakao access token>",
  "nickname": "아빠"
}
```

현재 로그인 사용자 확인:

```http
GET /api/mobile/auth/me
authorization: Bearer <Checky session token>
```

로그아웃:

```http
POST /api/mobile/auth/logout
authorization: Bearer <Checky session token>
```

로그아웃 API는 서버 세션 저장소를 아직 쓰지 않으므로 `{ "ok": true }`만 반환합니다. Flutter 앱에서는 secure storage에 저장한 session token을 삭제하면 됩니다.

## 그룹 관리 API

모든 그룹 관리 API는 `authorization: Bearer <Checky session token>` 헤더가 필요합니다.

그룹 목록:

```http
GET /api/mobile/families
```

그룹 생성:

```http
POST /api/mobile/families
content-type: application/json

{
  "name": "우리집"
}
```

그룹 상세 조회:

```http
GET /api/mobile/families/<familyId>
```

그룹 이름 수정:

```http
PATCH /api/mobile/families/<familyId>
content-type: application/json

{
  "name": "새 그룹 이름"
}
```

그룹 삭제:

```http
DELETE /api/mobile/families/<familyId>
```

구성원 목록:

```http
GET /api/mobile/families/<familyId>/members
```

구성원 추가:

```http
POST /api/mobile/families/<familyId>/members
content-type: application/json

{
  "nickname": "첫째",
  "role": "member"
}
```

`role`은 `owner`, `member` 중 하나입니다. `nickname`으로 먼저 구성원을 추가하므로, 해당 구성원이 아직 로그인 계정을 갖고 있지 않아도 일정과 반복 일정 담당자로 지정할 수 있습니다.

구성원 초대 링크 생성:

```http
POST /api/mobile/families/<familyId>/invitations
content-type: application/json

{
  "memberId": "<familyMemberId>"
}
```

초대 링크는 특정 구성원에 매핑됩니다. 수락한 사용자의 계정은 새 구성원으로 추가되는 것이 아니라 해당 구성원의 `user_id`에 연결됩니다. 이미 계정이 연결된 구성원에는 초대 링크를 만들 수 없습니다.

초대 수락:

```http
POST /api/mobile/family-invitations/<inviteToken>
```

구성원 삭제:

```http
DELETE /api/mobile/families/<familyId>/members/<memberId>
```

대표만 쓰기 API를 호출할 수 있습니다. 구성원은 조회만 가능합니다. 본인은 구성원 목록에서 삭제할 수 없으며, 서버도 `cannot_remove_self`로 거절합니다. 마지막 대표를 삭제하는 요청도 `cannot_remove_last_owner`로 거절합니다. 앱에서는 미연결 구성원 카드에 링크 버튼을 표시해 초대 링크를 만들고 공유할 수 있습니다.

## 주차 관리 API

모든 주차 관리 API는 `authorization: Bearer <Checky session token>` 헤더가 필요합니다.

주차 대시보드 조회:

```http
GET /api/mobile/families/<familyId>/parking
```

응답에는 차량 목록, 주차 위치 즐겨찾기, 차량별 최신 주차 위치, 쓰기 가능 여부가 포함됩니다.

차량별 주차 기록 조회:

```http
GET /api/mobile/families/<familyId>/parking/records?vehicleId=<vehicleId>
```

차량마다 최근 주차 기록 10개를 최신순으로 반환합니다. 새 기록이 추가되면 가장 오래된 기록은 자동으로 정리됩니다.

차량 등록:

```http
POST /api/mobile/families/<familyId>/parking/vehicles
content-type: application/json

{
  "nickname": "패밀리카",
  "plateNumber": "12가3456"
}
```

차량 수정/삭제:

```http
PATCH /api/mobile/families/<familyId>/parking/vehicles/<vehicleId>
DELETE /api/mobile/families/<familyId>/parking/vehicles/<vehicleId>
```

주차 위치 즐겨찾기 등록:

```http
POST /api/mobile/families/<familyId>/parking/presets
content-type: application/json

{
  "presetType": "floor",
  "name": "B1"
}
```

`presetType`은 `floor` 또는 `spot`입니다. 앱에서는 자주 쓰는 층수와 자주 쓰는 위치를 따로 관리합니다. 기본 선택지는 층수 `B1`, `B2`, `B3`, `B4`, 위치 `101동`, `107동`, `가운데`이며 직접 입력도 가능합니다.

주차 위치 즐겨찾기 수정/삭제:

```http
PATCH /api/mobile/families/<familyId>/parking/presets/<presetId>
DELETE /api/mobile/families/<familyId>/parking/presets/<presetId>
```

차량 주차 위치 등록:

```http
POST /api/mobile/families/<familyId>/parking/records
content-type: application/json

{
  "vehicleId": "<vehicleId>",
  "floorPresetId": "<floorPresetId>",
  "spotPresetId": "<spotPresetId>",
  "floorText": "B2",
  "spotText": "101동"
}
```

`floorPresetId`, `spotPresetId`는 선택 입력입니다. 프리셋 없이 `floorText`, `spotText`만 보내 직접 입력 위치를 저장할 수 있습니다. 서버는 표시용 `locationText`를 `층 / 위치` 형태로 함께 저장합니다. 앱에서 이미 등록된 현재 위치가 있으면 위치 등록 화면 진입 시 기존 층과 위치가 자동 선택됩니다. 대표만 쓰기 API를 호출할 수 있고, 구성원은 조회만 가능합니다.

## 일정 관리 API

모든 일정 관리 API는 `authorization: Bearer <Checky session token>` 헤더가 필요합니다.

일정 대시보드 조회:

```http
GET /api/mobile/families/<familyId>/schedules?rangeStart=<ISO8601>&rangeEnd=<ISO8601>
```

응답에는 그룹 구성원 목록, 조회 범위 안의 일정 목록, 쓰기 가능 여부가 포함됩니다.

공휴일 조회:

```http
GET /api/mobile/families/<familyId>/holidays?rangeStart=<ISO8601>&rangeEnd=<ISO8601>
```

공휴일 탭은 조회한 공휴일과 주말을 기준으로 3일 이상 연휴, 평일 하루를 쉬면 3일 이상 연휴가 되는 징검다리를 앱에서 계산해 보여줍니다.

일정 등록:

```http
POST /api/mobile/families/<familyId>/schedules
content-type: application/json

{
  "familyMemberId": "<familyMemberId>",
  "title": "수학 수업",
  "content": "교재 챙기기",
  "startsAt": "2026-05-23T06:00:00.000Z",
  "endsAt": "2026-05-23T07:00:00.000Z",
  "vehicleBoardingAt": "2026-05-23T05:30:00.000Z",
  "vehicleDropoffAt": "2026-05-23T07:20:00.000Z"
}
```

`content`, `vehicleBoardingAt`, `vehicleDropoffAt`은 선택 입력입니다.

일정 수정/삭제:

```http
PATCH /api/mobile/families/<familyId>/schedules/<scheduleId>
DELETE /api/mobile/families/<familyId>/schedules/<scheduleId>
```

대표만 등록, 수정, 삭제할 수 있고, 구성원은 조회만 가능합니다.

Flutter 일정 화면은 Cupertino 위젯 기반입니다. 기본은 주간 뷰이며, 일/주/월 전환을 제공합니다. 캘린더는 `일 월 화 수 목 금 토` 순서로 표시합니다. 일간/주간 뷰는 시간축 기반이며, 해당 날짜 또는 오늘 일정이 있으면 가장 이른 일정 시간대로 자동 이동하고 일정이 없으면 8시 근처로 이동합니다. 캘린더의 날짜 또는 시간 칸을 누르면 해당 날짜와 시간으로 일정 등록 화면을 엽니다. 일정 칩을 누르면 상세 화면에서 제목, 내용, 구성원, From, To, 차량승차시각, 하차시각을 확인하고 수정 또는 삭제할 수 있습니다.

## 반복 일정 관리

반복 일정 관리는 그룹 구성원별 반복 일정을 관리하는 기능입니다.

- 이름
- 담당 그룹 구성원
- 시작일과 종료일
- 요일별 시작/종료 시각
- 요일별 차량탑승시각과 하차시각

반복 일정 등록 시 선택한 기간과 요일별 시각을 기준으로 일정 데이터도 자동 생성합니다. 캘린더에는 반복 일정 이름이 일정 제목으로 표시됩니다. 요일별 시간 입력은 클라이언트에서 바로 위 요일의 값을 복사할 수 있습니다.

## 검증 명령어

TypeScript 타입체크:

```bash
cd /Users/changhwanlee/Documents/project/favis
npm run typecheck
```

Flutter analyze:

```bash
cd /Users/changhwanlee/Documents/project/favis
npm run mobile:analyze
```

Flutter test:

```bash
cd /Users/changhwanlee/Documents/project/favis
npm run mobile:test
```

모바일 폴더에서 직접 실행해도 됩니다.

```bash
cd /Users/changhwanlee/Documents/project/favis/apps/mobile
flutter analyze
flutter test
```

## Vercel 배포 준비

Vercel 프로젝트를 연결합니다.

```bash
cd /Users/changhwanlee/Documents/project/favis
npx vercel link
```

Vercel Dashboard 또는 CLI로 아래 환경변수를 등록합니다.

- `SUPABASE_URL`
- `SUPABASE_SECRET_KEY`
- `KAKAO_REST_API_KEY`
- `KAKAO_CLIENT_SECRET`
- `KAKAO_REDIRECT_URI`
- `SESSION_SECRET`
- `WEB_INVITE_BASE_URL`
- `CRON_SECRET`
- `KASI_SERVICE_KEY`

현재 서버 코드는 Supabase 서버용 secret key만 사용하므로 `SUPABASE_PUBLISHABLE_KEY`는 필수값이 아닙니다.

캘린더는 토요일·일요일과 동기화된 대한민국 공휴일을 빨간색으로 표시합니다. 공휴일은 한국천문연구원 특일 정보 API에서 현재·다음 연도 기준으로 동기화하며, 과거 데이터는 한 번에 백필할 수 있습니다. 일정 알림 발송과 공휴일 동기화는 Vercel Cron 대신 Supabase Cron으로 호출합니다. 설정 방법은 [docs/supabase-cron.md](docs/supabase-cron.md)를 참고합니다.

Production 배포용 카카오 Redirect URI는 카카오 개발자 콘솔에도 동일하게 등록해야 합니다.

```text
https://favis.vercel.app/api/auth/kakao/callback
```

등록 후 로컬 env를 다시 내려받습니다.

```bash
npx vercel env pull .env.local --yes
```

Preview 배포:

```bash
npx vercel
```

Production 배포:

```bash
npx vercel --prod
```

현재 API 앱은 `/Users/changhwanlee/Documents/project/favis/apps/api`가 Vercel 프로젝트로 연결되어 있습니다. API 앱 폴더에서 바로 Production 배포할 수도 있습니다.

```bash
cd /Users/changhwanlee/Documents/project/favis/apps/api
npx vercel --prod --yes
```

배포 후 health check로 확인합니다.

```bash
curl https://favis.vercel.app/api/health
```

## 개발 역할

하네스 엔지니어링 문서는 역할별 소유 영역과 완료 기준을 정리합니다.

- 기획자: `docs/product-plan.md`, 기능 요구사항, 수용 기준
- 디자이너: `apps/mobile/lib/**`, 화면 구조, 접근성, 상태별 UX
- 앱개발자: `apps/mobile`
- 백엔드개발자: `apps/api`, `packages/contracts`, `supabase`

자세한 내용은 아래 문서를 확인합니다.

- `docs/harness-engineering.md`
- `harness/planner.md`
- `harness/designer.md`
- `harness/app-developer.md`
- `harness/backend-developer.md`

## 다음 개발 순서

1. Supabase에 최신 migration 적용
2. Vercel Production API 재배포
3. 실제 iPhone에서 가입, 그룹 생성, 구성원 추가/초대/수락, 주차 관리, 일정 등록/수정/삭제 회귀 테스트
4. 일정 반복 규칙과 알림 같은 고급 기능 검토
5. 주차 기록 히스토리와 차량별 기록 조회 기능 검토


## 그룹 초대 링크

그룹 초대 링크는 카카오톡 등 메신저에서 안정적으로 열리도록 HTTPS 링크로 생성합니다.

```text
https://favis.vercel.app/invite/<초대토큰>
```

초대 페이지는 체키 앱이 설치된 단말에서 아래 앱 딥링크로 이동합니다.

```text
checky://family-invite/<초대토큰>
```

Android는 `checky://family-invite/...`와 기존 호환용 `favis://family-invite/...`를 모두 받을 수 있습니다. iOS도 동일한 URL scheme을 등록합니다.
