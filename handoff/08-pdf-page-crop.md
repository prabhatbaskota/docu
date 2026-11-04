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
