[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Version)

$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+$') { throw 'Version must be vMAJOR.MINOR.PATCH.' }
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$pubspecVersion = (Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+.*)?$').Matches.Groups[1].Value
if ($pubspecVersion -ne $Version.Substring(1)) { throw "Tag $Version does not match pubspec version $pubspecVersion." }
$bundle = Join-Path $root 'build\windows\x64\runner\Release'
$release = Join-Path $root 'release'
$exe = Join-Path $bundle 'docapp.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'Missing docapp.exe' }
if (-not (Test-Path -LiteralPath (Join-Path $bundle 'flutter_windows.dll') -PathType Leaf)) { throw 'Missing Flutter runtime' }
if (-not (Test-Path -LiteralPath (Join-Path $bundle 'data') -PathType Container)) { throw 'Missing Flutter data' }
$pdfium = @(Get-ChildItem -LiteralPath $bundle -Filter pdfium.dll -Recurse -File)
if ($pdfium.Count -ne 1) { throw "Expected one bundled pdfium.dll, found $($pdfium.Count)." }
$expectedPdfium = '019b6ee6e54e5508002e43c5199b00f6caca26d32dd23c7bb229ff6855cd5394'
if ((Get-FileHash -LiteralPath $pdfium[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedPdfium) {
  throw 'Bundled PDFium differs from the reviewed SHA-256 pin.'
}
# pdfium_dart does not hash its own download. Verify the exact upstream archive
# digest published on the chromium/7811 release, then compare its DLL to ours.
$verifyDir = Join-Path $env:RUNNER_TEMP ("docu-pdfium-" + [Guid]::NewGuid().ToString('N'))
$tempRoot = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\')
$verifyDir = [IO.Path]::GetFullPath($verifyDir)
if ([IO.Path]::GetDirectoryName($verifyDir) -ne $tempRoot) { throw 'Unexpected PDFium verification path.' }
New-Item -ItemType Directory -Path $verifyDir | Out-Null
try {
  $archive = Join-Path $verifyDir 'pdfium-win-x64.tgz'
  Invoke-WebRequest -Uri 'https://github.com/bblanchon/pdfium-binaries/releases/download/chromium%2F7811/pdfium-win-x64.tgz' -OutFile $archive
  $expectedArchive = '2e7af12674ac3716cb0e20369bb9fb269ceadfa2f0b0597097a520e6834175a0'
  if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedArchive) {
    throw 'PDFium upstream archive SHA-256 mismatch.'
  }
  & tar.exe -xzf $archive -C $verifyDir bin/pdfium.dll
  if ($LASTEXITCODE -ne 0) { throw 'Could not extract PDFium archive.' }
  $upstreamDll = Join-Path $verifyDir 'bin\pdfium.dll'
  if ((Get-FileHash -LiteralPath $upstreamDll -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedPdfium) {
    throw 'Bundled PDFium differs from DLL in verified upstream archive.'
  }
} finally {
  Remove-Item -LiteralPath $verifyDir -Recurse -Force
}
New-Item -ItemType Directory -Path $release -Force | Out-Null
if (Get-ChildItem -LiteralPath $release -Force) { throw 'Release directory must be empty.' }

if (-not [Environment]::Is64BitProcess) { throw 'Packaging requires 64-bit PowerShell.' }
$crt = Join-Path $env:WINDIR 'System32'
foreach ($name in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
  $source = Join-Path $crt $name
  if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Required VC runtime DLL missing: $source" }
  Copy-Item -LiteralPath $source -Destination (Join-Path $bundle $name)
}

$pfx = $null
try {
  if ($env:DOCU_SIGNING_PFX_BASE64 -or $env:DOCU_SIGNING_PFX_PASSWORD) {
    if (-not $env:DOCU_SIGNING_PFX_BASE64 -or -not $env:DOCU_SIGNING_PFX_PASSWORD) {
      throw 'Both signing secrets are required.'
    }
    $pfx = Join-Path $env:RUNNER_TEMP 'docu-signing.pfx'
    [IO.File]::WriteAllBytes($pfx, [Convert]::FromBase64String($env:DOCU_SIGNING_PFX_BASE64))
    $signTool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Filter signtool.exe -Recurse -File |
      Where-Object { $_.FullName -match '\\x64\\' } | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
    if (-not $signTool) { throw 'Windows SDK signtool.exe not found.' }
    & $signTool sign /fd SHA256 /f $pfx /p $env:DOCU_SIGNING_PFX_PASSWORD /tr http://timestamp.digicert.com /td SHA256 $exe
    if ($LASTEXITCODE -ne 0) { throw 'App signing failed.' }
    & $signTool verify /pa /v $exe
    if ($LASTEXITCODE -ne 0) { throw 'App signature verification failed.' }
  }

  $zip = Join-Path $release 'docu-windows-x64.zip'
  Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $zip
  $iscc = Join-Path "${env:ProgramFiles(x86)}" 'Inno Setup 6\ISCC.exe'
  if (-not (Test-Path -LiteralPath $iscc)) { throw 'ISCC.exe not found.' }
  & $iscc "/DMyAppVersion=$($Version.Substring(1))" (Join-Path $PSScriptRoot 'docu.iss')
  if ($LASTEXITCODE -ne 0) { throw 'Installer build failed.' }
  $installer = Join-Path $release 'docu-windows-x64-setup.exe'
  if (-not (Test-Path -LiteralPath $installer)) { throw 'Installer missing.' }
  if ($pfx) {
    & $signTool sign /fd SHA256 /f $pfx /p $env:DOCU_SIGNING_PFX_PASSWORD /tr http://timestamp.digicert.com /td SHA256 $installer
    if ($LASTEXITCODE -ne 0) { throw 'Installer signing failed.' }
    & $signTool verify /pa /v $installer
    if ($LASTEXITCODE -ne 0) { throw 'Installer signature verification failed.' }
  }
  $files = Get-ChildItem -LiteralPath $release -File | Sort-Object Name
  $lines = foreach ($file in $files) { '{0}  {1}' -f (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $file.Name }
  [IO.File]::WriteAllLines((Join-Path $release 'SHA256SUMS.txt'), $lines, [Text.UTF8Encoding]::new($false))
} finally {
  if ($pfx -and (Test-Path -LiteralPath $pfx)) { Remove-Item -LiteralPath $pfx -Force }
}
