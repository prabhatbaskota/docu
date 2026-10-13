# PDF Worker and docu Desktop

This repository contains the original Streamlit PDF Worker (`app.py`) and the
local-first Flutter PDF application in [`desktop/`](desktop/). The Streamlit
application remains separate from the downloadable Windows app.

## Windows desktop app

docu Desktop stores PDFs on the PC. It can read PDFs, create and rename library
folders, move multiple PDFs between folders, search, sort, edit pages, merge,
compress, convert images to PDF, and export PDFs. Deleting a folder moves its
documents to Unfiled. Library folders are categories in the app; the PDF files
remain in its local document store. No account or cloud service is required.

Download the latest Windows installer from
[GitHub Releases](https://github.com/prabhatbaskota/pdf-merger/releases/latest)
once the first release is published. The installer must be downloaded and run
on the Windows PC. A link opened on a phone cannot install it on a separate PC.

To build from source, use the commands in [desktop/README.md](desktop/README.md).
