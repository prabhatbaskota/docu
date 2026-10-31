import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/document_edges.dart';
import 'scan_draft.dart';
export 'scan_draft.dart';
import '../../core/image_tools.dart';
import '../../core/toast.dart';

class EdgeCorrectionScreen extends StatefulWidget {
  final List<ScanPage> pages;
  final int initialIndex;
  final String draftKey;
  const EdgeCorrectionScreen(
      {super.key, required this.pages, this.initialIndex = 0,this.draftKey='scan'});
  @override
  State<EdgeCorrectionScreen> createState() => _EdgeCorrectionScreenState();
}

class _EdgeCorrectionScreenState extends State<EdgeCorrectionScreen> {
  late int index = widget.initialIndex;
  bool busy = false;
  final _sizes=<String,Future<Size>>{};
  int? dragging;
  ScanPage get page => widget.pages[index];
  Future<void> persist() => ScanDraft.save(widget.pages, index: index,key:widget.draftKey);
  Future<void> confirm({bool skip = false}) async {
    setState(() => busy = true);
    try {
      if (skip) page.corners = List.of(page.automatic);
      page.corrected = await flattenPage(page.path, page.corners);
      await persist();
      if (!mounted) return;
      if (index == widget.pages.length - 1) {
        Navigator.pop(
            context, [for (final p in widget.pages) p.corrected ?? p.path]);
      } else {
        setState(() => index++);
        await persist();
      }
    } catch (_) {
      if (mounted) {
        toast(context,
            'Could not correct this page. Your scan is kept; please try again.');
      }
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> rotate() async {
    setState(() => busy = true);
    try {
      page.path = await rotateImageFile(page.path);
      List<Offset> turn(List<Offset> p) =>
          [p[3], p[0], p[1], p[2]].map((v) => Offset(1 - v.dy, v.dx)).toList();
      page.corners = turn(page.corners);
      page.automatic = turn(page.automatic);
      await persist();
    } catch (_) {
      if (mounted) toast(context, 'Could not rotate this page.');
    }
    if (mounted) setState(() => busy = false);
  }

  bool valid(List<Offset> p) {
    for (var i = 0; i < 4; i++) {
      final a = p[(i + 1) % 4] - p[i], b = p[(i + 2) % 4] - p[(i + 1) % 4];
      if (a.dx * b.dy - a.dy * b.dx < .002) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text('Page ${index + 1} of ${widget.pages.length}'),
          actions: [
            TextButton(
                onPressed: busy ? null : () => confirm(),
                child: Text(index == widget.pages.length - 1 ? 'Done' : 'Next'))
          ]),
      body: Column(children: [
        LinearProgressIndicator(
            value: busy ? null : (index + 1) / widget.pages.length,
            minHeight: 2),
        Expanded(
            child: FutureBuilder<Size>(
                key: ValueKey(page.path),
                future: _sizes.putIfAbsent(page.path,()=>_size(page.path)),
                builder: (context, snapshot) {
                  if(snapshot.hasError)return const Center(child:Text('Could not open this page. Your draft is kept.'));
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return LayoutBuilder(builder: (context, c) {
                    final size = applyBoxFit(BoxFit.contain, snapshot.data!,
                            Size(c.maxWidth, c.maxHeight))
                        .destination;
                    final origin = Offset((c.maxWidth - size.width) / 2,
                        (c.maxHeight - size.height) / 2);
                    final points = [
                      for (final p in page.corners)
                        origin + Offset(p.dx * size.width, p.dy * size.height)
                    ];
                    return Stack(children: [
                      Positioned(
                          left: origin.dx,
                          top: origin.dy,
                          width: size.width,
                          height: size.height,
                          child: Image.file(File(page.path),
                              fit: BoxFit.fill, cacheWidth: 1600)),
                      Positioned.fill(
                          child: IgnorePointer(
                              child:
                                  CustomPaint(painter: PageOutline(points)))),
                      for (var i = 0; i < 4; i++)
                        Positioned(
                            left: points[i].dx - 24,
                            top: points[i].dy - 24,
                            width: 48,
                            height: 48,
                            child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: busy
                                    ? null
                                    : (_) => setState(() => dragging = i),
                                onPanUpdate: busy
                                    ? null
                                    : (d) {
                                        final next =
                                            List<Offset>.of(page.corners);
                                        final p = next[i] +
                                            Offset(d.delta.dx / size.width,
                                                d.delta.dy / size.height);
                                        next[i] = Offset(
                                            p.dx.clamp(0, 1), p.dy.clamp(0, 1));
                                        if (valid(next)) {
                                          setState(() => page.corners = next);
                                        }
                                      },
                                onPanEnd: (_) {
                                  setState(() => dragging = null);
                                  persist();
                                },
                                child: const Center(
                                    child: CircleAvatar(
                                        radius: 10,
                                        backgroundColor: Colors.white,
                                        child: CircleAvatar(radius: 6))))),
                      if (dragging != null)
                        Positioned(
                            left: 16,
                            top: 16,
                            child: RawMagnifier(
                                size: const Size(110, 110),
                                magnificationScale: 2,
                                focalPointOffset:
                                    points[dragging!] - const Offset(71, 71),
                                decoration: const MagnifierDecoration(
                                    shape: CircleBorder(
                                        side: BorderSide(
                                            color: Colors.white, width: 2))))),
                    ]);
                  });
                })),
        SafeArea(
            child: Wrap(alignment: WrapAlignment.center, children: [
          TextButton(
              onPressed: busy || index == 0
                  ? null
                  : () async {
                      setState(() => index--);
                      await persist();
                    },
              child: const Text('Back')),
          TextButton(
              onPressed: busy ? null : () => confirm(skip: true),
              child: const Text('Skip')),
          TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => page.corners = List.of(pageMargin));
                      await persist();
                    },
              child: const Text('Reset corners')),
          IconButton(
              onPressed: busy ? null : rotate,
              tooltip: 'Rotate 90°',
              icon: const Icon(Icons.rotate_right)),
        ])),
      ]));
}

Future<Size> _size(String path) async {
  final buffer=await ui.ImmutableBuffer.fromFilePath(path);
  final image=await ui.ImageDescriptor.encoded(buffer);
  try{return Size(image.width.toDouble(),image.height.toDouble());}
  finally{image.dispose();buffer.dispose();}
}

class PageOutline extends CustomPainter {
  final List<Offset> points;
  PageOutline(this.points);
  @override
  void paint(Canvas c, Size size) {
    if (points.length != 4) return;
    final path = Path()..addPolygon(points, true);
    c.drawPath(
        path, Paint()..color = Colors.lightBlueAccent.withValues(alpha: .15));
    c.drawPath(
        path,
        Paint()
          ..color = Colors.lightBlueAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(PageOutline old) => true;
}
