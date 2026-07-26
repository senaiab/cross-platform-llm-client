# PrivateLM Tool-Calling Build Memory

This repo is the forked PrivateLM build at:

- Local path: `/data/data/com.termux/files/home/PrivateLM-toolcalling`
- Branch: `feature/opendroid-fusion` (current active branch)
- Fork remote: `https://github.com/senaiab/cross-platform-llm-client.git`
- Upstream/tracking branch: `fork/feature/tool-calling-agent`

## Current Completed Work

The current source state on `feature/opendroid-fusion` includes full OpenDroid phone automation integration (see OpenDroid Integration section below).

Last committed baseline (before opendroid work):

- `dda4bb4 Add LiteRT v79 Qualcomm NPU dispatcher for HTP acceleration`

Previous relevant commits:

- `40bf0a4 Add NPU backend for LiteRT-LM on Snapdragon/MediaTek devices`
- `9a1fb5c Replace Firebase with local crash reporter; fix tool follow-up history`
- `7508412 Add Termux RUN_COMMAND permission to enable shell bridge`
- `1f429f9 Fix GetX improper-use error in LogView filter chip Obx`
- `d8c145b Add copy action to chat messages`
- `8aa4971 Use stable release signing for Android builds`
- `fb41501 Retry transient cloud API disconnects`
- `5be1575 Implement XLSX tool handling`

## OpenDroid Integration

Ported OpenDroid phone automation into PrivateLM as a Hilt-free embedded module:

**Package**: `com.orailnoor.privatelm.opendroid` (repackaged from `com.opendroid.ai`)

**New files added under `android/app/src/main/kotlin/com/orailnoor/privatelm/opendroid/`**:

- `accessibility/`: OpenDroidAccessibilityService.kt (Step 3 mods: no agentLoop/DI, string states for FloatingWidgetView, openMainActivityAction targets PrivateLM), SmsAutomator.kt (added direct `sendSms(context, to, message)`), CallAutomator.kt (added direct `makeCall(context, to)`), WhatsAppAutomator.kt, GenericAppAutomator.kt
- `core/service/`: OpenDroidService.kt (minimal foreground service skeleton), OpenDroidNotificationListener.kt (Hilt stripped, autoReplyEngine removed), BootReceiver.kt
- `core/memory/`: WorkingMemory.kt (simplified, no ChatMessage/Plan/DeviceStateProvider), NotificationIntelligence.kt (simplified, uses only DAO methods present in PrivateLM's NotificationDao, patterns stored in-memory), EpisodicMemory.kt, SemanticMemory.kt, ProceduralMemory.kt, MemoryExtractor.kt (stubs)
- `actions/`: ActionDispatcher.kt (Hilt stripped), AdvancedControlActions.kt (Hilt stripped, all 23 inner action classes intact)

**New root-package file**: `PhoneActionBridge.kt` — Flutter MethodChannel `com.orailnoor.privatelm/phone_actions` exposing `sendSms` and `makeCall`. Uses `applicationContext` (not Activity) to avoid context leak. Results dispatched to main thread via `withContext(Dispatchers.Main)`.

**Modified**:
- `MainActivity.kt`: Added `PhoneActionBridge(applicationContext, flutterEngine)` at end of `configureFlutterEngine`
- `AndroidManifest.xml`: Added SEND_SMS, CALL_PHONE, READ_SMS permissions; registered OpenDroidAccessibilityService, OpenDroidNotificationListener, OpenDroidService (foreground/dataSync), BootReceiver (.opendroid.core.service.BootReceiver)
- `build.gradle.kts`: Added serialization plugin (2.2.20), KSP plugin (2.2.20-2.0.4), Room 2.7.2, DataStore 1.1.4, Coroutines 1.10.2, WorkManager 2.10.1, Serialization JSON 1.8.1
- `settings.gradle.kts`: Added `id("com.google.devtools.ksp") version "2.2.20-2.0.4" apply false`

**New resources**:
- `res/xml/accessibility_service_config.xml`
- `res/values/strings.xml` (accessibility_service_description)
- `res/drawable/bot.xml` (vector placeholder for floating widget icon)

**Hilt stripping rules applied throughout**:
- `@AndroidEntryPoint`, `@HiltAndroidApp`, `@Singleton` (class-level), `@Module`, `@InstallIn`, `@Provides`, `@HiltViewModel` → removed entirely
- `@Inject constructor()` → plain constructor
- `@Inject lateinit var` → not used (classes instantiated manually)

**NOT copied** (intentionally excluded): AgentLoop.kt, IntentClassifier.kt, AutoReplyEngine, di/ directory, all UI/ViewModel/Compose files

## Implemented Features

- SA-AI style tool-calling capabilities are present in the fork.
- OpenRouter/cloud model support includes free-model usage paths.
- Excel/XLSX file handling capability is implemented.
- Weather and location tools are implemented.
- Chat messages now have copy buttons:
  - Finished user messages can be copied.
  - Finished assistant messages can be copied.
  - Streaming assistant responses can be copied while generation is still running.
  - Copy action uses the platform clipboard and shows `Copied chat message`.
- Cloud API transient disconnect handling was improved:
  - Retries transient OpenRouter/network errors.
  - Adds request timeouts.
  - Falls back from streaming to non-streaming when needed.
  - Returns partial streamed text if a connection closes after tokens were received.
- LogView filter chip GetX Obx crash fixed:
  - The filter chip Obx in `lib/views/log_view.dart` threw "improper use of GetX" because `selectedFilter.value` was only read inside a lazy `itemBuilder` callback (zero synchronous subscriptions).
  - Fix: capture `selectedFilter.value` as a local variable at the top of the Obx builder body.

## Android Package And Updates

- Android package/application ID: `com.orailnoor.privatelm`
- Current Flutter app version: `1.0.5+5`
- Release builds now use a stable release signing key from GitHub Actions secrets.
- Future APKs should be updateable over the stable-signed build as long as:
  - `applicationId` stays `com.orailnoor.privatelm`
  - the same release signing key is used
  - `versionCode` increases

Important caveat: if the user currently has an older debug-signed APK installed, Android may reject this stable-signed APK as an update. In that case, uninstall once, install the stable-signed APK, and future stable-signed builds should update normally.

## Release Signing

GitHub repository secrets configured for `senaiab/cross-platform-llm-client`:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Local private signing material is stored outside git:

- Keystore: `/data/data/com.termux/files/home/.privatelm-signing/privatelm-upload-keystore.jks`
- Credentials env file: `/data/data/com.termux/files/home/.privatelm-signing/release-signing.env`

Signing certificate:

- DN: `CN=PrivateLM, OU=PrivateLM, O=PrivateLM, L=Addis Ababa, ST=Addis Ababa, C=ET`
- SHA-256: `1ed126bd75e101e5a739f3e044d677159850eae5960848279de8a34a27adef61`

Do not commit the keystore or credentials.

## Latest Built APK

Latest successful build:

- Commit: `62c0ca6` (Add PTE pre-flight checks; pass modelDir as dataDir for external constants)
- GitHub Actions run: `https://github.com/senaiab/cross-platform-llm-client/actions/runs/30028505122`
- Artifact: `privatelm-tool-calling-arm64-apk`

APK copied to:

- `/storage/emulated/0/Download/privatelm-tool-calling-arm64-release.apk`
- `/data/data/com.termux/files/home/PrivateLM-toolcalling/app-arm64-v8a-release.apk`

APK details:

- Size: `120 MB` (includes ExecuTorch QNN native libs for Fold 7 NPU)
- Verified Android APK v2 signature: true
- Signing cert SHA-256: `1ed126bd75e101e5a739f3e044d677159850eae5960848279de8a34a27adef61`

## Build Notes

Local Termux Flutter Android builds were blocked by host-toolchain issues:

- Flutter bundled Linux Dart binary cannot run directly on Android/Termux.
- Repointing Flutter to Termux Dart led to Flutter snapshot/kernel mismatch.
- Some local Flutter toolchain experiments were made under `/data/data/com.termux/files/home/flutter`, outside this repo.

Use GitHub Actions for release APK builds:

- Workflow: `.github/workflows/android-release.yml`
- It installs Flutter/Android SDK/NDK, decodes the release keystore from secrets, builds arm64 release APK, and uploads the artifact.

To download a GitHub artifact from Termux, signed blob URLs can expire mid-download. Preferred pattern:

1. Get artifact ID:
   `gh api repos/senaiab/cross-platform-llm-client/actions/runs/<run_id>/artifacts --jq '.artifacts[] | [.id,.name,.size_in_bytes,.expired] | @tsv'`
2. Fetch a fresh signed URL:
   `TOKEN=$(gh auth token) && curl -sS -I -L -o /dev/null -w '%{url_effective}' -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" https://api.github.com/repos/senaiab/cross-platform-llm-client/actions/artifacts/<artifact_id>/zip > artifact-url.txt`
3. Download/resume:
   `URL=$(cat artifact-url.txt) && aria2c -c -x 4 -s 4 -k 1M --connect-timeout=20 --timeout=60 --retry-wait=5 --max-tries=8 -o privatelm-tool-calling-arm64-apk.zip "$URL"`
4. If a 403 appears, the signed URL expired. Stop, fetch a fresh URL, and resume with `aria2c -c`.

## Verification Commands

Format/analyze touched files:

```sh
dart format lib/widgets/chat_bubble.dart lib/views/chat_view.dart
dart analyze lib/widgets/chat_bubble.dart lib/views/chat_view.dart
```

The analyzer currently reports only info-level style notes in `lib/views/chat_view.dart`, no warnings or errors for the copy-button changes.

Verify APK signature:

```sh
/data/data/com.termux/files/home/android-sdk/build-tools/36.0.0/apksigner verify --print-certs --verbose /storage/emulated/0/Download/privatelm-tool-calling-arm64-release.apk
```

## Current Dirty Worktree

Expected local-only/generated items currently not committed:

- `android/build/reports/problems/problems-report.html`
- `artifacts/`
- One odd untracked generated file with binary/control characters in its name

These are from local build/download attempts and should not be committed unless explicitly needed.

