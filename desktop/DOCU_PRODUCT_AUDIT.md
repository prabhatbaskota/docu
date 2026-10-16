# DOCU product audit and implementation plan

## Codebase

- `../mobile/` is the Flutter mobile project. This directory is the Flutter desktop project. `../streamlit/app.py` is the older Streamlit application; it is not the desktop release target.
- Both Flutter projects use Material 3, Riverpod for state, SQLite for the local library, `pdfrx` for viewing and page assembly, `pdf` for generated PDFs, and file picker/share plugins. Their models, repository, PDF engine, scanner, and theme were copied between projects; they still need a single maintained source of truth.
- Desktop has a folder-based library, recent external PDFs, search, sorting, multi-select, page editing, merging, compression, export, and Open With integration on Windows. Mobile has camera capture, automatic scanning through the native scanner plugin, crop/rotate/reorder review, PDF import, favorites, and native sharing.
- Existing PDF editing is page-level. Merge, extract, split, delete, duplicate, rotate, and reorder are largely variants of page assembly. Compression rasterizes pages and loses selectable text. The scanner's automatic edge detection is supplied by the native scanner plugin; manual capture does not do edge detection or perspective correction.
- There is no OCR, annotation, signature, password management, PDF-to-image export, office document renderer/converter, EPUB or mail reader, or cross-device sync. The PDF library model stores PDFs only. No cloud processing path exists.

## Work completed in this increment

- Both libraries now check a PDF signature and require the parser to find pages before import, replacement, or adoption from disk. Invalid replacement input leaves the existing document intact. Import reports rejected files.
- Mobile Home now shows Scan and Open first, followed by recent documents. The desktop library layout is preserved, with Ctrl+O, Ctrl+N, and Escape shortcuts added.
- The repository-root Windows release-candidate workflow builds `desktop/` using the pinned package, PDFium verification, SHA-256 manifest, and optional Authenticode signing script.

## Next implementation sequence

1. Move the duplicated Dart models, PDF engine, file detection, action definitions, theme tokens, and repository logic into one shared local package, with both apps pinned to the same revision. Keep desktop and mobile widgets separate.
2. Add a format-aware intake layer and contextual actions. Only offer operations with real adapters. Add image/PDF combinations and PDF-to-image export before office formats.
3. Add explicit native conversion adapters for supported platforms and tested formats. Detect missing engines and show a clear unavailable state. Do not send documents to a server without an explicit user choice.
4. Extend the scanner review with manual perspective correction, image enhancement, and a local OCR adapter. Keep the native automatic scanner path as the fast path on mobile.
5. Add PDF annotation, signatures, protection, and metadata through maintained local libraries or platform adapters, then exercise malformed and large-file cases with bounded memory and temporary-file cleanup.
6. Validate the desktop release in an isolated Windows VM with Defender enabled, inspect the actual packaged binaries, verify signatures and checksums, then test Android and iOS builds on their supported hosts.

The planned capabilities above are not represented as working buttons in the application.
