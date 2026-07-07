# PrivateLM Tool-Calling Build Memory

This repo is the forked PrivateLM build at:

- Local path: `/data/data/com.termux/files/home/PrivateLM-toolcalling`
- Branch: `feature/tool-calling-agent`
- Fork remote: `https://github.com/senaiab/cross-platform-llm-client.git`
- Upstream/tracking branch: `fork/feature/tool-calling-agent`

## Current Completed Work

The current source state has been committed and pushed through commit:

- `d8c145b Add copy action to chat messages`

Recent relevant commits:

- `d8c145b Add copy action to chat messages`
- `8aa4971 Use stable release signing for Android builds`
- `fb41501 Retry transient cloud API disconnects`
- `5be1575 Implement XLSX tool handling`
- `c2df448 Implement weather and location tools`

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

- Commit: `d8c145b6e3affd3a55ff9a26591a7451b86c5e50`
- GitHub Actions run: `https://github.com/senaiab/cross-platform-llm-client/actions/runs/28465189557`
- Artifact: `privatelm-tool-calling-arm64-apk`

APK copied to:

- `/storage/emulated/0/Download/privatelm-tool-calling-arm64-release.apk`
- `/data/data/com.termux/files/home/privatelm-tool-calling-arm64-release.apk`

APK details:

- Size: `94,557,520` bytes
- SHA-256: `c2d6a7c9ef1caec57ba1180e7bba947539ddb3a67a62f69d900f0650526816e6`
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

