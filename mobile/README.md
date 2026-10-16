# docu

Local-first Android and iOS document scanner and PDF toolkit (Flutter). No
accounts, ads, or analytics. Run the commands below from this `mobile/` directory.
The released Windows app is maintained separately in [`../desktop/`](../desktop/).

## Features
- Scan (single / multiple, manual capture, batch review, crop, rotate) or auto-detect via Google scanner
- Page editor: big thumbnails, drag-reorder, replace / insert pages, colour + letter per source PDF
- Merge, "Compress and merge", standalone Compress (always saves a copy)
- Photos to PDF, import, share, favorites, search, Today / Yesterday / date grouping

## Setup (easy: run .\setup.ps1)
```
flutter pub add flutter_riverpod sqflite camera image flutter_reorderable_grid_view
flutter pub add --dev flutter_launcher_icons sqflite_common_ffi
dart run flutter_launcher_icons
flutter test
flutter run
```
Android: `android:label="docu"` in AndroidManifest.xml, CAMERA permission, minSdk 24+.
iOS (needs a Mac): `CFBundleDisplayName` = docu, `NSCameraUsageDescription`.

## Build an Android APK
First configure the package ID and upload key in [PLAY_RELEASE.md](PLAY_RELEASE.md).

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```
The APK is written to `build/app/outputs/flutter-apk/app-release.apk`.
The first build needs internet access to download Android dependencies and PDFium native libraries from GitHub.

For an ARM64-only APK:
```powershell
flutter build apk --release --target-platform android-arm64 --split-per-abi
```
This produces `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.

The Gradle settings limit build memory and disable Kotlin incremental compilation to avoid Windows cache failures when the project and Pub cache are on different drives. Google Play release builds require your permanent package ID and upload key; see [PLAY_RELEASE.md](PLAY_RELEASE.md).

## Structure
- `lib/core` PDF engine (everything is `assemble(List<PageRef>)`; `compress` re-renders pages as JPEG), progress, toast, image tools
- `lib/features` documents (Home/Favorites/selection), scan, page editor, compress, branding, settings

## Known limits
- Compression turns pages into images (text no longer selectable)
- No automatic edge detection / perspective correction yet (OpenCV is the planned step)
