[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
foreach ($required in @('.git\HEAD', '.git-backup-pdf_merger-20261016\HEAD',
    'mobile\pubspec.yaml', 'desktop\pubspec.yaml', 'streamlit\app.py',
    'release\DOCU-Android-universal-v0.1.2-navigation-debug.apk')) {
  if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $required))) {
    throw "Expected repository file is missing: $required"
  }
}
if (Test-Path -LiteralPath (Join-Path $repoRoot 'pdf_merger\.git')) {
  throw 'The old nested Git repository is still present.'
}

# Check every remaining source file in the old root mobile tree before removing it.
foreach ($directory in @('android', 'assets', 'ios', 'lib', 'test')) {
  $old = Join-Path $repoRoot $directory
  $current = Join-Path $repoRoot "mobile\$directory"
  foreach ($file in @(Get-ChildItem -LiteralPath $old -Recurse -File)) {
    $relative = $file.FullName.Substring($old.Length).TrimStart('\')
    if ($directory -eq 'android' -and
        ($relative -eq '.gitignore' -or $relative -eq 'local.properties' -or
         $relative -like '.gradle\*' -or $relative -like '.kotlin\*' -or
         $relative -like 'build\*' -or $relative -like '*.log')) { continue }
    $newFile = Join-Path $current $relative
    if (-not (Test-Path -LiteralPath $newFile) -or
        (Get-FileHash -LiteralPath $file.FullName).Hash -ne
        (Get-FileHash -LiteralPath $newFile).Hash) {
      throw "Old mobile source differs from mobile/: $directory\$relative"
    }
  }
}
foreach ($name in @('.metadata', 'PLAY_RELEASE.md', 'analysis_options.yaml',
    'flutter_launcher_icons.yaml', 'pubspec.lock', 'pubspec.yaml', 'setup.ps1')) {
  $old = Join-Path $repoRoot $name
  $current = Join-Path $repoRoot "mobile\$name"
  if ((Get-FileHash -LiteralPath $old).Hash -ne
      (Get-FileHash -LiteralPath $current).Hash) {
    throw "Old mobile file differs from mobile/: $name"
  }
}

$obsolete = @(
  'android', 'assets', 'ios', 'lib', 'test', 'packaging',
  '.android', '.android-home', '.apk-assets', '.appdata', '.build', '.dart_tool',
  '.flutter_sdk', '.flutter_sdk2', '.flutter_sdk3', '.flutter_state',
  '.gradle-build', '.gradle-clean', '.gradle-final', '.gradle-local',
  '.gradle-local2', '.java-home', '.localappdata', '.local_build', 'build',
  'pdf_merger', '.metadata', 'PLAY_RELEASE.md', 'analysis_options.yaml',
  'flutter_launcher_icons.yaml', 'pubspec.lock', 'pubspec.yaml', 'setup.ps1',
  'docu_full.zip', 'assemble-attempt.log', 'build-attempt.log',
  'gradle-error.txt', 'gradle-offline.log', 'repair-gradle-cache.ps1',
  'release\DOCU-Android-universal-v0.1.2-debug.apk',
  'release\DOCU-Android-universal-v0.1.2-debug.apk.sha256',
  'release\DOCU-Android-universal-v0.1.2-navigation-debug.apk.idsig'
)
foreach ($relative in $obsolete) {
  $target = [IO.Path]::GetFullPath((Join-Path $repoRoot $relative))
  if (-not $target.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Cleanup target is outside the repository: $relative"
  }
  if ((Test-Path -LiteralPath $target) -and $PSCmdlet.ShouldProcess($target, 'Remove obsolete local copy')) {
    Remove-Item -LiteralPath $target -Recurse -Force
  }
}
