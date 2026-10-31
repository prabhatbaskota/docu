# 02-sequential-correction

Complete final integrated files. Apply the bundle as a whole; shared imports cross feature boundaries.

See [test steps and limits](README.md).

## `mobile/lib/features/scan/scan_draft.dart`

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:path_provider/path_provider.dart';
import '../../core/document_geometry.dart';

class ScanPage {
  String path;
  List<Offset> corners;
  List<Offset> automatic;
  String? corrected;
  ScanPage(this.path, List<Offset>? initial)
      : corners = List.of(initial ?? pageMargin),
        automatic = List.of(initial ?? pageMargin);
  Map<String, dynamic> toJson() => {
        'path': path,
        'corners': [
          for (final p in corners) [p.dx, p.dy]
        ],
        'automatic': [
          for (final p in automatic) [p.dx, p.dy]
        ],
        'corrected': corrected
      };
  factory ScanPage.fromJson(Map<String, dynamic> j) {
    List<Offset> points(dynamic v) => [
          for (final p in v)
            Offset((p[0] as num).toDouble(), (p[1] as num).toDouble())
        ];
    final page = ScanPage(j['path'] as String, points(j['automatic']));
    page.corners = points(j['corners']);
    page.corrected = j['corrected'] as String?;
    return page;
  }
}

/// A durable working manifest. Photos are copied before acknowledging capture.
class ScanDraft {
  static Future<void> _writing = Future<void>.value();
  static Future<File> get manifest=>_file('scan');
  static Future<File> _file(String key) async=>File('${(await getApplicationSupportDirectory()).path}/${key}_draft.json');
  static Future<void> save(List<ScanPage> pages,
      {int index = 0, bool review = false,String key='scan'}) {
    final content = jsonEncode({
      'index': index,
      'review': review,
      'pages': [for (final p in pages) p.toJson()]
    });
    final task = _writing.catchError((Object _) {}).then((_) => _save(content,key));
    _writing = task;
    return task;
  }

  static Future<void> _save(String content,String key) async {
    final f = await _file(key);
    await f.parent.create(recursive: true);
    final temp = File('${f.path}.new');
    await temp.writeAsString(content, flush: true);
    await temp.rename(f.path);
  }

  static Future<void> saveReview(List<String> paths) => save(
      [for (final path in paths) ScanPage(path, pageMargin)..corrected = path],
      review: true);
  static Future<(List<ScanPage>, int, bool)?> load({String key='scan'}) async {
    await _writing.catchError((Object _) {});
    final f = await _file(key);
    if (!await f.exists()) return null;
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return (
      [
        for (final p in j['pages'])
          ScanPage.fromJson(Map<String, dynamic>.from(p))
      ],
      j['index'] as int,
      j['review'] == true
    );
  }

  static Future<void> clear({String key='scan'}) async {
    await _writing.catchError((Object _) {});
    final f = await _file(key);
    if (await f.exists()) await f.delete();
  }
}
```

## `mobile/lib/features/scan/edge_correction_screen.dart`

```dart
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
```

## `mobile/lib/features/scan/scan_review_screen.dart`

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';

import '../../core/image_tools.dart';
import '../../core/pdf_engine.dart' show friendlyError;
import '../../core/toast.dart';
import '../camera_scan_screen.dart';
import '../crop_screen.dart';
import 'edge_correction_screen.dart';

class _Img {
  final int id;
  String path;
  _Img(this.id, this.path);
}

/// The whole scanned batch at a glance. Fix pages (crop, rotate), delete,
/// reorder by dragging, add more, then confirm.
/// Pops with the final list of image paths, or null when cancelled.
class ScanReviewScreen extends StatefulWidget {
  final List<String> initial;
  final String confirmLabel; // e.g. "Save PDF" or "Add pages"
  const ScanReviewScreen(
      {super.key, required this.initial, required this.confirmLabel});

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  final List<_Img> _imgs = [];
  final Set<int> _sel = {};
  final ScrollController _scroll = ScrollController();
  int _nextId = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _imgs.addAll([for (final p in widget.initial) _Img(_nextId++, p)]);
    _persist();
  }

  void _persist() {
    ScanDraft.saveReview([for (final im in _imgs) im.path])
        .catchError((Object _) {
      if (mounted) {
        toast(context, 'Could not update the saved draft. Check free space.');
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toggle(int id) => setState(() {
        if (!_sel.remove(id)) _sel.add(id);
      });

  void _delete() => setState(() {
        _imgs.removeWhere((i) => _sel.contains(i.id));
        _sel.clear();
        _persist();
      });

  Future<void> _rotate() async {
    setState(() => _busy = true);
    try {
      for (final im in _imgs.where((i) => _sel.contains(i.id))) {
        final out = await rotateImageFile(im.path);
        im.path = out;
      }
      _persist();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _crop() async {
    final im = _imgs.firstWhere((i) => _sel.contains(i.id));
    try {
      final decoded =
          await decodeImageFromList(await File(im.path).readAsBytes());
      final w = decoded.width, h = decoded.height;
      decoded.dispose();
      if (!mounted) return;
      final rect = await Navigator.of(context).push<Rect>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => CropScreen(path: im.path, imgW: w, imgH: h),
        ),
      );
      if (rect == null || !mounted) return;
      final full = rect.width >= w - 2 && rect.height >= h - 2;
      if (full) return;
      setState(() => _busy = true);
      final out = await cropImageFile(im.path, rect);
      if (!mounted) return;
      setState(() {
        im.path = out;
        _persist();
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, friendlyError(e));
    }
  }

  Future<void> _addMore() async {
    final more = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CameraScanScreen(multiple: true, startAt: _imgs.length),
      ),
    );
    if (more == null || more.isEmpty || !mounted) return;
    setState(() {
      _imgs.addAll([for (final p in more) _Img(_nextId++, p)]);
      _persist();
    });
  }

  void _onReorder(ReorderedListFunction reorderedListFunction) {
    final updated =
        reorderedListFunction(List<_Img>.of(_imgs)).cast<_Img>().toList();
    setState(() {
      _imgs
        ..clear()
        ..addAll(updated);
      _persist();
    });
    HapticFeedback.lightImpact();
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            'Discard ${_imgs.length} page${_imgs.length == 1 ? '' : 's'}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard')),
        ],
      ),
    );
    if (ok == true) await ScanDraft.clear();
    return ok == true;
  }

  Widget _tile(int i) {
    final im = _imgs[i];
    final cs = Theme.of(context).colorScheme;
    final selected = _sel.contains(im.id);
    return GestureDetector(
      key: ValueKey<String>('img_${im.id}'),
      onTap: () => _toggle(im.id),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? cs.primary : cs.outlineVariant,
                  width: selected ? 3 : 1,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(im.path),
                      fit: BoxFit.contain, cacheWidth: 500),
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
          Text('${i + 1}', style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap,
          {Color? color}) =>
      Expanded(
        child: InkWell(
          onTap: _busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(fontSize: 11, color: color)),
              ],
            ),
          ),
        ),
      );

  Widget _bar() {
    final one = _sel.length == 1;
    final error = Theme.of(context).colorScheme.error;
    return Material(
      elevation: 8,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: _sel.isEmpty
              ? Row(children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _addMore,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Add page'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: (_busy || _imgs.isEmpty)
                          ? null
                          : () => Navigator.pop(
                              context, [for (final i in _imgs) i.path]),
                      child: Text(widget.confirmLabel),
                    ),
                  ),
                ])
              : Row(children: [
                  if (one) _action(Icons.crop, 'Crop', _crop),
                  _action(Icons.rotate_right, 'Rotate', _rotate),
                  _action(Icons.delete_outline, 'Delete', _delete,
                      color: error),
                  _action(Icons.deselect, 'Clear', () => setState(_sel.clear)),
                ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cols = (MediaQuery.of(context).size.width ~/ 170).clamp(2, 6);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_imgs.isEmpty || await _confirmDiscard()) {
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_sel.isEmpty
              ? '${_imgs.length} page${_imgs.length == 1 ? '' : 's'}'
              : '${_sel.length} selected'),
        ),
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Tap a page to fix it. Hold and drag to reorder.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            Expanded(
              child: _imgs.isEmpty
                  ? const Center(
                      child: Text('No pages left. Add a page below.'))
                  : ReorderableBuilder.builder(
                      scrollController: _scroll,
                      itemCount: _imgs.length,
                      onReorder: _onReorder,
                      childBuilder: (itemBuilder) => GridView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.7,
                        ),
                        itemCount: _imgs.length,
                        itemBuilder: (context, i) => itemBuilder(_tile(i), i),
                      ),
                    ),
            ),
          ],
        ),
        bottomNavigationBar: _bar(),
      ),
    );
  }
}
```

## `mobile/lib/features/scan_flow.dart`

```dart
import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/pdf_engine.dart';
import '../core/pdf_helpers.dart';
import '../core/progress.dart';
import '../core/toast.dart';
import '../core/ocr_service.dart';
import 'camera_scan_screen.dart';
import 'documents/actions.dart';
import 'documents/document_screen.dart';
import 'scan/scan_review_screen.dart';
import 'scan/edge_correction_screen.dart';
import 'scan/card_scan_screen.dart';

enum ScanMode { single, multiple, card }

Future<ScanMode?> askScanMode(BuildContext context) {
  return showModalBottomSheet<ScanMode>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.crop_portrait),
            title: const Text('Single page'),
            subtitle: const Text('Press the shutter, then crop'),
            onTap: () => Navigator.pop(ctx, ScanMode.single),
          ),
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: const Text('Multiple pages'),
            subtitle:
                const Text('Shoot page after page, review them all after'),
            onTap: () => Navigator.pop(ctx, ScanMode.multiple),
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('ID / Card'),
            subtitle: const Text('Front and back on one A4 page'),
            onTap: () => Navigator.pop(ctx, ScanMode.card),
          ),
        ],
      ),
    ),
  );
}

/// Mode prompt, capture, then the batch review. Returns the approved image
/// paths, or null if the user backed out at any point.
Future<List<String>?> scanAndReview(
  BuildContext context, {
  required String confirmLabel,
}) async {
  final mode = await askScanMode(context);
  if (mode == null || !context.mounted) return null;
  if (mode == ScanMode.card) {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => const CardScanScreen()));
    return null;
  }

  List<String> imgs = const [];
  final draft = await ScanDraft.load();
  if (!context.mounted) return null;
  if (draft != null && draft.$1.isNotEmpty) {
    final resume = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Resume unfinished scan?'),
                content: Text(
                    '${draft.$1.length} captured pages are kept on this device.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Discard')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Resume'))
                ]));
    if (!context.mounted) return null;
    if (resume == null) return null;
    if (resume) {
      imgs = draft.$3
          ? [for (final p in draft.$1) p.corrected ?? p.path]
          : await Navigator.of(context).push<List<String>>(MaterialPageRoute(
                  builder: (_) => EdgeCorrectionScreen(
                      pages: draft.$1, initialIndex: draft.$2))) ??
              const [];
      if (imgs.isEmpty || !context.mounted) return null;
      return Navigator.of(context).push<List<String>>(MaterialPageRoute(
          builder: (_) =>
              ScanReviewScreen(initial: imgs, confirmLabel: confirmLabel)));
    }
    await ScanDraft.clear();
  }
  if (!context.mounted) return null;
  {
    imgs = await Navigator.of(context).push<List<String>>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) =>
                CameraScanScreen(multiple: mode == ScanMode.multiple),
          ),
        ) ??
        const [];
  }
  if (imgs.isEmpty || !context.mounted) return null;

  return Navigator.of(context).push<List<String>>(
    MaterialPageRoute(
      builder: (_) =>
          ScanReviewScreen(initial: imgs, confirmLabel: confirmLabel),
    ),
  );
}

/// Scan, review, save as a PDF named "Scan <date time>", and open it.
Future<void> startScan(BuildContext context) async {
  final imgs = await scanAndReview(context, confirmLabel: 'Save PDF');
  if (imgs == null || imgs.isEmpty || !context.mounted) return;
  final repo = repoOf(context);
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final id =
        await runWithProgress<String>(context, 'Saving...', (report) async {
      final tmp = await tempPdfPath();
      await engine.imagesToPdf(imgs, tmp, onProgress: report);
      final doc = await repo.addFile(tmp, title: 'Scan ${stamp()}');
      await ScanDraft.clear();
      await OcrService(repo).enqueue(doc.id);
      return doc.id;
    });
    nav.push(MaterialPageRoute<void>(builder: (_) => DocumentScreen(id: id)));
  } catch (e) {
    toastOn(messenger, friendlyError(e));
  }
}
```

## `mobile/test/scan_regression_test.dart`

```dart
import 'dart:io';
import 'package:docapp/core/document_geometry.dart';
import 'package:docapp/core/pdf_engine.dart';
import 'package:docapp/features/scan/scan_draft.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('outline requires stable frames and expires after lost page', () {
    final tracker = EdgeTracker();
    tracker.update(pageMargin);
    tracker.update(pageMargin);
    expect(tracker.corners, isNull);
    tracker.update(pageMargin);
    expect(tracker.corners, pageMargin);
    tracker.update(null);
    tracker.update(null);
    tracker.update(null);
    expect(tracker.corners, isNull);
    tracker.update(pageMargin);
    expect(tracker.corners, isNull);
  });
  test(
      'batch survives process-style reload with ordering, edits, and page index',
      () async {
    final dir = await Directory.systemTemp.createTemp('docu_batch_');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => dir.path);
    try {
      final first = ScanPage('${dir.path}/one.jpg', pageMargin)
        ..corners = [
          const Offset(.1, .1),
          const Offset(.9, .12),
          const Offset(.95, .9),
          const Offset(.08, .94)
        ]
        ..corrected = 'corrected.jpg';
      final second = ScanPage('${dir.path}/two.jpg', null);
      await ScanDraft.save([first, second], index: 1);
      final restored = (await ScanDraft.load())!;
      expect(restored.$2, 1);
      expect(restored.$1.length, 2);
      expect(restored.$1.first.corners, first.corners);
      expect(restored.$1.first.corrected, 'corrected.jpg');
      expect(restored.$1.last.path, second.path);
      await ScanDraft.saveReview(['two.jpg', 'one.jpg']);
      final review = (await ScanDraft.load())!;
      expect(review.$3, isTrue);
      expect(review.$1.first.corrected, 'two.jpg');
      await ScanDraft.clear();
      expect(await ScanDraft.load(), isNull);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await dir.delete(recursive: true);
    }
  });
  test('merge rejects empty input before creating a corrupt PDF', () async {
    await expectLater(
        engine.assemble([], 'unused.pdf'), throwsA(isA<FormatException>()));
    expect(File('unused.pdf').existsSync(), isFalse);
  });
  test('internal errors are never shown as stack traces', () {
    expect(friendlyError(StateError('secret internal detail')),
        isNot(contains('secret')));
    expect(friendlyError(CompressionCancelled()), contains('cancelled'));
  });
}
```

## `desktop/lib/features/scan/scan_draft.dart`

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:path_provider/path_provider.dart';
import '../../core/document_geometry.dart';

class ScanPage {
  String path;
  List<Offset> corners;
  List<Offset> automatic;
  String? corrected;
  ScanPage(this.path, List<Offset>? initial)
      : corners = List.of(initial ?? pageMargin),
        automatic = List.of(initial ?? pageMargin);
  Map<String, dynamic> toJson() => {
        'path': path,
        'corners': [
          for (final p in corners) [p.dx, p.dy]
        ],
        'automatic': [
          for (final p in automatic) [p.dx, p.dy]
        ],
        'corrected': corrected
      };
  factory ScanPage.fromJson(Map<String, dynamic> j) {
    List<Offset> points(dynamic v) => [
          for (final p in v)
            Offset((p[0] as num).toDouble(), (p[1] as num).toDouble())
        ];
    final page = ScanPage(j['path'] as String, points(j['automatic']));
    page.corners = points(j['corners']);
    page.corrected = j['corrected'] as String?;
    return page;
  }
}

/// A durable working manifest. Photos are copied before acknowledging capture.
class ScanDraft {
  static Future<void> _writing = Future<void>.value();
  static Future<File> get manifest=>_file('scan');
  static Future<File> _file(String key) async=>File('${(await getApplicationSupportDirectory()).path}/${key}_draft.json');
  static Future<void> save(List<ScanPage> pages,
      {int index = 0, bool review = false,String key='scan'}) {
    final content = jsonEncode({
      'index': index,
      'review': review,
      'pages': [for (final p in pages) p.toJson()]
    });
    final task = _writing.catchError((Object _) {}).then((_) => _save(content,key));
    _writing = task;
    return task;
  }

  static Future<void> _save(String content,String key) async {
    final f = await _file(key);
    await f.parent.create(recursive: true);
    final temp = File('${f.path}.new');
    await temp.writeAsString(content, flush: true);
    await temp.rename(f.path);
  }

  static Future<void> saveReview(List<String> paths) => save(
      [for (final path in paths) ScanPage(path, pageMargin)..corrected = path],
      review: true);
  static Future<(List<ScanPage>, int, bool)?> load({String key='scan'}) async {
    await _writing.catchError((Object _) {});
    final f = await _file(key);
    if (!await f.exists()) return null;
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return (
      [
        for (final p in j['pages'])
          ScanPage.fromJson(Map<String, dynamic>.from(p))
      ],
      j['index'] as int,
      j['review'] == true
    );
  }

  static Future<void> clear({String key='scan'}) async {
    await _writing.catchError((Object _) {});
    final f = await _file(key);
    if (await f.exists()) await f.delete();
  }
}
```

## `desktop/lib/features/scan/edge_correction_screen.dart`

```dart
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
```

## `desktop/lib/features/scan/scan_review_screen.dart`

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';

import '../../core/image_tools.dart';
import '../../core/pdf_engine.dart' show friendlyError;
import '../../core/toast.dart';
import 'import_scan.dart';
import '../crop_screen.dart';
import 'edge_correction_screen.dart';

class _Img {
  final int id;
  String path;
  _Img(this.id, this.path);
}

/// The whole scanned batch at a glance. Fix pages (crop, rotate), delete,
/// reorder by dragging, add more, then confirm.
/// Pops with the final list of image paths, or null when cancelled.
class ScanReviewScreen extends StatefulWidget {
  final List<String> initial;
  final String confirmLabel; // e.g. "Save PDF" or "Add pages"
  const ScanReviewScreen(
      {super.key, required this.initial, required this.confirmLabel});

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  final List<_Img> _imgs = [];
  final Set<int> _sel = {};
  final ScrollController _scroll = ScrollController();
  int _nextId = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _imgs.addAll([for (final p in widget.initial) _Img(_nextId++, p)]);
    _persist();
  }

  void _persist() {
    ScanDraft.saveReview([for (final im in _imgs) im.path])
        .catchError((Object _) {
      if (mounted) {
        toast(context, 'Could not update the saved draft. Check free space.');
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toggle(int id) => setState(() {
        if (!_sel.remove(id)) _sel.add(id);
      });

  void _delete() => setState(() {
        _imgs.removeWhere((i) => _sel.contains(i.id));
        _sel.clear();
        _persist();
      });

  Future<void> _rotate() async {
    setState(() => _busy = true);
    try {
      for (final im in _imgs.where((i) => _sel.contains(i.id))) {
        final out = await rotateImageFile(im.path);
        im.path = out;
      }
      _persist();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _crop() async {
    final im = _imgs.firstWhere((i) => _sel.contains(i.id));
    try {
      final decoded =
          await decodeImageFromList(await File(im.path).readAsBytes());
      final w = decoded.width, h = decoded.height;
      decoded.dispose();
      if (!mounted) return;
      final rect = await Navigator.of(context).push<Rect>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => CropScreen(path: im.path, imgW: w, imgH: h),
        ),
      );
      if (rect == null || !mounted) return;
      final full = rect.width >= w - 2 && rect.height >= h - 2;
      if (full) return;
      setState(() => _busy = true);
      final out = await cropImageFile(im.path, rect);
      if (!mounted) return;
      setState(() {
        im.path = out;
        _persist();
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, friendlyError(e));
    }
  }

  Future<void> _addMore() async {
    final more = await importScan(context);
    if (more == null || more.isEmpty || !mounted) return;
    setState(() {
      _imgs.addAll([for (final p in more) _Img(_nextId++, p)]);
      _persist();
    });
  }

  void _onReorder(ReorderedListFunction reorderedListFunction) {
    final updated =
        reorderedListFunction(List<_Img>.of(_imgs)).cast<_Img>().toList();
    setState(() {
      _imgs
        ..clear()
        ..addAll(updated);
      _persist();
    });
    HapticFeedback.lightImpact();
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            'Discard ${_imgs.length} page${_imgs.length == 1 ? '' : 's'}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard')),
        ],
      ),
    );
    if (ok == true) await ScanDraft.clear();
    return ok == true;
  }

  Widget _tile(int i) {
    final im = _imgs[i];
    final cs = Theme.of(context).colorScheme;
    final selected = _sel.contains(im.id);
    return GestureDetector(
      key: ValueKey<String>('img_${im.id}'),
      onTap: () => _toggle(im.id),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? cs.primary : cs.outlineVariant,
                  width: selected ? 3 : 1,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(im.path),
                      fit: BoxFit.contain, cacheWidth: 500),
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
          Text('${i + 1}', style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap,
          {Color? color}) =>
      Expanded(
        child: InkWell(
          onTap: _busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(fontSize: 11, color: color)),
              ],
            ),
          ),
        ),
      );

  Widget _bar() {
    final one = _sel.length == 1;
    final error = Theme.of(context).colorScheme.error;
    return Material(
      elevation: 8,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: _sel.isEmpty
              ? Row(children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _addMore,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Add page'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: (_busy || _imgs.isEmpty)
                          ? null
                          : () => Navigator.pop(
                              context, [for (final i in _imgs) i.path]),
                      child: Text(widget.confirmLabel),
                    ),
                  ),
                ])
              : Row(children: [
                  if (one) _action(Icons.crop, 'Crop', _crop),
                  _action(Icons.rotate_right, 'Rotate', _rotate),
                  _action(Icons.delete_outline, 'Delete', _delete,
                      color: error),
                  _action(Icons.deselect, 'Clear', () => setState(_sel.clear)),
                ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cols = (MediaQuery.of(context).size.width ~/ 170).clamp(2, 6);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_imgs.isEmpty || await _confirmDiscard()) {
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_sel.isEmpty
              ? '${_imgs.length} page${_imgs.length == 1 ? '' : 's'}'
              : '${_sel.length} selected'),
        ),
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Tap a page to fix it. Hold and drag to reorder.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            Expanded(
              child: _imgs.isEmpty
                  ? const Center(
                      child: Text('No pages left. Add a page below.'))
                  : ReorderableBuilder.builder(
                      scrollController: _scroll,
                      itemCount: _imgs.length,
                      onReorder: _onReorder,
                      childBuilder: (itemBuilder) => GridView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.7,
                        ),
                        itemCount: _imgs.length,
                        itemBuilder: (context, i) => itemBuilder(_tile(i), i),
                      ),
                    ),
            ),
          ],
        ),
        bottomNavigationBar: _bar(),
      ),
    );
  }
}
```

## `desktop/lib/features/scan_flow.dart`

```dart
import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/pdf_engine.dart';
import '../core/pdf_helpers.dart';
import '../core/progress.dart';
import '../core/toast.dart';
import '../core/ocr_service.dart';
import 'scan/import_scan.dart';
import 'scan/card_scan_screen.dart';
import 'scan/edge_correction_screen.dart';
import 'documents/actions.dart';
import 'documents/document_screen.dart';
import 'scan/scan_review_screen.dart';

enum ScanMode { single, multiple, auto }

Future<ScanMode?> askScanMode(BuildContext context) {
  return showModalBottomSheet<ScanMode>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.crop_portrait),
            title: const Text('Single page'),
            subtitle: const Text('Choose a photo, then correct its edges'),
            onTap: () => Navigator.pop(ctx, ScanMode.single),
          ),
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: const Text('Multiple pages'),
            subtitle: const Text('Choose photos and correct them in sequence'),
            onTap: () => Navigator.pop(ctx, ScanMode.multiple),
          ),
          ListTile(
            leading: const Icon(Icons.auto_fix_high_outlined),
            title: const Text('ID / Card'),
            subtitle: const Text('Front and back on one A4 page'),
            onTap: () => Navigator.pop(ctx, ScanMode.auto),
          ),
        ],
      ),
    ),
  );
}

/// Mode prompt, capture, then the batch review. Returns the approved image
/// paths, or null if the user backed out at any point.
Future<List<String>?> scanAndReview(
  BuildContext context, {
  required String confirmLabel,
}) async {
  final mode = await askScanMode(context);
  if (mode == null || !context.mounted) return null;

  List<String> imgs = const [];
  if (mode == ScanMode.auto) {
    try {
      await Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const CardScanScreen()));
      return null;
    } catch (e) {
      if (context.mounted) toast(context, friendlyError(e));
      return null;
    }
  } else {
    final draft = await ScanDraft.load();
    if (!context.mounted) return null;
    if (draft != null && draft.$1.isNotEmpty) {
      imgs = draft.$3
          ? [for (final p in draft.$1) p.corrected ?? p.path]
          : await Navigator.of(context).push<List<String>>(MaterialPageRoute(
                  builder: (_) => EdgeCorrectionScreen(
                      pages: draft.$1, initialIndex: draft.$2))) ??
              const [];
    } else {
      imgs = await importScan(context, multiple: mode == ScanMode.multiple) ??
          const [];
    }
  }
  if (imgs.isEmpty || !context.mounted) return null;

  return Navigator.of(context).push<List<String>>(
    MaterialPageRoute(
      builder: (_) =>
          ScanReviewScreen(initial: imgs, confirmLabel: confirmLabel),
    ),
  );
}

/// Scan, review, save as a PDF named "Scan <date time>", and open it.
Future<void> startScan(BuildContext context) async {
  final imgs = await scanAndReview(context, confirmLabel: 'Save PDF');
  if (imgs == null || imgs.isEmpty || !context.mounted) return;
  final repo = repoOf(context);
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final id =
        await runWithProgress<String>(context, 'Saving...', (report) async {
      final tmp = await tempPdfPath();
      await engine.imagesToPdf(imgs, tmp, onProgress: report);
      final doc = await repo.addFile(tmp, title: 'Scan ${stamp()}');
      await ScanDraft.clear();
      await OcrService(repo).enqueue(doc.id);
      return doc.id;
    });
    nav.push(MaterialPageRoute<void>(builder: (_) => DocumentScreen(id: id)));
  } catch (e) {
    toastOn(messenger, friendlyError(e));
  }
}
```

## `desktop/test/scan_regression_test.dart`

```dart
import 'dart:io';
import 'package:docapp/core/document_geometry.dart';
import 'package:docapp/core/pdf_engine.dart';
import 'package:docapp/features/scan/scan_draft.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('outline requires stable frames and expires after lost page', () {
    final tracker = EdgeTracker();
    tracker.update(pageMargin);
    tracker.update(pageMargin);
    expect(tracker.corners, isNull);
    tracker.update(pageMargin);
    expect(tracker.corners, pageMargin);
    tracker.update(null);
    tracker.update(null);
    tracker.update(null);
    expect(tracker.corners, isNull);
    tracker.update(pageMargin);
    expect(tracker.corners, isNull);
  });
  test(
      'batch survives process-style reload with ordering, edits, and page index',
      () async {
    final dir = await Directory.systemTemp.createTemp('docu_batch_');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => dir.path);
    try {
      final first = ScanPage('${dir.path}/one.jpg', pageMargin)
        ..corners = [
          const Offset(.1, .1),
          const Offset(.9, .12),
          const Offset(.95, .9),
          const Offset(.08, .94)
        ]
        ..corrected = 'corrected.jpg';
      final second = ScanPage('${dir.path}/two.jpg', null);
      await ScanDraft.save([first, second], index: 1);
      final restored = (await ScanDraft.load())!;
      expect(restored.$2, 1);
      expect(restored.$1.length, 2);
      expect(restored.$1.first.corners, first.corners);
      expect(restored.$1.first.corrected, 'corrected.jpg');
      expect(restored.$1.last.path, second.path);
      await ScanDraft.saveReview(['two.jpg', 'one.jpg']);
      final review = (await ScanDraft.load())!;
      expect(review.$3, isTrue);
      expect(review.$1.first.corrected, 'two.jpg');
      await ScanDraft.clear();
      expect(await ScanDraft.load(), isNull);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await dir.delete(recursive: true);
    }
  });
  test('merge rejects empty input before creating a corrupt PDF', () async {
    await expectLater(
        engine.assemble([], 'unused.pdf'), throwsA(isA<FormatException>()));
    expect(File('unused.pdf').existsSync(), isFalse);
  });
  test('internal errors are never shown as stack traces', () {
    expect(friendlyError(StateError('secret internal detail')),
        isNot(contains('secret')));
    expect(friendlyError(CompressionCancelled()), contains('cancelled'));
  });
}
```

## `desktop/lib/features/scan/import_scan.dart`

```dart
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/document_edges.dart';
import '../../core/progress.dart';
import '../../core/pdf_engine.dart';
import '../../core/toast.dart';
import 'edge_correction_screen.dart';

Future<List<String>?> importScan(BuildContext context,
    {bool multiple = true,String draftKey='scan'}) async {
  try {
  final picked = await FilePicker.platform
      .pickFiles(type: FileType.image, allowMultiple: multiple);
  if (picked == null || !context.mounted) return null;
  final pages = await runWithProgress<List<ScanPage>>(
      context, 'Finding page edges…', (report) async {
    final dir = Directory(
        '${(await getApplicationSupportDirectory()).path}/scan_pages');
    await dir.create(recursive: true);
    final pages = <ScanPage>[];
    for (final path in picked.paths.whereType<String>()) {
      final copy = await File(path)
          .copy('${dir.path}/${DateTime.now().microsecondsSinceEpoch}.jpg');
      final normalized = await normalizeScanPhoto(copy.path);
      pages.add(ScanPage(normalized.$1, await detectPhoto(normalized.$1)));
      await ScanDraft.save(pages,key:draftKey);
      report(pages.length, picked.count);
    }
    return pages;
  });
  if (!context.mounted || pages.isEmpty) return null;
  return await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(builder: (_) => EdgeCorrectionScreen(pages: pages,draftKey:draftKey)));
  } catch(e) {
    if(context.mounted)toast(context,friendlyError(e));
    return null;
  }
}
```

## `mobile/lib/core/scan_cleanup.dart`

```dart
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Run before opening scan screens so active captures cannot race cleanup.
Future<void> cleanOldScanImages({Directory? support, DateTime? now}) async {
  try {
    final root = support ?? await getApplicationSupportDirectory();
    final protected = <String>{};
    void collect(dynamic value) {
      if (value is String) {
        protected.add(p.normalize(p.absolute(value)));
      } else if (value is List) {
        value.forEach(collect);
      } else if (value is Map) {
        value.values.forEach(collect);
      }
    }

    for (final name in ['scan', 'card', 'card_side']) {
      for (final suffix in ['.json', '.json.new']) {
        final manifest = File(p.join(root.path, '${name}_draft$suffix'));
        if (await manifest.exists()) {
          // A damaged manifest might still describe recoverable photos.
          // Abort cleanup rather than guessing which photos are unreferenced.
          collect(jsonDecode(await manifest.readAsString()));
        }
      }
    }
    final pages = Directory(p.join(root.path, 'scan_pages'));
    if (!await pages.exists()) return;
    final cutoff = (now ?? DateTime.now()).subtract(const Duration(days: 7));
    await for (final entry in pages.list(followLinks: false)) {
      if (entry is! File ||
          p.extension(entry.path).toLowerCase() != '.jpg' ||
          protected.contains(p.normalize(p.absolute(entry.path)))) {
        continue;
      }
      try {
        if ((await entry.stat()).modified.isBefore(cutoff)) {
          await entry.delete();
        }
      } on FileSystemException {
        // A locked or removed working image must not prevent app startup.
      }
    }
  } on FileSystemException {
    // Cleanup is best effort; storage errors must not block the library.
  } on FormatException {
    // Preserve all photos when draft recovery data cannot be decoded.
  }
}
```

## `desktop/lib/core/scan_cleanup.dart`

```dart
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Run before opening scan screens so active captures cannot race cleanup.
Future<void> cleanOldScanImages({Directory? support, DateTime? now}) async {
  try {
    final root = support ?? await getApplicationSupportDirectory();
    final protected = <String>{};
    void collect(dynamic value) {
      if (value is String) {
        protected.add(p.normalize(p.absolute(value)));
      } else if (value is List) {
        value.forEach(collect);
      } else if (value is Map) {
        value.values.forEach(collect);
      }
    }

    for (final name in ['scan', 'card', 'card_side']) {
      for (final suffix in ['.json', '.json.new']) {
        final manifest = File(p.join(root.path, '${name}_draft$suffix'));
        if (await manifest.exists()) {
          // A damaged manifest might still describe recoverable photos.
          // Abort cleanup rather than guessing which photos are unreferenced.
          collect(jsonDecode(await manifest.readAsString()));
        }
      }
    }
    final pages = Directory(p.join(root.path, 'scan_pages'));
    if (!await pages.exists()) return;
    final cutoff = (now ?? DateTime.now()).subtract(const Duration(days: 7));
    await for (final entry in pages.list(followLinks: false)) {
      if (entry is! File ||
          p.extension(entry.path).toLowerCase() != '.jpg' ||
          protected.contains(p.normalize(p.absolute(entry.path)))) {
        continue;
      }
      try {
        if ((await entry.stat()).modified.isBefore(cutoff)) {
          await entry.delete();
        }
      } on FileSystemException {
        // A locked or removed working image must not prevent app startup.
      }
    }
  } on FileSystemException {
    // Cleanup is best effort; storage errors must not block the library.
  } on FormatException {
    // Preserve all photos when draft recovery data cannot be decoded.
  }
}
```
