# Google Play release handoff

The Android app targets API 36 and uses an Android App Bundle. Release builds
require a permanent application ID and an upload key. The current template ID
is deliberately rejected for release builds.

1. Register a unique package name in Play Console. Put it in
   `android/gradle.properties` as `docuApplicationId=your.registered.package`.
   Keep the same ID for every future update.
2. Create an upload keystore with Android Studio's **Generate Signed Bundle / APK**
   flow, or use the upload key already registered for this app. Keep the keystore
   and passwords backed up outside the repository.
3. Create `android/key.properties` (ignored by Git):

   ```properties
   storeFile=C:/absolute/path/to/upload-key.jks
   storePassword=YOUR_STORE_PASSWORD
   keyAlias=upload
   keyPassword=YOUR_KEY_PASSWORD
   ```

4. Increase `version` in `pubspec.yaml` for each Play upload. Run:

   ```powershell
   flutter analyze
   flutter test
   flutter build appbundle --release
   ```

   Upload `build/app/outputs/bundle/release/app-release.aab` to a Play internal
   testing track first. Verify the package name, signing certificate, target
   API, scanner, file import/export, and PDF rendering on a real device.
   Inspect bundled native libraries for 16 KB page-size support in Android
   Studio's APK Analyzer or Play Console; the PDF renderer includes native code.

5. Complete the Play Console store listing and App content forms, including
   Data safety, privacy policy URL, content rating, and app access. Review
   permissions and third-party SDK behavior against the final bundle before
   submitting. Use `assets/store/icon_512.png` for the listing icon; capture
   current device screenshots and provide a feature graphic in Play Console.
   The app's files are stored locally unless the user exports or
   shares them, but the Play declarations must be based on the final build.

The desktop and mobile notices currently describe availability. They do not
claim automatic document sync; files move between devices through the existing
export/share and import flows. Add public store/download links when those URLs
are available.
