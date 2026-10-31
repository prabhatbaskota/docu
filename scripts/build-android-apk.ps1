[CmdletBinding()]
param([switch]$PrepareOnly)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$mobileRoot = Join-Path $projectRoot 'mobile'
$localProperties = @{}
$propertiesFile = Join-Path $mobileRoot 'android/local.properties'
if (Test-Path -LiteralPath $propertiesFile) {
    foreach ($line in Get-Content -LiteralPath $propertiesFile) {
        if ($line -match '^([^#=]+)=(.*)$') {
            $localProperties[$matches[1]] = $matches[2].Replace('\\', '\').Replace('\:', ':')
        }
    }
}
function Get-LatestSdkDirectory([string]$ParentDirectory) {
    $directory = Get-ChildItem -LiteralPath $ParentDirectory -Directory |
        Where-Object { $_.Name -match '^\d+(\.\d+)+$' } |
        Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    if (-not $directory) { throw "No installed tools found in $ParentDirectory" }
    return $directory.FullName
}
$sdkRoot = $env:ANDROID_HOME
if (-not $sdkRoot) { $sdkRoot = $env:ANDROID_SDK_ROOT }
if (-not $sdkRoot) { $sdkRoot = $localProperties['sdk.dir'] }
if (-not $sdkRoot -or -not (Test-Path -LiteralPath $sdkRoot -PathType Container)) {
    throw 'Set ANDROID_HOME or sdk.dir in mobile/android/local.properties to the installed Android SDK.'
}
$sdkRoot = (Resolve-Path -LiteralPath $sdkRoot).Path
$ndkRoot = $env:ANDROID_NDK_HOME
if (-not $ndkRoot) { $ndkRoot = Get-LatestSdkDirectory (Join-Path $sdkRoot 'ndk') }
$cmakeBin = Join-Path (Get-LatestSdkDirectory (Join-Path $sdkRoot 'cmake')) 'bin'
$buildTools = Get-LatestSdkDirectory (Join-Path $sdkRoot 'build-tools')
foreach ($tool in @((Join-Path $ndkRoot 'build/cmake/android.toolchain.cmake'),
                    (Join-Path $cmakeBin 'cmake.exe'), (Join-Path $cmakeBin 'ninja.exe'),
                    (Join-Path $buildTools 'apksigner.bat'))) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Required Android tool is missing: $tool" }
}
$flutter = (Get-Command flutter -ErrorAction Stop).Source
if ($PrepareOnly) {
    [pscustomobject]@{ AndroidSdk = $sdkRoot; AndroidNdk = $ndkRoot; CMake = $cmakeBin; BuildTools = $buildTools; Flutter = $flutter }
    return
}
$previousEnvironment = @{}
foreach ($name in @('ANDROID_HOME', 'ANDROID_SDK_ROOT', 'ANDROID_NDK_HOME', 'PATH')) {
    $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$previousLocation = Get-Location
try {
    # Native Dart hooks do not read Android's local.properties.
    $env:ANDROID_HOME = $sdkRoot
    $env:ANDROID_SDK_ROOT = $sdkRoot
    $env:ANDROID_NDK_HOME = $ndkRoot
    $env:PATH = "$cmakeBin;$buildTools;$ndkRoot;$env:PATH"
    Set-Location -LiteralPath $mobileRoot
    & $flutter build apk --debug --no-pub
    if ($LASTEXITCODE -ne 0) { throw "Flutter APK build failed with exit code $LASTEXITCODE" }
    $apk = Join-Path $mobileRoot 'build/app/outputs/flutter-apk/app-debug.apk'
    if (-not (Test-Path -LiteralPath $apk -PathType Leaf)) { throw "Flutter did not create $apk" }
    & (Join-Path $buildTools 'apksigner.bat') verify --verbose $apk
    if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
    $version = [regex]::Match((Get-Content (Join-Path $mobileRoot 'pubspec.yaml') -Raw), '(?m)^version:\s*(\S+)').Groups[1].Value.Split('+')[0]
    $exportDirectory = Join-Path $projectRoot 'release'
    New-Item -ItemType Directory -Path $exportDirectory -Force | Out-Null
    $exportPath = Join-Path $exportDirectory "DOCU-Android-universal-v$version-features-debug.apk"
    Copy-Item -LiteralPath $apk -Destination $exportPath -Force
    $digest = (Get-FileHash -LiteralPath $exportPath -Algorithm SHA256).Hash.ToLowerInvariant()
    "$digest  $([IO.Path]::GetFileName($exportPath))" | Set-Content -LiteralPath "$exportPath.sha256" -Encoding Ascii
    Write-Output "Exported $exportPath"
} finally {
    Set-Location -LiteralPath $previousLocation.Path
    foreach ($name in $previousEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
    }
}