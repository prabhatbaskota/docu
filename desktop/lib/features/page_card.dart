import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Big visual representation of one PDF page, with a page number underneath.
class PageCard extends StatelessWidget {
  final PdfDocument doc;
  final int index; // 0-based page in [doc]
  final int number; // number shown to the user
  final bool selected;
  final bool highlight;

  /// Source-PDF color and letter (editor with 2+ sources). Letter keeps it
  /// readable for people who can't tell the colors apart.
  final Color? tint;
  final String? badge;

  const PageCard({
    super.key,
    required this.doc,
    required this.index,
    required this.number,
    this.selected = false,
    this.highlight = false,
    this.tint,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final page = doc.pages[index];
    final marked = selected || highlight;
    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(6),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: tint == null
                  ? cs.surfaceContainerHighest
                  : Color.alphaBlend(
                      tint!.withValues(alpha: 0.18), cs.surfaceContainerHighest),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: marked ? cs.primary : (tint ?? cs.outlineVariant),
                width: marked ? 3 : (tint == null ? 1 : 2),
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: page.width / page.height,
                    child: PdfPageView(document: doc, pageNumber: index + 1),
                  ),
                ),
                if (badge != null)
                  Positioned(
                    top: 0,
                    left: 0,
                    child: Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tint ?? cs.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(badge!,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                if (selected)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Icon(Icons.check_circle, color: cs.primary),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text('$number', style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}
