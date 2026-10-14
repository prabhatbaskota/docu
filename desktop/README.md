# docu

Local-first document scanner and PDF toolkit (Flutter). No accounts, ads or analytics.

## Desktop edition

The Windows app opens on a desktop library with local folders. Create, rename,
and delete folders; import PDFs into a folder; select and move multiple PDFs;
search, sort, read, edit pages, merge, compress, convert images to PDF, and
export a PDF. Deleting a folder moves its PDFs to Unfiled. Library folders are
categories inside the app; the underlying PDF files stay in the app's local
document directory. No account or cloud service is required.

For a Windows build, install Flutter and Visual Studio with the Desktop
development with C++ workload, then run:

```powershell
flutter clean
flutter create --platforms=windows --project-name docapp --no-pub .
flutter pub get --enforce-lockfile
flutter test
flutter build windows --release --no-pub
```

The app bundle is at `build/windows/x64/runner/Release`. Distribute the full
folder, not just `docapp.exe`. The GitHub Actions workflow builds a release
candidate when run manually or when a `v*` tag is pushed. Follow the
[Windows release audit](../WINDOWS_RELEASE_AUDIT.md) before publishing its ZIP
and installer to GitHub Releases. Users download the installer on their Windows
PC. A mobile app can
provide a link to the release, but opening that link on a phone cannot install
the app on a PC.

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

The Gradle settings limit build memory and disable Kotlin incremental compilation to avoid Windows cache failures when the project and Pub cache are on different drives. Release builds currently use the debug signing key; configure your own release key before publishing.

## Structure
- `lib/core` PDF engine (everything is `assemble(List<PageRef>)`; `compress` re-renders pages as JPEG), progress, toast, image tools
- `lib/features` documents (Home/Favorites/selection), scan, page editor, compress, branding, settings

## Known limits
- Compression turns pages into images (text no longer selectable)
- No automatic edge detection / perspective correction yet (OpenCV is the planned step)
