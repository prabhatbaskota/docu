import 'package:flutter/material.dart';

/// The docu mark, drawn in code (no asset needed): a page being scanned.
class DocuLogo extends StatelessWidget {
  final double size;
  const DocuLogo({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _LogoPainter()),
      );
}

/// Logo + "docu" wordmark for app bars.
class DocuTitle extends StatelessWidget {
  const DocuTitle({super.key});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DocuLogo(size: 30),
          const SizedBox(width: 10),
          Text(
            'docu',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
          ),
        ],
      );
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final box = Offset.zero & size;

    canvas.drawRRect(
      RRect.fromRectAndRadius(box, Radius.circular(s * 0.24)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5B7CFA), Color(0xFF2B44C9)],
        ).createShader(box),
    );

    final pw = s * 0.46, ph = s * 0.58;
    final left = (s - pw) / 2, top = (s - ph) / 2;
    final right = left + pw, bottom = top + ph;
    final fold = s * 0.15;
    final c = s * 0.045;
    final page = Path()
      ..moveTo(left + c, top)
      ..lineTo(right - fold, top)
      ..lineTo(right, top + fold)
      ..lineTo(right, bottom - c)
      ..quadraticBezierTo(right, bottom, right - c, bottom)
      ..lineTo(left + c, bottom)
      ..quadraticBezierTo(left, bottom, left, bottom - c)
      ..lineTo(left, top + c)
      ..quadraticBezierTo(left, top, left + c, top)
      ..close();
    canvas.drawPath(page, Paint()..color = Colors.white);
    canvas.drawPath(
      Path()
        ..moveTo(right - fold, top)
        ..lineTo(right, top + fold)
        ..lineTo(right - fold, top + fold)
        ..close(),
      Paint()..color = const Color(0xFFCDD7FF),
    );

    final line = Paint()..color = const Color(0xFFC4CFFF);
    final lx = left + s * 0.07;
    final lw = pw - s * 0.14;
    final lh = s * 0.028;
    void bar(double yFrac, double wFrac) => canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(lx, top + ph * yFrac, lw * wFrac, lh),
            Radius.circular(lh / 2),
          ),
          line,
        );
    bar(0.28, 1.0);
    bar(0.43, 1.0);
    bar(0.56, 0.62);

    final by = top + ph * 0.70;
    final bh = s * 0.05;
    final over = s * 0.045;
    final beam = RRect.fromRectAndRadius(
      Rect.fromLTRB(left - over, by, right + over, by + bh),
      Radius.circular(bh / 2),
    );
    canvas.drawRRect(
      beam,
      Paint()
        ..color = const Color(0x663EE6C3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.025),
    );
    canvas.drawRRect(beam, Paint()..color = const Color(0xFF3EE6C3));
  }

  @override
  bool shouldRepaint(_LogoPainter old) => false;
}
