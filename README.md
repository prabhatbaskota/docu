# PDF Worker and docu Desktop

This repository contains three separate applications: the original Streamlit
PDF Worker (`app.py`), the released Windows Flutter app in [`desktop/`](desktop/),
and the Android/iOS Flutter app in [`mobile/`](mobile/). Each Flutter app has its
own dependencies and build instructions. The Streamlit app remains separate.

## Windows desktop app

docu Desktop stores PDFs on the PC. It can read PDFs, create and rename library
folders, move multiple PDFs between folders, search, sort, edit pages, merge,
compress, convert images to PDF, and export PDFs. Deleting a folder moves its
documents to Unfiled. Library folders are categories in the app; the PDF files
remain in its local document store. No account or cloud service is required.

Download the latest Windows installer from
[GitHub Releases](https://github.com/prabhatbaskota/pdf-merger/releases/latest).
The installer must be downloaded and run
on the Windows PC. A link opened on a phone cannot install it on a separate PC.

To build from source, use the commands in [desktop/README.md](desktop/README.md).
For release checks and candidate verification, see [WINDOWS_RELEASE_AUDIT.md](WINDOWS_RELEASE_AUDIT.md).

## Mobile app

The mobile app opens on Scan and has Home, Tools, and Favorites navigation.
It scans pages, imports PDFs, edits and merges pages, compresses copies, and
creates PDFs from images. Build instructions and known limitations are in
[mobile/README.md](mobile/README.md). Mobile builds and APKs are separate from
the Windows installer and are not committed to Git.
