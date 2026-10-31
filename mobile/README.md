# docu mobile

Local-first Android and iOS document scanner and PDF toolkit. No accounts, ads or analytics.

## Features

- Manual camera capture with stable live outlines, perspective correction, sequential review and durable draft recovery
- ID/card front and back on one A4 page at physical ID-1 or passport size
- Page editing, reorder, replace/insert, merge, favorites, folders and search
- Optimal or target-size compression with cancellation and preserved originals
- Offline English/Devanagari OCR, full-text search, text export and searchable PDF export

## Setup

Use Flutter 3.38+ (Dart 3.10+). Run from mobile/:

```powershell
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run
```

Native OpenCV builds require the platform compiler toolchain. On Android install
the Android SDK, NDK, CMake and Ninja. Android minSdk is 24.

## Export a local Android APK

Follow [the build handoff](../scripts/ANDROID-BUILD.md). After resolving mobile
dependencies, run from the repository root on Windows:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-android-apk.ps1
```

The helper exposes the SDK/NDK to OpenCV's native hook, verifies the APK signature
and exports the universal debug APK and checksum to release/ at the repository root.
For Google Play builds, configure your package ID and upload key as described in
[PLAY_RELEASE.md](PLAY_RELEASE.md), then run flutter build apk --release.

## iOS

Requires a Mac, Xcode 15.3+, CocoaPods and iOS 15.5+. After flutter pub get, run
pod install in ios/, then build with Flutter. The Podfile adds the Devanagari
recognition model alongside the wrapper's Latin model. Native iOS build testing
has not been completed.

## Validation and limits

See [the feature handoff](../handoff/README.md) for test results and manual checks.
Camera behavior, recognition accuracy and physical print dimensions need device
verification. JPEG compression rasterizes selectable source text. At startup,
unreferenced scan JPEGs older than seven days are removed; active drafts are retained.