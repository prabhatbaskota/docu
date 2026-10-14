# Windows release audit

The old installer detected as `Trojan:Win32/Bearfoos.B!ml` is not available in this checkout. Its exact detection cannot be diagnosed from source alone. The new workflow produces a release candidate for inspection and does not publish it automatically.

## Findings

- The tracked Windows app is `desktop/`. The repository-root Streamlit `app.py` and unpinned `requirements.txt` are separate and are not included in the Windows installer.
- The Dart app handles local PDFs and images, stores its library in local SQLite and document folders, and offers file picker, camera, share, and PDF Open With features. Library deletion removes app-owned files after a soft-delete flow. Source search found no process execution, remote command client, auto-start persistence, or obfuscation. This does not prove all transitive or native code is safe.
- The Inno installer installs per-user under LocalAppData, creates shortcuts, adds per-user PDF Open With registry entries, and offers to launch the app after an interactive install. It has no custom installer code, downloader, service, or scheduled task. The unsigned, solid LZMA installer and its registry and launch behavior could contribute to a heuristic alert, but do not explain a specific verdict.
- `desktop/pubspec.lock` lists 119 hosted packages with SHA-256 content hashes from pub.dev. The old workflow used ordinary `flutter pub get`, fetched an unpinned Inno Setup package, and published directly from a tag. The new workflow enforces the lockfile, fixes action and tool versions, and requires analysis and tests before uploading a candidate.
- `pdfium_dart 0.3.1` downloads PDFium from the bblanchon `chromium/7811` release without verifying the download. The package script now checks the [published archive SHA-256](https://github.com/bblanchon/pdfium-binaries/releases/expanded_assets/chromium%2F7811), extracts its DLL, and compares that DLL with the one Flutter bundled. The local cached DLL has no Authenticode signature. Hash checks provide integrity against the pinned source, not a malware guarantee.

## Release procedure

For a candidate now, commit and push these changes to the repository's default branch, then open GitHub Actions → **Windows release candidate** → **Run workflow**. No new tag or release is needed. For an eventual release, update `desktop/pubspec.yaml` to the intended version, review the source and lockfile changes, and push a matching `vMAJOR.MINOR.PATCH` tag. The workflow checks tagged builds against the app version and uploads `docu-windows-x64.zip`, `docu-windows-x64-setup.exe`, and `SHA256SUMS.txt`. It never creates a public release. The fixed inputs improve auditability, but Windows runner and compiler updates, timestamps, compression, and signing can still prevent byte-identical rebuilds.

Optional Authenticode signing uses both repository secrets `DOCU_SIGNING_PFX_BASE64` and `DOCU_SIGNING_PFX_PASSWORD`. The script signs and verifies `docapp.exe` and the final installer. Protect who can change the workflow and release tags when these secrets are configured. The Inno uninstaller and third-party DLLs are not signed by this step.

Download the completed run's candidate and verify it on a Windows machine:

```powershell
gh run download RUN_ID -n docu-windows-release-candidate -D .\candidate
foreach ($line in Get-Content .\candidate\SHA256SUMS.txt) {
  if ($line -notmatch '^([0-9a-f]{64})  ([^\\/]+)$') { throw "Bad checksum line: $line" }
  $actual = (Get-FileHash -LiteralPath (Join-Path .\candidate $Matches[2]) -Algorithm SHA256).Hash
  if ($actual -ne $Matches[1]) { throw "Checksum mismatch: $($Matches[2])" }
}
Get-AuthenticodeSignature .\candidate\docu-windows-x64-setup.exe | Format-List Status,SignerCertificate,TimeStamperCertificate
Start-MpScan -ScanType CustomScan -ScanPath (Resolve-Path .\candidate\docu-windows-x64-setup.exe).Path
```

For signed builds, require `Valid` signature status and the expected publisher; inspect the ZIP's `docapp.exe` signature too. Inspect the installer payload and test installation and uninstallation in an isolated VM with Defender enabled. A checksum checks consistency with this candidate, not whether the file is benign. If Defender detects it, leave it unpublished and [submit that exact EXE to Microsoft](https://learn.microsoft.com/en-us/defender-xdr/submission-guide). Once review passes, publish the three candidate files using `gh release create TAG .\candidate\docu-windows-x64-setup.exe .\candidate\docu-windows-x64.zip .\candidate\SHA256SUMS.txt --verify-tag`, and recheck the public download's SHA-256.
