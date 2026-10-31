# Move the whole project to another computer

## Clone the complete project

```powershell
git clone --branch repo-reorganization https://github.com/prabhatbaskota/docu.git
cd docu
```

This clones the complete repository and checks out the saved work. It includes
mobile, desktop, Streamlit, assets/fonts, native platform projects, Gradle wrapper,
dependency manifests/Flutter lockfiles, packaging scripts, CI workflows, tests,
licenses and the feature handoff. It is not a single-branch clone.

The maintained Flutter applications are in `mobile/` and `desktop/`. Run Flutter
from those folders, not the repository root. The ignored root Flutter tree is an
older duplicate. Its extra mobile regression tests are preserved in `verification/`.
The old local `main` history is already an ancestor of the saved feature branch.

## Install development tools on the new machine

SDK installations and package caches are downloaded again; they are not source files.

| Component | Tools needed |
| --- | --- |
| Flutter apps | Flutter, including its bundled Dart SDK. This work was analyzed with Flutter 3.47.2 / Dart 3.13.2. |
| Android | Java 17, Android SDK platform/build-tools 36, Flutter's requested NDK, Android SDK CMake and Ninja. The original machine used NDK 28.2.13676358 and CMake 3.22.1. |
| Windows desktop | Visual Studio with Desktop development with C++, Windows SDK, CMake and Ninja. |
| Desktop OCR | Separately installed Tesseract with `eng`, `hin` and `nep` language data; choose its executable in the app Settings. |
| Windows installer | Inno Setup, if you want to package an installer in addition to the Flutter application folder. |
| Streamlit app | Python and pip; application dependencies are in `requirements.txt`. |
| iOS | A Mac, Xcode 15.3+, CocoaPods and iOS 15.5+. |

Run `flutter doctor -v` to check the installed Flutter toolchains.

## Restore application dependencies

From the repository root:

```powershell
Set-Location mobile
flutter pub get --enforce-lockfile
Set-Location ../desktop
flutter pub get --enforce-lockfile
Set-Location ../verification
flutter pub get --enforce-lockfile
flutter test
Set-Location ..
```

For the Python app, from the repository root:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m streamlit run streamlit/app.py
```

The root requirements file installs Streamlit's dependencies. It does not install
Flutter, Android, Visual Studio or other system SDKs. The Python requirements list
direct dependencies; unlike the Flutter lockfiles, it is not an exact environment lock.

## Build and run

Android, from the repository root after resolving mobile dependencies:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-android-apk.ps1 -PrepareOnly
powershell -ExecutionPolicy Bypass -File scripts/build-android-apk.ps1
```

Set `ANDROID_HOME` to the Android SDK installation if the helper cannot discover it
from your local Flutter-generated configuration. See [Android build details](scripts/ANDROID-BUILD.md).
Successful builds are exported with a checksum to `release/`.

Windows desktop, from `desktop/`:

```powershell
flutter analyze
flutter test
flutter build windows --release --no-pub
```

The complete application folder is `desktop/build/windows/x64/runner/Release`.
For iOS, resolve mobile dependencies, run `pod install` from `mobile/ios/`, then
build from `mobile/` on the Mac. See the app READMEs for more details.

## Transfer separately before deleting the old copy

Git intentionally excludes signing keys, private credentials, installed SDKs,
caches, generated build files and old APK/installer outputs.

- Preserve any Android signing keystore and its passwords privately. A project-local
  debug key was found at `.local_build/home/.android/debug.keystore`; a private
  backup is saved outside the project at `~/docu-migration-private-20261031/`.
  Copy that private folder to the new computer as well if you need the same signing
  identity. Read its README before restoring a key. Never commit signing keys.
- Public release signing configuration is described in `mobile/PLAY_RELEASE.md`.
  Account credentials and repository-hosted CI secrets must be configured separately.
- Existing app libraries (PDFs, database, favorites and settings) are runtime data,
  not source code. Export/back up them separately if you want to migrate app data.
- Old APKs/installers under `release/` and `desktop/release/` are not in the source
  clone. Keep separate copies if you need those exact historical binaries.

Before removing the old project folder, confirm that the new clone is on
`repo-reorganization`, the private backup is transferred, dependencies resolve,
and the applications you need build/run on the new machine. The local cleanup
script is a historical migration tool, not a required setup or deletion step.

## Saved validation and unfinished native work

Mobile and desktop analysis passed. Fourteen core regression tests plus four scan
cleanup tests passed. The Android SDK/NDK lookup failure was fixed; the build was
stopped during OpenCV native compiler checks so it could be continued elsewhere.
No new feature APK was exported. Windows native builds require the C++ toolchain;
iOS builds and camera/recognition/physical-size checks still need platform testing.
Full details are in [handoff/README.md](handoff/README.md).
