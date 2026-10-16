import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Big visual representation of one PDF page, with a page number underneath.
class PageCard extends StatelessWidget {
  final PdfDocument doc;
  final int index; // 0-based page in [doc]
  final int number; // number shown to the user
  final bool selected;
  final bool highlight;

  /// Visually quiet pages while another page is selected for editing.
  final bool dimmed;

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
    this.dimmed = false,
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
                  : Color.alphaBlend(tint!.withValues(alpha: 0.18),
                      cs.surfaceContainerHighest),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: marked ? cs.primary : (tint ?? cs.outlineVariant),
                width: 2,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: dimmed ? 0.38 : 1,
                  child: ColorFiltered(
                    colorFilter: dimmed
                        ? const ColorFilter.matrix([
                            0.21,
                            0.72,
                            0.07,
                            0,
                            0,
                            0.21,
                            0.72,
                            0.07,
                            0,
                            0,
                            0.21,
                            0.72,
                            0.07,
                            0,
                            0,
                            0,
                            0,
                            0,
                            1,
                            0,
                          ])
                        : const ColorFilter.mode(
                            Colors.transparent, BlendMode.dst),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: page.width / page.height,
                        child:
                            PdfPageView(document: doc, pageNumber: index + 1),
                      ),
                    ),
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
