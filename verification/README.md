These tests import the actual mobile/desktop core files. This small Flutter
package deliberately excludes OpenCV and ML Kit, so persistence, database,
search and PDF merge regressions can run without Visual Studio's C++ compiler.
It does not verify native edge detection, the camera, ML Kit, or Tesseract.
The cleanup tests also import both apps' real cleanup implementation and verify
draft protection, age limits, external-file preservation and corrupt manifests.

Run from this directory:

```powershell
flutter pub get
flutter test
```

The full app suites in `mobile/test` and `desktop/test` also contain these
regressions. They additionally need the native OpenCV build toolchain.
