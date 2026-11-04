# PDF page cropping

Mobile and desktop PDF editors now offer **Crop** when exactly one page is
selected. Drag across the page preview to choose a rectangle to keep, then
choose **Apply**. **Reset** restores the full-page selection; Back cancels.
The editor updates its thumbnail and offers **Undo**. Save or Extract includes
the cropped page alongside the other pages in their current order. The source
PDF stays unchanged until the existing explicit Replace original save option
is used.

The retained rectangle is rendered as a lossless PNG in a new single-page PDF.
Only the selected image area is embedded; excluded source objects are not
copied. Page dimensions match the retained region. Resolution is bounded at
300 DPI and a 4000-pixel full-page longest edge. Cropped pages lose selectable
text, links, and interactive forms; the crop screen explains this before Apply.
Other pages use the existing PDF assembly path and keep their content.
Editor-owned temporary crop PDFs are removed when the editor closes.

Regression tests in `verification/test/pdf_crop_test.dart` cover both engines:
output dimensions, retained blue pixels with the red region excluded, assembly
with an untouched page, source preservation, and invalid crop rejection.

Windows already has branded app and PDF document ICO files. The installer now
also uses the app ICO and displays the installed executable icon in the
uninstall entry. Windows shows the registered document icon when the user
selects docu as the default PDF application; the installer does not override
that preference.

## Build results (2026-11-04)

- Android universal debug APK: `release/DOCU-Android-universal-v0.1.2-features-debug.apk`.
  Android build-tools verified its signature. The local and phone copies have
  SHA-256 `94ac31e0a3861ff59e812e47a8a1a7ebf015a4a9ded4d050bbb6c0d8a223d1c8`.
- Windows installer and portable ZIP: built by
  [run 41919720066](https://github.com/prabhatbaskota/docu/actions/runs/41919720066)
  from commit `aaf91d3`, including the crop feature and branded icon generation.
  Downloaded artifacts are stored in `release/windows-pdf-page-crop/`.
  Their SHA-256 values match `SHA256SUMS.txt`. The installer hash is
  `776c4c521931119b7d78422b761a07170db2aee669ec97b10bb375907d639abe`.
  The application and installer contain the branded app icon; the portable ZIP
  also contains the exact dedicated document icon. The installer is unsigned.
- Both apps passed analysis. All 20 portable tests passed on Windows and Linux;
  all 39 desktop application tests passed on the Windows build runner.

The Android preview is debug-signed. Physical camera behavior and installation
on a clean Windows machine were not tested by these automated checks.
