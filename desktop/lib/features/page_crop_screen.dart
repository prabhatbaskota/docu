import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Select a rectangle in displayed page coordinates, normalized to 0..1.
class PageCropScreen extends StatefulWidget {
  final PdfDocument document;
  final int index;
  const PageCropScreen(
      {super.key, required this.document, required this.index});

  @override
  State<PageCropScreen> createState() => _PageCropScreenState();
}

class _PageCropScreenState extends State<PageCropScreen> {
  Rect _crop = const Rect.fromLTWH(0, 0, 1, 1);
  Offset? _start;

  @override
  Widget build(BuildContext context) {
    final page = widget.document.pages[widget.index];
    return Scaffold(
      appBar: AppBar(title: const Text('Crop page'), actions: [
        TextButton(
            onPressed: () =>
                setState(() => _crop = const Rect.fromLTWH(0, 0, 1, 1)),
            child: const Text('Reset')),
        TextButton(
            onPressed: _crop.width >= .02 && _crop.height >= .02
                ? () => Navigator.pop(context, _crop)
                : null,
            child: const Text('Apply')),
      ]),
      body: Column(children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
              'Drag across the page to select the area to keep. Apply replaces this page in your edit. The cropped page becomes an image; text selection and links are lost.'),
        ),
        Expanded(
            child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
              child: AspectRatio(
            aspectRatio: page.width / page.height,
            child: LayoutBuilder(builder: (context, constraints) {
              Offset normalized(Offset p) => Offset(
                  (p.dx / constraints.maxWidth).clamp(0, 1),
                  (p.dy / constraints.maxHeight).clamp(0, 1));
              return GestureDetector(
                onPanStart: (d) => _start = normalized(d.localPosition),
                onPanUpdate: (d) => setState(() => _crop =
                    Rect.fromPoints(_start!, normalized(d.localPosition))),
                child: Stack(fit: StackFit.expand, children: [
                  PdfPageView(
                      document: widget.document, pageNumber: widget.index + 1),
                  CustomPaint(
                      painter: _CropPainter(
                          _crop, Theme.of(context).colorScheme.primary)),
                ]),
              );
            }),
          )),
        )),
      ]),
    );
  }
}

class _CropPainter extends CustomPainter {
  final Rect crop;
  final Color color;
  _CropPainter(this.crop, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(crop.left * size.width, crop.top * size.height,
        crop.right * size.width, crop.bottom * size.height);
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(rect);
    canvas.drawPath(mask, Paint()..color = Colors.black54);
    canvas.drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) =>
      oldDelegate.crop != crop || oldDelegate.color != color;
}
