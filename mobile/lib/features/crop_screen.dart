import 'dart:io';

import 'package:flutter/material.dart';

/// Drag the four corners to choose the page area.
/// Pops with the chosen rectangle in image pixels, or null for "retake".
class CropScreen extends StatefulWidget {
  final String path;
  final int imgW;
  final int imgH;
  const CropScreen(
      {super.key, required this.path, required this.imgW, required this.imgH});

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  // Normalized (0..1) crop rectangle.
  Rect _r = const Rect.fromLTRB(0.04, 0.04, 0.96, 0.96);

  static const _min = 0.08;

  void _drag(int corner, Offset delta, Size disp) {
    final dx = delta.dx / disp.width;
    final dy = delta.dy / disp.height;
    var l = _r.left, t = _r.top, r = _r.right, b = _r.bottom;
    // corners: 0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right
    if (corner == 0 || corner == 2) {
      l += dx;
    } else {
      r += dx;
    }
    if (corner == 0 || corner == 1) {
      t += dy;
    } else {
      b += dy;
    }
    l = l.clamp(0.0, r - _min).toDouble();
    r = r.clamp(l + _min, 1.0).toDouble();
    t = t.clamp(0.0, b - _min).toDouble();
    b = b.clamp(t + _min, 1.0).toDouble();
    setState(() => _r = Rect.fromLTRB(l, t, r, b));
  }

  Rect get _pixelRect => Rect.fromLTRB(
        _r.left * widget.imgW,
        _r.top * widget.imgH,
        _r.right * widget.imgW,
        _r.bottom * widget.imgH,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Crop'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Retake',
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                setState(() => _r = const Rect.fromLTRB(0, 0, 1, 1)),
            child: const Text('Full page'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _pixelRect),
            child: const Text('Done'),
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, cons) {
        final box = Size(cons.maxWidth, cons.maxHeight);
        final fit = applyBoxFit(
            BoxFit.contain, Size(widget.imgW.toDouble(), widget.imgH.toDouble()), box);
        final dest = fit.destination;
        final disp = Rect.fromLTWH(
          (box.width - dest.width) / 2,
          (box.height - dest.height) / 2,
          dest.width,
          dest.height,
        );
        final hole = Rect.fromLTRB(
          disp.left + _r.left * disp.width,
          disp.top + _r.top * disp.height,
          disp.left + _r.right * disp.width,
          disp.top + _r.bottom * disp.height,
        );
        final corners = [
          hole.topLeft,
          hole.topRight,
          hole.bottomLeft,
          hole.bottomRight,
        ];
        return Stack(
          children: [
            Positioned.fromRect(
              rect: disp,
              child: Image.file(File(widget.path), fit: BoxFit.fill),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _DimPainter(hole)),
              ),
            ),
            for (var i = 0; i < 4; i++)
              Positioned(
                left: corners[i].dx - 28,
                top: corners[i].dy - 28,
                width: 56,
                height: 56,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) => _drag(i, d.delta, disp.size),
                  child: Center(
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 3),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _DimPainter extends CustomPainter {
  final Rect hole;
  _DimPainter(this.hole);

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRect(hole),
    );
    canvas.drawPath(dim, Paint()..color = Colors.black54);
    canvas.drawRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.hole != hole;
}
