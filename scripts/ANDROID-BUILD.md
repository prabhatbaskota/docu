# Android APK build and export

Run these commands on a Windows machine with Flutter 3.38+ (Dart 3.10+),
Java 17, Android SDK platform/build-tools 36, the NDK requested by Flutter,
and Android SDK CMake/Ninja installed. Run Flutter commands from `mobile/`.

```powershell
Set-Location mobile
flutter pub get
Set-Location ..
powershell -File scripts/build-android-apk.ps1 -PrepareOnly
powershell -File scripts/build-android-apk.ps1
```

`-PrepareOnly` checks installed tool paths without compiling. The helper reads
`ANDROID_HOME`, `ANDROID_SDK_ROOT`, or `mobile/android/local.properties` for
the SDK. You can set `ANDROID_NDK_HOME` to choose a specific installed NDK;
otherwise it uses the newest installed numeric version. It discovers Android
SDK CMake, Ninja and build-tools, then passes the SDK/NDK paths explicitly to
Flutter's native hooks. Flutter finding the SDK from `local.properties` alone
is insufficient for OpenCV's hook on this setup.

The helper builds a universal debug APK, checks its Android signature and
exports it with a SHA-256 checksum to:

```text
release/DOCU-Android-universal-v0.1.2-features-debug.apk
release/DOCU-Android-universal-v0.1.2-features-debug.apk.sha256
```

The version in the filename follows `mobile/pubspec.yaml`. This is a signed
local preview, not a Google Play release. Release signing and application ID
configuration are documented in `mobile/PLAY_RELEASE.md`. The helper expects
`flutter pub get` to have resolved dependencies before building.

## Current handoff state (2026-10-31)

The build was stopped at the user's request so it could be moved to another
machine. No new feature APK was exported. Existing October 16 APKs in
`release/` are older previews and do not contain the new feature work.

The initial OpenCV hook failed to find the Android SDK/NDK. Explicit SDK/NDK
environment variables fixed that failure: CMake located NDK 28.2.13676358,
Clang 19.0.1 and began configuring OpenCV 4.13.0 from source for armeabi-v7a.
The source archive downloaded and extracted successfully. The build was still
performing compiler feature checks when stopped; no subsequent native build
failure had been reported. Full APK compilation/signature verification and
physical-device checks remain to be completed on the next machine.

`mobile/android/gradle.properties` limits Gradle to one worker and a 1.5 GB
heap. Heavy concurrent Java indexing caused memory paging on the original
8 GB machine. The helper's PowerShell parsing and SDK discovery (`-PrepareOnly`)
passed; its complete build/export path awaits a successful APK build.