# docu desktop

Local-first Windows PDF library and editor. No accounts, ads or analytics.

## Features

- Local library folders, Recent Files, favorites, search, sorting and multi-selection
- Photo import with page detection, perspective correction, sequential review and draft recovery
- ID/card front and back on one A4 page at physical ID-1 or passport size
- Page editing, reorder, replace/insert, merge and image-to-PDF conversion
- Optimal or target-size compression with cancellation and preserved originals
- Offline OCR, full-text search, text export and searchable PDF export

Library folders are categories inside the app. Deleting a folder moves its PDFs
to Unfiled; underlying PDFs stay in the app's document directory.

## Build

Install Flutter 3.38+ (Dart 3.10+) and Visual Studio with the Desktop development
with C++ workload. Run from desktop/:

```powershell
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build windows --release --no-pub
```

Distribute the complete build/windows/x64/runner/Release folder. The repository
Windows workflow builds desktop/ when a version tag is pushed. See the
[Windows release audit](WINDOWS_RELEASE_AUDIT.md) and [product audit](DOCU_PRODUCT_AUDIT.md)
before publishing an installer.

## OCR

Install Tesseract separately with eng, hin and nep language data, then select its
executable in Settings. No recognition models or Tesseract binaries are downloaded
at runtime. ML Kit is used by the separate [mobile app](../mobile/README.md).

## Validation and limits

See [the feature handoff](../handoff/README.md) for test results and manual checks.
Photo import is supported; live Windows webcam capture is not implemented. Native
OpenCV tests/builds require the C++ toolchain. JPEG compression rasterizes selectable
source text. Unreferenced scan JPEGs older than seven days are cleaned at startup;
active drafts are retained. Rebuild the Windows app/installer for the updated icons.