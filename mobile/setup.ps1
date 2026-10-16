# docu - one-shot setup. Run from this folder:  powershell -ExecutionPolicy Bypass -File .\setup.ps1
$ErrorActionPreference = "Stop"

# 1) Create the android/ios platform folders if missing (keeps lib, pubspec etc.)
if (-not (Test-Path ".\android")) {
  flutter create . --project-name docapp --org com.yourname --platforms android,ios
}

# 2) Packages the code needs
flutter pub add flutter_riverpod sqflite camera image flutter_reorderable_grid_view
flutter pub add --dev flutter_launcher_icons sqflite_common_ffi

# 3) Android: app name "docu", camera permission, minSdk 24
$m = ".\android\app\src\main\AndroidManifest.xml"
$t = [System.IO.File]::ReadAllText($m)
$t = $t -replace 'android:label="[^"]*"', 'android:label="docu"'
if ($t -notmatch 'android.permission.CAMERA') {
  $t = $t -replace '<application', "<uses-permission android:name=`"android.permission.CAMERA`" />`n    <application"
}
[System.IO.File]::WriteAllText($m, $t, (New-Object System.Text.UTF8Encoding($false)))

foreach ($g in ".\android\app\build.gradle.kts", ".\android\app\build.gradle") {
  if (Test-Path $g) {
    $b = [System.IO.File]::ReadAllText($g)
    $b = $b -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24'
    $b = $b -replace 'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 24'
    [System.IO.File]::WriteAllText($g, $b, (New-Object System.Text.UTF8Encoding($false)))
  }
}

# 4) iOS (only matters when built on a Mac)
$plist = ".\ios\Runner\Info.plist"
if (Test-Path $plist) {
  $p = [System.IO.File]::ReadAllText($plist)
  if ($p -notmatch 'NSCameraUsageDescription') {
    $p = $p -replace '</dict>\s*</plist>', "<key>NSCameraUsageDescription</key><string>docu uses the camera to scan documents.</string></dict></plist>"
    [System.IO.File]::WriteAllText($plist, $p, (New-Object System.Text.UTF8Encoding($false)))
  }
}

# 5) Icon, tests
dart run flutter_launcher_icons
flutter test

Write-Host "`nDone. Plug in the phone and run:  flutter run"
