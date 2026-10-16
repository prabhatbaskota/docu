import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/format.dart';
import 'document.dart';

/// First-page preview of a PDF file.
class DocThumb extends StatelessWidget {
  final String path;
  final Object versionKey;
  const DocThumb({super.key, required this.path, required this.versionKey});

  @override
  Widget build(BuildContext context) {
    return PdfDocumentViewBuilder.file(
      path,
      key: ValueKey('$path|$versionKey'),
      builder: (context, document) {
        if (document == null || document.pages.isEmpty) {
          return const Center(child: Icon(Icons.picture_as_pdf_outlined));
        }
        final page = document.pages.first;
        return Center(
          child: AspectRatio(
            aspectRatio: page.width / page.height,
            child: PdfPageView(document: document, pageNumber: 1),
          ),
        );
      },
    );
  }
}

class DocumentCard extends StatelessWidget {
  final Document doc;
  final String path;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onFavorite;

  const DocumentCard({
    super.key,
    required this.doc,
    required this.path,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? cs.primary : cs.outlineVariant,
          width: selected ? 3 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: cs.surfaceContainerHighest,
                    padding: const EdgeInsets.all(8),
                    child: DocThumb(path: path, versionKey: doc.updatedAt),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      tooltip: doc.favorite
                          ? 'Remove from favorites'
                          : 'Add to favorites',
                      icon: Icon(
                        doc.favorite ? Icons.star : Icons.star_border,
                        color: doc.favorite ? Colors.amber : cs.onSurfaceVariant,
                      ),
                      onPressed: onFavorite,
                    ),
                  ),
                  if (selected)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Icon(Icons.check_circle, color: cs.primary),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doc.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    '${doc.pageCount} page${doc.pageCount == 1 ? '' : 's'}  ·  ${fmtDate(doc.updatedAt)}',
                    style: tt.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact row used on Home and in the Files list view.
class DocumentRow extends StatelessWidget {
  final Document doc;
  final String path;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onFavorite;

  const DocumentRow({
    super.key,
    required this.doc,
    required this.path,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: selected ? cs.secondaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              if (selecting)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected ? cs.primary : cs.outline,
                  ),
                ),
              Container(
                width: 40,
                height: 52,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: DocThumb(path: path, versionKey: doc.updatedAt),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(doc.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      '${doc.pageCount} page${doc.pageCount == 1 ? '' : 's'}  ·  ${fmtDate(doc.updatedAt)}',
                      style: tt.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: doc.favorite
                    ? 'Remove from favorites'
                    : 'Add to favorites',
                icon: Icon(
                  doc.favorite ? Icons.star : Icons.star_border,
                  color: doc.favorite ? Colors.amber : cs.onSurfaceVariant,
                ),
                onPressed: onFavorite,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
