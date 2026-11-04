# docu feature handoff

The changes are applied to `mobile/` and `desktop/`. Existing Home, Favorites,
merge/split, Recent Files, folder handling, and page editing were extended.
The root app is the old copy and was not updated.

Complete, copy-pasteable final files are grouped below. They reference one
another: apply the complete ZIP when transferring these changes elsewhere.

- [1. Live edge detection: complete files](01-live-edges.md)
- [2. Sequential correction: complete files](02-sequential-correction.md)
- [3. ID/card: complete files](03-id-card.md)
- [4. Compression: complete files](04-compression.md)
- [5. OCR: complete files](05-ocr.md)
- [Desktop document icon: complete files](06-desktop-icon.md)
- [Pubspec, Android Gradle, and manifest: complete files](07-configuration.md)
- [All source files and assets in a ZIP](docu-feature-updates.zip)
- [Exact resolved packages, versions, and license notices](DEPENDENCIES.md)
- [PDF page cropping and Windows icon integration](08-pdf-page-crop.md)
- [Bundle file list](FILES.txt)

## Build and validation

**2026-11-04 update:** the Android universal preview APK was successfully built,
its APK v2 signature and SHA-256 were verified, and it was copied to the connected
phone's Downloads folder. It includes the new PDF page crop feature. Both apps
passed analysis, all 20 portable regressions passed on Windows and Linux, and
the [Windows candidate build](https://github.com/prabhatbaskota/docu/actions/runs/41919720066)
passed all 39 desktop tests and generated the installer and ZIP. The crop screen,
Windows app/document/installer icons, test setup, and build instructions are
included in the refreshed source bundle. Older dated build blockers below are
historical; physical camera and installed desktop runtime checks remain manual.

Use Flutter 3.38 or newer (Dart 3.10+). OpenCV 2.2.2 uses native build hooks.
Its modules are limited to imgproc and imgcodecs and two build workers.
Android builds need the Android NDK, CMake and Ninja; on this machine CMake
is at `C:\Android\cmake\3.22.1\bin`. Add that directory to PATH if necessary.
Windows builds/tests with OpenCV require Visual Studio C++ desktop tooling.

From each application directory:

```powershell
flutter pub get
flutter analyze
flutter test
```

The portable `verification/` Flutter package imports the real mobile/desktop
core source and excludes OpenCV/ML Kit. Run `flutter test` there for database,
OCR search, draft recovery, merge, and Unicode PDF export checks. Fourteen
tests passed, including real PDF merge order and extraction of `नेपाल` from
the invisible layer by PDFium. That verifies PDF text extraction, not native
camera behavior or recognition accuracy.

On 2026-10-31, mobile and desktop `flutter analyze --no-pub` both passed
with no issues. All fourteen existing portable tests and four new scan cleanup
tests passed (eighteen tests total across the two test runs).

The full native app test run was blocked by the missing Windows C++/CMake
toolchain. The Android APK build reached OpenCV native compiler feature checks after SDK/NDK discovery was fixed. It was stopped at the user's request to continue on another machine. No new APK was exported. Follow [the Android build handoff](../scripts/ANDROID-BUILD.md) and run `scripts/build-android-apk.ps1` from the repository root on Windows. The helper exposes the SDK/NDK to OpenCV, verifies the debug APK signature and exports the APK with its SHA-256 checksum. Gradle uses a 1.5 GB heap and one worker; editor indexing caused heavy memory paging on the original machine.
No physical phone, Windows installer, or iOS runtime was tested.

## Physical Android test steps, by feature

1. **Live edges:** run `flutter run` from `mobile/`, allow Camera, and hold
   an A4 sheet over a contrasting background. Check that an outline appears
   only after several stable frames, follows the page, and disappears when
   the page is removed. Nothing should capture until you tap the shutter.
   Test portrait camera sensors with both 90° and 270° orientation if available.
   Capture an angled page, check initial corners, then confirm and inspect
   straight edges. Repeat without a detectable page to verify margin fallback.

2. **Multiple pages:** capture five pages without a crop screen between shots.
   Tap Done. Check Page 1 of 5, Next, the last-page Done, progress, Back,
   Skip, Reset, rotation, and the dragging magnifier. Back must retain edits.
   Confirm every page, inspect the large batch thumbnails, reorder and save.
   Background during capture, correction and review. Kill/reopen the app and
   choose Resume; confirm all pages are present. Also test low free storage
   and camera permission denial. Merge two saved scans and check every page.

3. **ID/card:** choose ID / Card, capture front, correct it, capture back and
   correct it. Retake each side independently. Try ID-1 and passport sizes.
   Save and inspect a single A4 page. Print at **Actual size / 100%** and
   measure 85.60 × 53.98 mm or 125 × 88 mm, 20 mm margins and 12 mm gap.
   Check that an unfinished document batch survives using card mode.

4. **Compression:** try Optimal and Target size on a large scanned PDF, both
   standalone and through Compress and merge. Compare sizes and legibility.
   Try KB and MB, invalid/zero input, a target above the current size, an
   impossible tiny target, and Cancel during processing. Verify the original
   still exists and the new exported name ends `_compressed.pdf`.

5. **OCR:** enable airplane mode, select English, Devanagari and Auto in
   Settings, then scan English, Nepali and Hindi pages. Saving should finish
   before recognition; the file should show Reading text… then Text ready.
   Search an interior word from Home and inspect its snippet. Open Text,
   select a page, copy text, share `.txt`, and accept a suggested name.
   Export searchable PDF. Open it in Adobe Acrobat, Google Drive PDF viewer,
   or another standard reader; search and copy both an English word and a
   Nepali word. Check spelling, character order, and word selection positions.

No AndroidManifest permission was added. CAMERA already existed. Files stay
in app-private storage, and file pickers use platform document access; broad
storage permission is unnecessary on Android 15. The new recognition models
are bundled via Android Gradle dependencies and need no document upload.

## Desktop checks and limits

Use **Scan photos / ID** to import photos for perspective correction; Windows
live webcam capture is not provided. Existing Recent Files and folder merge
behavior are retained. Test compression and OCR search in both library views.

ML Kit has no Windows implementation. Desktop OCR uses a local Tesseract
executable (Apache-2.0), installed separately with `eng`, `hin` and `nep`
language data. Choose its executable in Settings, or use a normal installation
at `C:\Program Files\Tesseract-OCR\tesseract.exe`. Recognition fails with an
actionable message when the executable or language data is missing. No
Tesseract binary or language downloads occur at runtime.

Rebuild/install the Windows application to get the regenerated docu executable
icon and dedicated document icon. Choose docu as the PDF default in Windows
Settings to see its file icon. The installer points `docu.PDF\DefaultIcon` at
the bundled `document_icon.ico`; it does not forcibly change the user's default.
Explorer may retain an old icon until its cache refreshes or you sign in again.

Recognition runs asynchronously while the process is alive. If the OS kills
the process, queued jobs resume on the next launch. Auto chooses a script per
page; it is not general language identification. Very small compression
targets can take multiple rendering passes, and cancellation is cooperative
between processing steps. JPEG compression rasterizes selectable source text.
Flattened scan output is limited to a 3000-pixel longest edge with preserved
aspect ratio; initial corners are mapped against the full normalized photo.
At startup, unreferenced JPEGs in app-private `scan_pages` storage older than
seven days are deleted. Images referenced by document, card, or pending card-side
drafts (including pending manifest writes) are preserved regardless of age.
Unreadable draft data prevents cleanup so recovery images are retained.
Four portable cleanup regression tests passed for mobile and desktop.
The Windows build was retried on 2026-10-31 and remains blocked by the missing
Visual Studio C++ toolchain. Camera, memory use, and native builds still
need device verification. iOS now includes CocoaPods integration, the bundled Devanagari model, 32-bit architecture exclusions and the iOS 15.5 minimum required by the installed ML Kit wrapper. Its Xcode/CocoaPods build still needs a Mac.

ML Kit is the expressly approved proprietary exception to the open-source
requirement. Its Flutter wrapper is MIT; Google's underlying SDK is free and
on-device but is not open source. Noto fonts are bundled under SIL OFL-1.1.
