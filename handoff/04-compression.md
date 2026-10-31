# 04-compression

Complete final integrated files. Apply the bundle as a whole; shared imports cross feature boundaries.

See [test steps and limits](README.md).

## `mobile/lib/core/pdf_engine.dart`

```dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/painting.dart' show decodeImageFromList;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart' as pdflib;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

/// One page of some PDF on disk. The editor works only with these.
class PageRef {
  final String src;
  final int index; // 0-based
  const PageRef(this.src, this.index);
}

/// How hard to compress. Pages are re-rendered as JPEG at [dpi].
class CompressQuality {
  static const small = CompressQuality('Small', 'Smallest file.', 100, 55);
  static const balanced = CompressQuality(
      'Optimal (recommended)', 'Automatic size and quality.', 175, 73);
  static const high = CompressQuality('High', 'Sharper text.', 200, 82);
  static const values = [balanced];
  const CompressQuality(this.label, this.hint, this.dpi, this.jpegQuality,
      {this.targetBytes});
  final String label;
  final String hint;
  final int dpi;
  final int jpegQuality;
  final int? targetBytes;
}

class CompressionCancelled implements Exception {}

typedef ProgressFn = void Function(int done, int total);

/// Everything the UI needs from a PDF backend.
abstract class PdfEngine {
  Future<int> pageCount(String path);

  /// Build a new PDF from any pages of any PDFs, in the given order.
  /// This single operation covers merge, split/extract, reorder, delete,
  /// replace and insert.
  Future<void> assemble(List<PageRef> pages, String outPath);

  /// One image per page.
  Future<void> imagesToPdf(List<String> images, String outPath,
      {ProgressFn? onProgress});

  /// Like [assemble], but every page is re-rendered as a JPEG, which shrinks
  /// scanned documents a lot. Text is no longer selectable in the result.
  Future<void> compress(
    List<PageRef> pages,
    String outPath,
    CompressQuality quality, {
    ProgressFn? onProgress,
  });
}

/// Runs in a background isolate. Args: BGRA pixels, width, height, quality.
Uint8List _encodeJpg((Uint8List, int, int, int) a) {
  final im = img.Image.fromBytes(
    width: a.$2,
    height: a.$3,
    bytes: a.$1.buffer,
    numChannels: 4,
    order: img.ChannelOrder.bgra,
  );
  var colored = 0, sampled = 0;
  for (var y = 0; y < im.height; y += 8) {
    for (var x = 0; x < im.width; x += 8) {
      final p = im.getPixel(x, y);
      sampled++;
      if (math.max(p.r, math.max(p.g, p.b)) -
              math.min(p.r, math.min(p.g, p.b)) >
          18) {
        colored++;
      }
    }
  }
  final output = colored / math.max(1, sampled) < .015 ? img.grayscale(im) : im;
  return img.encodeJpg(output, quality: a.$4);
}

class PdfrxEngine implements PdfEngine {
  @override
  Future<int> pageCount(String path) async {
    final doc = await PdfDocument.openFile(path);
    try {
      return doc.pages.length;
    } finally {
      doc.dispose();
    }
  }

  @override
  Future<void> assemble(List<PageRef> pages, String outPath) async {
    if (pages.isEmpty) {
      throw const FormatException('Choose at least one page to merge.');
    }
    final docs = <String, PdfDocument>{};
    PdfDocument? out;
    try {
      for (final s in {for (final r in pages) r.src}) {
        docs[s] = await PdfDocument.openFile(s);
      }
      for (final r in pages) {
        if (r.index < 0 || r.index >= docs[r.src]!.pages.length) {
          throw const FormatException(
              'A selected page is no longer available. Reopen the files and try again.');
        }
      }
      out = await PdfDocument.createNew(sourceName: p.basename(outPath));
      out.pages = [for (final r in pages) docs[r.src]!.pages[r.index]];
      final bytes = await out.encodePdf();
      await File(outPath).writeAsBytes(bytes, flush: true);
    } finally {
      out?.dispose();
      for (final d in docs.values) {
        d.dispose();
      }
    }
  }

  @override
  Future<void> compress(
    List<PageRef> pages,
    String outPath,
    CompressQuality quality, {
    ProgressFn? onProgress,
  }) async {
    if (pages.isEmpty) {
      throw const FormatException('Choose at least one page to compress.');
    }
    if (quality.targetBytes != null) {
      final candidate = '$outPath.candidate.pdf';
      final best = '$outPath.best.pdf';
      var smallest = 1 << 62;
      var fits = false;
      try {
        for (final dpi in [200, 175, 150, 125, 100, 80, 60]) {
          var low = 40, high = 90;
          while (low <= high) {
            final q = (low + high) ~/ 2;
            onProgress?.call(0, pages.length);
            await compress(
                pages, candidate, CompressQuality('Target', '', dpi, q),
                onProgress: onProgress);
            final bytes = await File(candidate).length();
            final candidateFits = bytes <= quality.targetBytes!;
            if (candidateFits || (!fits && bytes < smallest)) {
              await File(candidate).copy(best);
              smallest = bytes;
            }
            if (candidateFits) {
              fits = true;
              low = q + 1;
            } else {
              high = q - 1;
            }
          }
          if (fits) break;
        }
        await File(best).copy(outPath);
      } finally {
        for (final path in [candidate, best]) {
          final f = File(path);
          if (await f.exists()) await f.delete();
        }
      }
      return;
    }
    final docs = <String, PdfDocument>{};
    try {
      for (final s in {for (final r in pages) r.src}) {
        docs[s] = await PdfDocument.openFile(s);
      }
      final out = pw.Document();
      final scale = quality.dpi / 72.0;
      for (var i = 0; i < pages.length; i++) {
        final r = pages[i];
        final page = docs[r.src]!.pages[r.index];
        var w = (page.width * scale).round();
        var h = (page.height * scale).round();
        final longest = math.max(w, h);
        if (longest > 3000) {
          final f = 3000 / longest;
          w = (w * f).round();
          h = (h * f).round();
        }
        final image = await page.render(
          width: w,
          height: h,
          fullWidth: w.toDouble(),
          fullHeight: h.toDouble(),
        );
        if (image == null) throw StateError('Could not render page ${i + 1}');
        final pixels = Uint8List.fromList(image.pixels); // own copy, offset 0
        final iw = image.width, ih = image.height;
        image.dispose();
        final jpg =
            await compute(_encodeJpg, (pixels, iw, ih, quality.jpegQuality));
        final photo = pw.MemoryImage(jpg);
        out.addPage(pw.Page(
          pageFormat: pdflib.PdfPageFormat(page.width, page.height),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(photo, fit: pw.BoxFit.fill),
          ),
        ));
        onProgress?.call(i + 1, pages.length);
      }
      await File(outPath).writeAsBytes(await out.save(), flush: true);
    } finally {
      for (final d in docs.values) {
        d.dispose();
      }
    }
  }

  @override
  Future<void> imagesToPdf(List<String> images, String outPath,
      {ProgressFn? onProgress}) async {
    final doc = pw.Document();
    var n = 0;
    for (final path in images) {
      final bytes = await File(path).readAsBytes();
      final decoded = await decodeImageFromList(bytes);
      final w = decoded.width.toDouble();
      final h = decoded.height.toDouble();
      decoded.dispose();
      // Page takes the image's own aspect (longest side 842pt = A4 length),
      // so cropped scans have no white bars.
      final scale = 842 / (w > h ? w : h);
      final photo = pw.MemoryImage(bytes);
      doc.addPage(pw.Page(
        pageFormat: pdflib.PdfPageFormat(w * scale, h * scale),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Image(photo, fit: pw.BoxFit.fill),
        ),
      ));
      onProgress?.call(++n, images.length);
    }
    await File(outPath).writeAsBytes(await doc.save(), flush: true);
  }
}

final PdfEngine engine = PdfrxEngine();

String friendlyError(Object e) {
  if (e is CompressionCancelled) return 'Compression cancelled. Original kept.';
  final s = e.toString();
  if (s.toLowerCase().contains('password')) {
    return 'This PDF is password-protected.';
  }
  if (e is FormatException) return e.message;
  if (e is FileSystemException) {
    return 'Could not read or save the file. Check free space and try again.';
  }
  return 'Could not process this document. Please reopen it and try again.';
}
```

## `mobile/lib/core/progress.dart`

```dart
import 'package:flutter/material.dart';

/// Modal progress dialog around [task]. The task reports (done, total) and
/// the bar fills; the dialog closes itself when the task ends (or throws).
Future<T> runWithProgress<T>(BuildContext context, String title,
    Future<T> Function(void Function(int done, int total) report) task,
    {VoidCallback? onCancel}) async {
  final progress = ValueNotifier<double?>(null);
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(title),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, v, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(value: v, minHeight: 8),
              ),
              const SizedBox(height: 12),
              Text(v == null ? 'Working...' : '${(v * 100).round()}%'),
            ],
          ),
        ),
        actions: [
          if (onCancel != null)
            TextButton(onPressed: onCancel, child: const Text('Cancel'))
        ],
      ),
    ),
  );
  try {
    return await task((done, total) {
      progress.value = total == 0 ? null : done / total;
    });
  } finally {
    nav.pop();
    // Not disposed: the closing dialog may rebuild once more; the notifier
    // is tiny and is garbage-collected with the route.
  }
}
```

## `mobile/lib/features/compress/compress_flow.dart`

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/pdf_engine.dart';
import '../../core/progress.dart';
import '../../core/pdf_helpers.dart';
import '../../core/toast.dart';
import '../documents/actions.dart';
import '../documents/document.dart';
import '../documents/document_screen.dart';

/// Small / Balanced / High. Null if dismissed.
Future<CompressQuality?> askQuality(BuildContext context,
    {int? originalBytes}) {
  final input = TextEditingController();
  var unit = 'MB';
  String? error;
  return showModalBottomSheet<CompressQuality>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text('Compress',
                        style: Theme.of(ctx).textTheme.titleMedium),
                    subtitle: const Text(
                        'Makes a smaller copy. Pages become images, so text can no longer be selected.'),
                  ),
                  if (originalBytes != null)
                    ListTile(
                      title: Text('Original size: ${fmtSize(originalBytes)}'),
                      subtitle: const Text(
                          'The final size depends on the page content and will be shown after compression.'),
                    ),
                  ListTile(
                    leading: const Icon(Icons.compress),
                    title: const Text('Optimal (recommended)'),
                    subtitle: const Text(
                        'Automatically balance clarity and file size'),
                    onTap: () => Navigator.pop(ctx, CompressQuality.balanced),
                  ),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(children: [
                        Expanded(
                            child: TextField(
                                controller: input,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                    labelText: 'Target size',
                                    hintText: 'For example, 2',
                                    errorText: error))),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                            value: unit,
                            items: [
                              for (final u in ['KB', 'MB'])
                                DropdownMenuItem(value: u, child: Text(u))
                            ],
                            onChanged: (v) => set(() => unit = v!)),
                      ])),
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: FilledButton(
                          onPressed: () {
                            final value = double.tryParse(
                                input.text.trim().replaceAll(',', '.'));
                            if (value == null ||
                                !value.isFinite ||
                                value <= 0) {
                              set(() => error = 'Enter a positive size.');
                              return;
                            }
                            final bytes =
                                (value * (unit == 'MB' ? 1024 * 1024 : 1024))
                                    .round();
                            if (bytes < 1) {
                              set(() => error = 'Enter at least 1 byte.');
                              return;
                            }
                            if (originalBytes != null &&
                                bytes >= originalBytes) {
                              set(() =>
                                  error = 'This file is already smaller.');
                              return;
                            }
                            Navigator.pop(
                                ctx,
                                CompressQuality('Target size',
                                    'Best quality within your target.', 200, 90,
                                    targetBytes: bytes));
                          },
                          child: const Text('Use target size'))),
                ],
              ),
            ))),
  );
}

Future<bool> compressWithOptions(BuildContext context, List<PageRef> pages,
    String output, CompressQuality quality) async {
  var cancelled = false;
  final baseline = '$output.original.pdf';
  try {
    await runWithProgress<void>(context, 'Compressing…', (report) async {
      await engine.assemble(pages, baseline);
      if (cancelled) throw CompressionCancelled();
      await engine.compress(pages, output, quality, onProgress: (done, total) {
        if (cancelled) throw CompressionCancelled();
        report(done, total);
      });
      if (await File(output).length() >= await File(baseline).length()) {
        await File(baseline).copy(output);
      }
    }, onCancel: () => cancelled = true);
  } finally {
    if (await File(baseline).exists()) await File(baseline).delete();
  }
  if (cancelled) throw CompressionCancelled();
  final bytes = await File(output).length();
  if (quality.targetBytes != null && bytes > quality.targetBytes!) {
    if (!context.mounted) return false;
    return await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
                    title: const Text('Target could not be reached'),
                    content: Text(
                        'Smallest size reached: ${fmtSize(bytes)}. Keep this copy?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Keep copy'))
                    ])) ==
        true;
  }
  return true;
}

/// Merge or Compress and merge. Returns true for compress, null if dismissed.
Future<bool?> askMergeMode(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.merge_type),
            title: const Text('Merge'),
            subtitle: const Text('Keep original quality'),
            onTap: () => Navigator.pop(ctx, false),
          ),
          ListTile(
            leading: const Icon(Icons.compress),
            title: const Text('Compress and merge'),
            subtitle: const Text('Smaller file; text becomes unselectable'),
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    ),
  );
}

Future<void> compressDocument(BuildContext context, Document doc) =>
    compressPdfFile(context,
        path: repoOf(context).pathOf(doc), title: doc.title);

/// Compresses any PDF into a *copy* in the library; the original is untouched.
Future<void> compressPdfFile(
  BuildContext context, {
  required String path,
  required String title,
}) async {
  final repo = repoOf(context);
  final messenger = ScaffoldMessenger.of(context);
  final nav = Navigator.of(context);
  try {
    final original = await File(path).length();
    if (!context.mounted) return;
    final q = await askQuality(context, originalBytes: original);
    if (q == null || !context.mounted) return;
    final n = await engine.pageCount(path);
    final tmp = await tempPdfPath();
    if (!context.mounted) return;
    final accepted = await compressWithOptions(
        context, [for (var i = 0; i < n; i++) PageRef(path, i)], tmp, q);
    if (!accepted) {
      if (await File(tmp).exists()) await File(tmp).delete();
      return;
    }
    final compressed = await File(tmp).length();
    if (compressed >= original) {
      await File(tmp).delete();
      toastOn(messenger,
          'No useful reduction: ${fmtSize(original)} original, ${fmtSize(compressed)} after compression. Original kept.');
      return;
    }
    final doc = await repo.addFile(tmp,
        title:
            '${title.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')}_compressed',
        compressed: true);
    toastOn(
      messenger,
      'Original: ${fmtSize(original)} · Compressed: ${fmtSize(compressed)}',
      actionLabel: 'Open',
      duration: const Duration(seconds: 5),
      onAction: () => nav.push(
          MaterialPageRoute<void>(builder: (_) => DocumentScreen(id: doc.id))),
    );
  } catch (e) {
    toastOn(messenger, friendlyError(e));
  }
}
```

## `mobile/lib/features/page_editor.dart`

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../core/format.dart';
import '../core/pdf_engine.dart';
import '../core/pdf_helpers.dart';
import '../core/progress.dart';
import '../core/toast.dart';
import 'documents/actions.dart';
import 'documents/document.dart';
import 'documents/document_screen.dart';
import 'page_card.dart';
import 'page_picker_screen.dart';
import 'pickers.dart';
import 'scan_flow.dart';
import 'compress/compress_flow.dart';

class _Pg {
  final PageRef ref;
  final int id;
  _Pg(this.ref, this.id);
}

/// Page-level editor: big page thumbnails you can select, drag to reorder,
/// delete, extract, replace (scan / other PDF / photos) or add to.
/// Nothing is written until the user taps Save.
class PageEditor extends StatefulWidget {
  /// Set only when editing a library document (enables "Replace original").
  final Document? original;
  final List<PageRef> initial;
  final String? defaultName;

  /// "Compress and merge": the Save dialog opens with compression selected.
  final bool compressByDefault;

  const PageEditor({
    super.key,
    this.original,
    required this.initial,
    this.defaultName,
    this.compressByDefault = false,
  });

  @override
  State<PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends State<PageEditor> {
  final Map<String, PdfDocument> _docs = {};
  final List<_Pg> _pages = [];
  final Set<int> _sel = {};
  int _nextId = 0;
  bool _loading = true;
  bool _busy = false;
  bool _dirty = false;
  String? _error;
  final ScrollController _scroll = ScrollController();
  final Map<String, String> _labels = {}; // src path -> friendly name

  String get _baseName => widget.original?.title ?? 'Document';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _ensureDocs(widget.initial);
      if (!mounted) return;
      setState(() {
        _pages.addAll([for (final r in widget.initial) _Pg(r, _nextId++)]);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final d in _docs.values) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _ensureDocs(List<PageRef> refs) async {
    for (final s in {for (final r in refs) r.src}) {
      if (!_docs.containsKey(s)) {
        _docs[s] = await PdfDocument.openFile(s);
      }
    }
  }

  void _toast(String msg) {
    toast(context, msg);
  }

  // ---------- selection & ordering ----------

  void _toggle(int id) => setState(() {
        if (!_sel.remove(id)) _sel.add(id);
      });

  void _move(int from, int to) {
    if (from == to) return;
    setState(() {
      _pages.insert(to, _pages.removeAt(from));
      _dirty = true;
    });
  }

  void _nudge(int delta) {
    final i = _pages.indexWhere((pg) => _sel.contains(pg.id));
    final j = i + delta;
    if (i < 0 || j < 0 || j >= _pages.length) return;
    _move(i, j);
  }

  void _delete() => setState(() {
        _pages.removeWhere((pg) => _sel.contains(pg.id));
        _sel.clear();
        _dirty = true;
      });

  // ---------- adding / replacing ----------

  Future<void> _addPages({required bool replace}) async {
    final src = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                replace ? 'Replace page with...' : 'Add pages from...',
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Scan'),
              onTap: () => Navigator.pop(ctx, 'scan'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Another PDF'),
              subtitle: const Text('Pick the pages you want'),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Photos'),
              onTap: () => Navigator.pop(ctx, 'photos'),
            ),
          ],
        ),
      ),
    );
    if (src == null || !mounted) return;
    try {
      List<PageRef>? refs;
      switch (src) {
        case 'scan':
          refs = await _fromScan();
        case 'pdf':
          refs = await _fromPdf();
        case 'photos':
          refs = await _fromPhotos();
      }
      if (refs == null || refs.isEmpty || !mounted) return;
      _labels.putIfAbsent(
          refs.first.src,
          () => switch (src) {
                'scan' => 'Scan',
                'photos' => 'Photos',
                _ => p.basenameWithoutExtension(refs!.first.src),
              });
      await _ensureDocs(refs);
      if (!mounted) return;
      _insert(refs, replace: replace);
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    }
  }

  Future<List<PageRef>?> _fromScan() async {
    final imgs = await scanAndReview(context, confirmLabel: 'Add pages');
    if (imgs == null || imgs.isEmpty) return null;
    return refsForPdf(await imagesToTempPdf(imgs));
  }

  Future<List<PageRef>?> _fromPdf() async {
    final picked = await pickPdf(context);
    if (picked == null || !mounted) return null;
    final path = picked.path;
    final idx = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(builder: (_) => PagePickerScreen(path: path)),
    );
    if (idx == null) return null;
    return [for (final i in idx) PageRef(path, i)];
  }

  Future<List<PageRef>?> _fromPhotos() async {
    final imgs = await pickImages();
    if (imgs.isEmpty) return null;
    return refsForPdf(await imagesToTempPdf(imgs));
  }

  /// One page selected: replace it, or insert after it. Otherwise: append.
  void _insert(List<PageRef> refs, {required bool replace}) {
    final fresh = [for (final r in refs) _Pg(r, _nextId++)];
    setState(() {
      final selIdx = [
        for (var i = 0; i < _pages.length; i++)
          if (_sel.contains(_pages[i].id)) i
      ];
      var at = _pages.length;
      if (selIdx.length == 1) {
        at = selIdx.first;
        if (replace) {
          _pages.removeAt(at);
        } else {
          at += 1;
        }
      }
      _pages.insertAll(at, fresh);
      _sel.clear();
      _dirty = true;
    });
  }

  // ---------- saving ----------

  Future<({String name, bool replace, CompressQuality? quality})?> _askSave({
    required String initial,
    required bool canReplace,
    required String title,
    bool canCompress = true,
    int? beforeBytes,
    bool alreadyCompressed = false,
  }) {
    final c = TextEditingController(text: initial);
    var replace = false;
    CompressQuality? quality = (canCompress && widget.compressByDefault)
        ? CompressQuality.balanced
        : null;
    return showDialog<({String name, bool replace, CompressQuality? quality})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: c,
                  enabled: !replace,
                  decoration: const InputDecoration(labelText: 'File name'),
                ),
                if (canReplace)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: replace,
                    onChanged: (v) => set(() => replace = v ?? false),
                    title: const Text('Replace original'),
                  ),
                if (alreadyCompressed)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text(
                        'These files are already compressed. Saving keeps their current quality.'),
                  ),
                if (canCompress) ...[
                  const SizedBox(height: 16),
                  Text('Compression',
                      style: Theme.of(ctx).textTheme.labelLarge),
                  if (beforeBytes != null)
                    Text('Estimated original size: ${fmtSize(beforeBytes)}'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Off'),
                        selected: quality == null,
                        onSelected: (_) => set(() => quality = null),
                      ),
                      for (final q in CompressQuality.values)
                        ChoiceChip(
                          label: Text(q.label),
                          selected: quality == q,
                          onSelected: (_) => set(() => quality = q),
                        ),
                    ],
                  ),
                  if (quality != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${quality!.hint} Pages become images, so text can no longer be selected.',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    const Text(
                        'The actual compressed size will be shown after saving.'),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(
                  ctx, (name: c.text, replace: replace, quality: quality)),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// Rough "before" size: each page's share of its source file.
  int _estimateBytes(List<PageRef> refs) {
    final perPage = <String, double>{};
    var total = 0.0;
    for (final r in refs) {
      total += perPage.putIfAbsent(r.src, () {
        final n = _docs[r.src]?.pages.length ?? 1;
        return File(r.src).lengthSync() / (n == 0 ? 1 : n);
      });
    }
    return total.round();
  }

  Future<void> _save() async {
    try {
      await _saveWithOptions();
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    }
  }

  Future<void> _saveWithOptions() async {
    final orig = widget.original;
    final repo = repoOf(context);
    final documents = await repo.list(const DocQuery());
    if (!mounted) return;
    final compressedPaths = {
      for (final doc in documents)
        if (doc.compressed) repo.pathOf(doc)
    };
    final alreadyCompressed = _pages.isNotEmpty &&
        _pages.every((pg) => compressedPaths.contains(pg.ref.src));
    final r = await _askSave(
      title: 'Save',
      initial: widget.defaultName ?? 'Document ${stamp()}',
      canReplace: orig != null,
      canCompress: !alreadyCompressed,
      alreadyCompressed: alreadyCompressed,
      beforeBytes: _estimateBytes([for (final pg in _pages) pg.ref]),
    );
    if (r == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final refs = [for (final pg in _pages) pg.ref];
      final tmp = await tempPdfPath();
      if (!mounted) return;
      var message = 'Saved ${refs.length} page${refs.length == 1 ? '' : 's'}';
      final q = r.quality == null
          ? null
          : await askQuality(context, originalBytes: _estimateBytes(refs));
      if (r.quality != null && q == null) return;
      if(!mounted)return;
      if (q != null) {
        final before = _estimateBytes(refs);
        if (!mounted) return;
        if (!await compressWithOptions(context, refs, tmp, q)) return;
        if (!mounted) return;
        final after = await File(tmp).length();
        message =
            '$message · Estimated original: ${fmtSize(before)} · Compressed: ${fmtSize(after)}';
      } else {
        await runWithProgress<void>(
          context,
          'Saving...',
          (report) => engine.assemble(refs, tmp),
        );
      }
      final String id;
      if (r.replace && orig != null && q == null) {
        id = (await repo.replaceFile(orig.id, tmp,
                compressed: q != null || alreadyCompressed))
            .id;
      } else {
        id = (await repo.addFile(tmp,
                title: q == null ? r.name : '${r.name}_compressed',
                compressed: q != null || alreadyCompressed))
            .id;
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final nav = Navigator.of(context);
      setState(() => _dirty = false);
      nav.pop();
      toastOn(
        messenger,
        message,
        actionLabel: 'Open',
        duration: const Duration(seconds: 5),
        onAction: () => nav.push(
            MaterialPageRoute<void>(builder: (_) => DocumentScreen(id: id))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _extract() async {
    final refs = [
      for (final pg in _pages)
        if (_sel.contains(pg.id)) pg.ref
    ];
    final r = await _askSave(
      title: 'Extract ${refs.length} page${refs.length == 1 ? '' : 's'}',
      initial: '$_baseName (pages)',
      canReplace: false,
      canCompress: false,
    );
    if (r == null || !mounted) return;
    setState(() => _busy = true);
    final repo = repoOf(context);
    try {
      final tmp = await tempPdfPath();
      await engine.assemble(refs, tmp);
      final documents = await repo.list(const DocQuery());
      final compressedPaths = {
        for (final doc in documents)
          if (doc.compressed) repo.pathOf(doc)
      };
      await repo.addFile(tmp,
          title: r.name,
          compressed: refs.isNotEmpty &&
              refs.every((ref) => compressedPaths.contains(ref.src)));
      if (!mounted) return;
      setState(() {
        _busy = false;
        _sel.clear();
      });
      _toast('Saved to Home');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(friendlyError(e));
    }
  }

  // ---------- UI ----------

  /// Called by the grid after a drop with a function that applies the move.
  void _onReorder(ReorderedListFunction reorderedListFunction) {
    final before = List<_Pg>.of(_pages);
    final updated =
        reorderedListFunction(List<_Pg>.of(_pages)).cast<_Pg>().toList();
    setState(() {
      _pages
        ..clear()
        ..addAll(updated);
      _dirty = true;
    });
    HapticFeedback.lightImpact();
    toast(
      context,
      'Page moved',
      actionLabel: 'Undo',
      duration: const Duration(seconds: 3),
      onAction: () {
        if (!mounted) return;
        setState(() {
          _pages
            ..clear()
            ..addAll(before);
        });
      },
    );
  }

  // ---------- source colors ----------

  static const _palette = [
    Color(0xFF3B82F6),
    Color(0xFFF59E0B),
    Color(0xFF10B981),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFF06B6D4),
  ];

  /// Sources in order of first appearance; colors only matter with 2+.
  List<String> get _sources {
    final seen = <String>[];
    for (final src in widget.initial.map((r) => r.src)) {
      if (!seen.contains(src)) seen.add(src);
    }
    for (final pg in _pages) {
      if (!seen.contains(pg.ref.src)) seen.add(pg.ref.src);
    }
    return seen;
  }

  bool get _multiSource => {for (final pg in _pages) pg.ref.src}.length >= 2;

  Color _colorOf(String src) =>
      _palette[_sources.indexOf(src).clamp(0, 1 << 20) % _palette.length];

  String _letterOf(String src) =>
      String.fromCharCode(65 + _sources.indexOf(src) % 26);

  String _labelOf(String src) => _labels[src] ?? 'File ${_letterOf(src)}';

  Widget _legend() {
    final srcs = [
      for (final s in _sources)
        if (_pages.any((pg) => pg.ref.src == s)) s
    ];
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final s in srcs) _sourceChip(s),
        ],
      ),
    );
  }

  Widget _sourceChip(String src) {
    final ids = [
      for (final pg in _pages)
        if (pg.ref.src == src) pg.id
    ];
    final selectedCount = ids.where(_sel.contains).length;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        showCheckmark: false,
        selected: selectedCount == ids.length,
        avatar: CircleAvatar(
          backgroundColor: _colorOf(src),
          child: Text(_letterOf(src),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ),
        label: Text(_sel.isEmpty
            ? '${_labelOf(src)} · ${ids.length} pages'
            : '${_labelOf(src)} · $selectedCount/${ids.length} selected for editing'),
        // Toggle this source without changing selections from other files.
        onSelected: _busy
            ? null
            : (selected) => setState(() {
                  if (selected) {
                    _sel.addAll(ids);
                  } else {
                    _sel.removeAll(ids);
                  }
                }),
      ),
    );
  }

  Widget _tile(int i) {
    final pg = _pages[i];
    final doc = _docs[pg.ref.src]!;
    final colored = _multiSource;
    return GestureDetector(
      key: ValueKey<String>(
          'page_${pg.id}'), // String key: the grid package reads keys as String
      onTap: () => _toggle(pg.id),
      child: PageCard(
        doc: doc,
        index: pg.ref.index,
        number: i + 1,
        selected: _sel.contains(pg.id),
        dimmed: _sel.isNotEmpty && !_sel.contains(pg.id),
        tint: colored ? _colorOf(pg.ref.src) : null,
        badge: colored ? _letterOf(pg.ref.src) : null,
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback? onTap) => InkWell(
        onTap: _busy ? null : onTap,
        child: SizedBox(
          width: 76,
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      );

  Widget _bar() {
    final one = _sel.length == 1;
    return Material(
      elevation: 8,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: _sel.isEmpty
              ? Row(children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _busy ? null : () => _addPages(replace: false),
                      icon: const Icon(Icons.add),
                      label: const Text('Add pages'),
                    ),
                  ),
                ])
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _action(Icons.delete_outline, 'Delete', _delete),
                    _action(Icons.file_download_outlined, 'Extract', _extract),
                    if (one) ...[
                      _action(Icons.swap_horiz, 'Replace',
                          () => _addPages(replace: true)),
                      _action(Icons.add, 'Insert after',
                          () => _addPages(replace: false)),
                      _action(Icons.arrow_back, 'Earlier', () => _nudge(-1)),
                      _action(Icons.arrow_forward, 'Later', () => _nudge(1)),
                    ],
                    _action(
                        Icons.deselect, 'Clear', () => setState(_sel.clear)),
                  ]),
                ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child:
              Padding(padding: const EdgeInsets.all(24), child: Text(_error!)));
    }
    final cols = (MediaQuery.of(context).size.width ~/ 170).clamp(2, 6);
    final selectedSources = {
      for (final pg in _pages)
        if (_sel.contains(pg.id)) pg.ref.src
    };
    final fileSummary = '${selectedSources.length} '
        '${selectedSources.length == 1 ? 'file' : 'files'} '
        '(${selectedSources.map(_letterOf).join(', ')})';
    return Column(
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_multiSource) _legend(),
        if (_multiSource)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  'All pages shown will be merged. Tap a file label to select pages for editing; tap again to deselect.'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _sel.isEmpty
                  ? '${_pages.length} pages  ·  Tap to select, hold and drag to reorder'
                  : '${_sel.length} of ${_pages.length} pages selected for editing'
                      '${_multiSource ? ' · $fileSummary' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        Expanded(
          child: _pages.isEmpty
              ? const Center(child: Text('No pages. Add some below.'))
              : ReorderableBuilder.builder(
                  scrollController: _scroll,
                  itemCount: _pages.length,
                  onReorder: _onReorder,
                  childBuilder: (itemBuilder) => GridView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.66,
                    ),
                    itemCount: _pages.length,
                    itemBuilder: (context, i) => itemBuilder(_tile(i), i),
                  ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.original != null ? _baseName : 'New PDF';
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Discard changes?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Keep editing')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Discard')),
            ],
          ),
        );
        if (discard == true && context.mounted) {
          setState(() => _dirty = false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title, overflow: TextOverflow.ellipsis),
          actions: [
            TextButton(
              onPressed: (_busy || _loading || _pages.isEmpty) ? null : _save,
              child: const Text('Save'),
            ),
          ],
        ),
        body: _body(),
        bottomNavigationBar: (_loading || _error != null) ? null : _bar(),
      ),
    );
  }
}
```

## `desktop/lib/core/pdf_engine.dart`

```dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/painting.dart' show decodeImageFromList;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart' as pdflib;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

/// One page of some PDF on disk. The editor works only with these.
class PageRef {
  final String src;
  final int index; // 0-based
  const PageRef(this.src, this.index);
}

/// How hard to compress. Pages are re-rendered as JPEG at [dpi].
class CompressQuality {
  static const small = CompressQuality('Small', 'Smallest file.', 100, 55);
  static const balanced = CompressQuality(
      'Optimal (recommended)', 'Automatic size and quality.', 175, 73);
  static const high = CompressQuality('High', 'Sharper text.', 200, 82);
  static const values = [balanced];
  const CompressQuality(this.label, this.hint, this.dpi, this.jpegQuality,
      {this.targetBytes});
  final String label;
  final String hint;
  final int dpi;
  final int jpegQuality;
  final int? targetBytes;
}

class CompressionCancelled implements Exception {}

typedef ProgressFn = void Function(int done, int total);

/// Everything the UI needs from a PDF backend.
abstract class PdfEngine {
  Future<int> pageCount(String path);

  /// Build a new PDF from any pages of any PDFs, in the given order.
  /// This single operation covers merge, split/extract, reorder, delete,
  /// replace and insert.
  Future<void> assemble(List<PageRef> pages, String outPath);

  /// One image per page.
  Future<void> imagesToPdf(List<String> images, String outPath,
      {ProgressFn? onProgress});

  /// Like [assemble], but every page is re-rendered as a JPEG, which shrinks
  /// scanned documents a lot. Text is no longer selectable in the result.
  Future<void> compress(
    List<PageRef> pages,
    String outPath,
    CompressQuality quality, {
    ProgressFn? onProgress,
  });
}

/// Runs in a background isolate. Args: BGRA pixels, width, height, quality.
Uint8List _encodeJpg((Uint8List, int, int, int) a) {
  final im = img.Image.fromBytes(
    width: a.$2,
    height: a.$3,
    bytes: a.$1.buffer,
    numChannels: 4,
    order: img.ChannelOrder.bgra,
  );
  var colored = 0, sampled = 0;
  for (var y = 0; y < im.height; y += 8) {
    for (var x = 0; x < im.width; x += 8) {
      final p = im.getPixel(x, y);
      sampled++;
      if (math.max(p.r, math.max(p.g, p.b)) -
              math.min(p.r, math.min(p.g, p.b)) >
          18) {
        colored++;
      }
    }
  }
  final output = colored / math.max(1, sampled) < .015 ? img.grayscale(im) : im;
  return img.encodeJpg(output, quality: a.$4);
}

class PdfrxEngine implements PdfEngine {
  @override
  Future<int> pageCount(String path) async {
    final doc = await PdfDocument.openFile(path);
    try {
      return doc.pages.length;
    } finally {
      doc.dispose();
    }
  }

  @override
  Future<void> assemble(List<PageRef> pages, String outPath) async {
    if (pages.isEmpty) {
      throw const FormatException('Choose at least one page to merge.');
    }
    final docs = <String, PdfDocument>{};
    PdfDocument? out;
    try {
      for (final s in {for (final r in pages) r.src}) {
        docs[s] = await PdfDocument.openFile(s);
      }
      for (final r in pages) {
        if (r.index < 0 || r.index >= docs[r.src]!.pages.length) {
          throw const FormatException(
              'A selected page is no longer available. Reopen the files and try again.');
        }
      }
      out = await PdfDocument.createNew(sourceName: p.basename(outPath));
      out.pages = [for (final r in pages) docs[r.src]!.pages[r.index]];
      final bytes = await out.encodePdf();
      await File(outPath).writeAsBytes(bytes, flush: true);
    } finally {
      out?.dispose();
      for (final d in docs.values) {
        d.dispose();
      }
    }
  }

  @override
  Future<void> compress(
    List<PageRef> pages,
    String outPath,
    CompressQuality quality, {
    ProgressFn? onProgress,
  }) async {
    if (pages.isEmpty) {
      throw const FormatException('Choose at least one page to compress.');
    }
    if (quality.targetBytes != null) {
      final candidate = '$outPath.candidate.pdf';
      final best = '$outPath.best.pdf';
      var smallest = 1 << 62;
      var fits = false;
      try {
        for (final dpi in [200, 175, 150, 125, 100, 80, 60]) {
          var low = 40, high = 90;
          while (low <= high) {
            final q = (low + high) ~/ 2;
            onProgress?.call(0, pages.length);
            await compress(
                pages, candidate, CompressQuality('Target', '', dpi, q),
                onProgress: onProgress);
            final bytes = await File(candidate).length();
            final candidateFits = bytes <= quality.targetBytes!;
            if (candidateFits || (!fits && bytes < smallest)) {
              await File(candidate).copy(best);
              smallest = bytes;
            }
            if (candidateFits) {
              fits = true;
              low = q + 1;
            } else {
              high = q - 1;
            }
          }
          if (fits) break;
        }
        await File(best).copy(outPath);
      } finally {
        for (final path in [candidate, best]) {
          final f = File(path);
          if (await f.exists()) await f.delete();
        }
      }
      return;
    }
    final docs = <String, PdfDocument>{};
    try {
      for (final s in {for (final r in pages) r.src}) {
        docs[s] = await PdfDocument.openFile(s);
      }
      final out = pw.Document();
      final scale = quality.dpi / 72.0;
      for (var i = 0; i < pages.length; i++) {
        final r = pages[i];
        final page = docs[r.src]!.pages[r.index];
        var w = (page.width * scale).round();
        var h = (page.height * scale).round();
        final longest = math.max(w, h);
        if (longest > 3000) {
          final f = 3000 / longest;
          w = (w * f).round();
          h = (h * f).round();
        }
        final image = await page.render(
          width: w,
          height: h,
          fullWidth: w.toDouble(),
          fullHeight: h.toDouble(),
        );
        if (image == null) throw StateError('Could not render page ${i + 1}');
        final pixels = Uint8List.fromList(image.pixels); // own copy, offset 0
        final iw = image.width, ih = image.height;
        image.dispose();
        final jpg =
            await compute(_encodeJpg, (pixels, iw, ih, quality.jpegQuality));
        final photo = pw.MemoryImage(jpg);
        out.addPage(pw.Page(
          pageFormat: pdflib.PdfPageFormat(page.width, page.height),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(photo, fit: pw.BoxFit.fill),
          ),
        ));
        onProgress?.call(i + 1, pages.length);
      }
      await File(outPath).writeAsBytes(await out.save(), flush: true);
    } finally {
      for (final d in docs.values) {
        d.dispose();
      }
    }
  }

  @override
  Future<void> imagesToPdf(List<String> images, String outPath,
      {ProgressFn? onProgress}) async {
    final doc = pw.Document();
    var n = 0;
    for (final path in images) {
      final bytes = await File(path).readAsBytes();
      final decoded = await decodeImageFromList(bytes);
      final w = decoded.width.toDouble();
      final h = decoded.height.toDouble();
      decoded.dispose();
      // Page takes the image's own aspect (longest side 842pt = A4 length),
      // so cropped scans have no white bars.
      final scale = 842 / (w > h ? w : h);
      final photo = pw.MemoryImage(bytes);
      doc.addPage(pw.Page(
        pageFormat: pdflib.PdfPageFormat(w * scale, h * scale),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Image(photo, fit: pw.BoxFit.fill),
        ),
      ));
      onProgress?.call(++n, images.length);
    }
    await File(outPath).writeAsBytes(await doc.save(), flush: true);
  }
}

final PdfEngine engine = PdfrxEngine();

String friendlyError(Object e) {
  if (e is CompressionCancelled) return 'Compression cancelled. Original kept.';
  final s = e.toString();
  if (s.toLowerCase().contains('password')) {
    return 'This PDF is password-protected.';
  }
  if (e is FormatException) return e.message;
  if (e is FileSystemException) {
    return 'Could not read or save the file. Check free space and try again.';
  }
  return 'Could not process this document. Please reopen it and try again.';
}
```

## `desktop/lib/core/progress.dart`

```dart
import 'package:flutter/material.dart';

/// Modal progress dialog around [task]. The task reports (done, total) and
/// the bar fills; the dialog closes itself when the task ends (or throws).
Future<T> runWithProgress<T>(BuildContext context, String title,
    Future<T> Function(void Function(int done, int total) report) task,
    {VoidCallback? onCancel}) async {
  final progress = ValueNotifier<double?>(null);
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(title),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, v, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(value: v, minHeight: 8),
              ),
              const SizedBox(height: 12),
              Text(v == null ? 'Working...' : '${(v * 100).round()}%'),
            ],
          ),
        ),
        actions: [
          if (onCancel != null)
            TextButton(onPressed: onCancel, child: const Text('Cancel'))
        ],
      ),
    ),
  );
  try {
    return await task((done, total) {
      progress.value = total == 0 ? null : done / total;
    });
  } finally {
    nav.pop();
    // Not disposed: the closing dialog may rebuild once more; the notifier
    // is tiny and is garbage-collected with the route.
  }
}
```

## `desktop/lib/features/compress/compress_flow.dart`

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/pdf_engine.dart';
import '../../core/progress.dart';
import '../../core/pdf_helpers.dart';
import '../../core/toast.dart';
import '../documents/actions.dart';
import '../documents/document.dart';
import '../documents/document_screen.dart';

/// Small / Balanced / High. Null if dismissed.
Future<CompressQuality?> askQuality(BuildContext context,
    {int? originalBytes}) {
  final input = TextEditingController();
  var unit = 'MB';
  String? error;
  return showModalBottomSheet<CompressQuality>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text('Compress',
                        style: Theme.of(ctx).textTheme.titleMedium),
                    subtitle: const Text(
                        'Makes a smaller copy. Pages become images, so text can no longer be selected.'),
                  ),
                  if (originalBytes != null)
                    ListTile(
                      title: Text('Original size: ${fmtSize(originalBytes)}'),
                      subtitle: const Text(
                          'The final size depends on the page content and will be shown after compression.'),
                    ),
                  ListTile(
                    leading: const Icon(Icons.compress),
                    title: const Text('Optimal (recommended)'),
                    subtitle: const Text(
                        'Automatically balance clarity and file size'),
                    onTap: () => Navigator.pop(ctx, CompressQuality.balanced),
                  ),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(children: [
                        Expanded(
                            child: TextField(
                                controller: input,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                    labelText: 'Target size',
                                    hintText: 'For example, 2',
                                    errorText: error))),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                            value: unit,
                            items: [
                              for (final u in ['KB', 'MB'])
                                DropdownMenuItem(value: u, child: Text(u))
                            ],
                            onChanged: (v) => set(() => unit = v!)),
                      ])),
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: FilledButton(
                          onPressed: () {
                            final value = double.tryParse(
                                input.text.trim().replaceAll(',', '.'));
                            if (value == null ||
                                !value.isFinite ||
                                value <= 0) {
                              set(() => error = 'Enter a positive size.');
                              return;
                            }
                            final bytes =
                                (value * (unit == 'MB' ? 1024 * 1024 : 1024))
                                    .round();
                            if (bytes < 1) {
                              set(() => error = 'Enter at least 1 byte.');
                              return;
                            }
                            if (originalBytes != null &&
                                bytes >= originalBytes) {
                              set(() =>
                                  error = 'This file is already smaller.');
                              return;
                            }
                            Navigator.pop(
                                ctx,
                                CompressQuality('Target size',
                                    'Best quality within your target.', 200, 90,
                                    targetBytes: bytes));
                          },
                          child: const Text('Use target size'))),
                ],
              ),
            ))),
  );
}

Future<bool> compressWithOptions(BuildContext context, List<PageRef> pages,
    String output, CompressQuality quality) async {
  var cancelled = false;
  final baseline = '$output.original.pdf';
  try {
    await runWithProgress<void>(context, 'Compressing…', (report) async {
      await engine.assemble(pages, baseline);
      if (cancelled) throw CompressionCancelled();
      await engine.compress(pages, output, quality, onProgress: (done, total) {
        if (cancelled) throw CompressionCancelled();
        report(done, total);
      });
      if (await File(output).length() >= await File(baseline).length()) {
        await File(baseline).copy(output);
      }
    }, onCancel: () => cancelled = true);
  } finally {
    if (await File(baseline).exists()) await File(baseline).delete();
  }
  if (cancelled) throw CompressionCancelled();
  final bytes = await File(output).length();
  if (quality.targetBytes != null && bytes > quality.targetBytes!) {
    if (!context.mounted) return false;
    return await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
                    title: const Text('Target could not be reached'),
                    content: Text(
                        'Smallest size reached: ${fmtSize(bytes)}. Keep this copy?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Keep copy'))
                    ])) ==
        true;
  }
  return true;
}

/// Merge or Compress and merge. Returns true for compress, null if dismissed.
Future<bool?> askMergeMode(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.merge_type),
            title: const Text('Merge'),
            subtitle: const Text('Keep original quality'),
            onTap: () => Navigator.pop(ctx, false),
          ),
          ListTile(
            leading: const Icon(Icons.compress),
            title: const Text('Compress and merge'),
            subtitle: const Text('Smaller file; text becomes unselectable'),
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    ),
  );
}

Future<void> compressDocument(BuildContext context, Document doc) =>
    compressPdfFile(context,
        path: repoOf(context).pathOf(doc), title: doc.title);

/// Compresses any PDF into a *copy* in the library; the original is untouched.
Future<void> compressPdfFile(
  BuildContext context, {
  required String path,
  required String title,
}) async {
  final repo = repoOf(context);
  final messenger = ScaffoldMessenger.of(context);
  final nav = Navigator.of(context);
  try {
    final original = await File(path).length();
    if (!context.mounted) return;
    final q = await askQuality(context, originalBytes: original);
    if (q == null || !context.mounted) return;
    final n = await engine.pageCount(path);
    final tmp = await tempPdfPath();
    if (!context.mounted) return;
    final accepted = await compressWithOptions(
        context, [for (var i = 0; i < n; i++) PageRef(path, i)], tmp, q);
    if (!accepted) {
      if (await File(tmp).exists()) await File(tmp).delete();
      return;
    }
    final compressed = await File(tmp).length();
    if (compressed >= original) {
      await File(tmp).delete();
      toastOn(messenger,
          'No useful reduction: ${fmtSize(original)} original, ${fmtSize(compressed)} after compression. Original kept.');
      return;
    }
    final doc = await repo.addFile(tmp,
        title:
            '${title.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')}_compressed',
        compressed: true);
    toastOn(
      messenger,
      'Original: ${fmtSize(original)} · Compressed: ${fmtSize(compressed)}',
      actionLabel: 'Open',
      duration: const Duration(seconds: 5),
      onAction: () => nav.push(
          MaterialPageRoute<void>(builder: (_) => DocumentScreen(id: doc.id))),
    );
  } catch (e) {
    toastOn(messenger, friendlyError(e));
  }
}
```

## `desktop/lib/features/page_editor.dart`

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../core/format.dart';
import '../core/pdf_engine.dart';
import '../core/pdf_helpers.dart';
import '../core/progress.dart';
import '../core/toast.dart';
import 'documents/actions.dart';
import 'documents/document.dart';
import 'documents/document_screen.dart';
import 'page_card.dart';
import 'page_picker_screen.dart';
import 'pickers.dart';
import 'scan_flow.dart';
import 'compress/compress_flow.dart';

class _Pg {
  final PageRef ref;
  final int id;
  _Pg(this.ref, this.id);
}

/// Page-level editor: big page thumbnails you can select, drag to reorder,
/// delete, extract, replace (scan / other PDF / photos) or add to.
/// Nothing is written until the user taps Save.
class PageEditor extends StatefulWidget {
  /// Set only when editing a library document (enables "Replace original").
  final Document? original;
  final List<PageRef> initial;
  final String? defaultName;

  /// "Compress and merge": the Save dialog opens with compression selected.
  final bool compressByDefault;

  /// A merge is saved as a new document in this library folder.
  final String? outputFolderId;
  final bool mergeOutput;
  final bool openAfterSave;

  const PageEditor({
    super.key,
    this.original,
    required this.initial,
    this.defaultName,
    this.compressByDefault = false,
    this.outputFolderId,
    this.mergeOutput = false,
    this.openAfterSave = false,
  });

  @override
  State<PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends State<PageEditor> {
  final Map<String, PdfDocument> _docs = {};
  final List<_Pg> _pages = [];
  final Set<int> _sel = {};
  int _nextId = 0;
  bool _loading = true;
  bool _busy = false;
  bool _dirty = false;
  String? _error;
  final ScrollController _scroll = ScrollController();
  final Map<String, String> _labels = {}; // src path -> friendly name

  String get _baseName => widget.original?.title ?? 'Document';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _ensureDocs(widget.initial);
      if (!mounted) return;
      setState(() {
        _pages.addAll([for (final r in widget.initial) _Pg(r, _nextId++)]);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final d in _docs.values) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _ensureDocs(List<PageRef> refs) async {
    for (final s in {for (final r in refs) r.src}) {
      if (!_docs.containsKey(s)) {
        _docs[s] = await PdfDocument.openFile(s);
      }
    }
  }

  void _toast(String msg) {
    toast(context, msg);
  }

  // ---------- selection & ordering ----------

  void _toggle(int id) => setState(() {
        if (!_sel.remove(id)) _sel.add(id);
      });

  void _move(int from, int to) {
    if (from == to) return;
    setState(() {
      _pages.insert(to, _pages.removeAt(from));
      _dirty = true;
    });
  }

  void _nudge(int delta) {
    final i = _pages.indexWhere((pg) => _sel.contains(pg.id));
    final j = i + delta;
    if (i < 0 || j < 0 || j >= _pages.length) return;
    _move(i, j);
  }

  void _delete() => setState(() {
        _pages.removeWhere((pg) => _sel.contains(pg.id));
        _sel.clear();
        _dirty = true;
      });

  // ---------- adding / replacing ----------

  Future<void> _addPages({required bool replace}) async {
    final src = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                replace ? 'Replace page with...' : 'Add pages from...',
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Scan'),
              onTap: () => Navigator.pop(ctx, 'scan'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Another PDF'),
              subtitle: const Text('Pick the pages you want'),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Photos'),
              onTap: () => Navigator.pop(ctx, 'photos'),
            ),
          ],
        ),
      ),
    );
    if (src == null || !mounted) return;
    try {
      List<PageRef>? refs;
      switch (src) {
        case 'scan':
          refs = await _fromScan();
        case 'pdf':
          refs = await _fromPdf();
        case 'photos':
          refs = await _fromPhotos();
      }
      if (refs == null || refs.isEmpty || !mounted) return;
      _labels.putIfAbsent(
          refs.first.src,
          () => switch (src) {
                'scan' => 'Scan',
                'photos' => 'Photos',
                _ => p.basenameWithoutExtension(refs!.first.src),
              });
      await _ensureDocs(refs);
      if (!mounted) return;
      _insert(refs, replace: replace);
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    }
  }

  Future<List<PageRef>?> _fromScan() async {
    final imgs = await scanAndReview(context, confirmLabel: 'Add pages');
    if (imgs == null || imgs.isEmpty) return null;
    return refsForPdf(await imagesToTempPdf(imgs));
  }

  Future<List<PageRef>?> _fromPdf() async {
    final picked = await pickPdf(context);
    if (picked == null || !mounted) return null;
    final path = picked.path;
    final idx = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(builder: (_) => PagePickerScreen(path: path)),
    );
    if (idx == null) return null;
    return [for (final i in idx) PageRef(path, i)];
  }

  Future<List<PageRef>?> _fromPhotos() async {
    final imgs = await pickImages();
    if (imgs.isEmpty) return null;
    return refsForPdf(await imagesToTempPdf(imgs));
  }

  /// One page selected: replace it, or insert after it. Otherwise: append.
  void _insert(List<PageRef> refs, {required bool replace}) {
    final fresh = [for (final r in refs) _Pg(r, _nextId++)];
    setState(() {
      final selIdx = [
        for (var i = 0; i < _pages.length; i++)
          if (_sel.contains(_pages[i].id)) i
      ];
      var at = _pages.length;
      if (selIdx.length == 1) {
        at = selIdx.first;
        if (replace) {
          _pages.removeAt(at);
        } else {
          at += 1;
        }
      }
      _pages.insertAll(at, fresh);
      _sel.clear();
      _dirty = true;
    });
  }

  // ---------- saving ----------

  Future<({String name, bool replace, CompressQuality? quality})?> _askSave({
    required String initial,
    required bool canReplace,
    required String title,
    bool canCompress = true,
    int? beforeBytes,
    bool alreadyCompressed = false,
  }) {
    final c = TextEditingController(text: initial);
    var replace = false;
    CompressQuality? quality = (canCompress && widget.compressByDefault)
        ? CompressQuality.balanced
        : null;
    return showDialog<({String name, bool replace, CompressQuality? quality})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: c,
                  enabled: !replace,
                  decoration: const InputDecoration(labelText: 'File name'),
                ),
                if (canReplace)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: replace,
                    onChanged: (v) => set(() => replace = v ?? false),
                    title: const Text('Replace original'),
                  ),
                if (alreadyCompressed)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text(
                        'These files are already compressed. Saving keeps their current quality.'),
                  ),
                if (canCompress) ...[
                  const SizedBox(height: 16),
                  Text('Compression',
                      style: Theme.of(ctx).textTheme.labelLarge),
                  if (beforeBytes != null)
                    Text('Estimated original size: ${fmtSize(beforeBytes)}'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Off'),
                        selected: quality == null,
                        onSelected: (_) => set(() => quality = null),
                      ),
                      for (final q in CompressQuality.values)
                        ChoiceChip(
                          label: Text(q.label),
                          selected: quality == q,
                          onSelected: (_) => set(() => quality = q),
                        ),
                    ],
                  ),
                  if (quality != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${quality!.hint} Pages become images, so text can no longer be selected.',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    const Text(
                        'The actual compressed size will be shown after saving.'),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(
                  ctx, (name: c.text, replace: replace, quality: quality)),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// Rough "before" size: each page's share of its source file.
  int _estimateBytes(List<PageRef> refs) {
    final perPage = <String, double>{};
    var total = 0.0;
    for (final r in refs) {
      total += perPage.putIfAbsent(r.src, () {
        final n = _docs[r.src]?.pages.length ?? 1;
        return File(r.src).lengthSync() / (n == 0 ? 1 : n);
      });
    }
    return total.round();
  }

  Future<void> _save() async {
    try {
      await _saveWithOptions();
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    }
  }

  Future<void> _saveWithOptions() async {
    final orig = widget.original;
    final repo = repoOf(context);
    final documents = await repo.list(const DocQuery());
    if (!mounted) return;
    final compressedPaths = {
      for (final doc in documents)
        if (doc.compressed) repo.pathOf(doc)
    };
    final alreadyCompressed = _pages.isNotEmpty &&
        _pages.every((pg) => compressedPaths.contains(pg.ref.src));
    final r = await _askSave(
      title: widget.mergeOutput ? 'Save merged PDF' : 'Save',
      initial: widget.defaultName ?? 'Document ${stamp()}',
      canReplace: orig != null,
      canCompress: !alreadyCompressed,
      alreadyCompressed: alreadyCompressed,
      beforeBytes: _estimateBytes([for (final pg in _pages) pg.ref]),
    );
    if (r == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final refs = [for (final pg in _pages) pg.ref];
      final tmp = await tempPdfPath();
      if (!mounted) return;
      var message = 'Saved ${refs.length} page${refs.length == 1 ? '' : 's'}';
      final q = r.quality == null
          ? null
          : await askQuality(context, originalBytes: _estimateBytes(refs));
      if (r.quality != null && q == null) return;
      if(!mounted)return;
      if (q != null) {
        final before = _estimateBytes(refs);
        if (!mounted) return;
        if (!await compressWithOptions(context, refs, tmp, q)) return;
        if (!mounted) return;
        final after = await File(tmp).length();
        message =
            '$message · Estimated original: ${fmtSize(before)} · Compressed: ${fmtSize(after)}';
      } else {
        await runWithProgress<void>(
          context,
          'Saving...',
          (report) => engine.assemble(refs, tmp),
        );
      }
      final String id;
      if (r.replace && orig != null && q == null) {
        id = (await repo.replaceFile(orig.id, tmp,
                compressed: q != null || alreadyCompressed))
            .id;
      } else {
        id = (await repo.addFile(tmp,
                title: q == null ? r.name : '${r.name}_compressed',
                compressed: q != null || alreadyCompressed,
                folderId: widget.outputFolderId))
            .id;
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final nav = Navigator.of(context);
      setState(() => _dirty = false);
      if (widget.openAfterSave) {
        nav.pushReplacement(
            MaterialPageRoute<void>(builder: (_) => DocumentScreen(id: id)));
        toastOn(messenger, message);
      } else {
        nav.pop();
        toastOn(
          messenger,
          message,
          actionLabel: 'Open',
          duration: const Duration(seconds: 5),
          onAction: () => nav.push(
              MaterialPageRoute<void>(builder: (_) => DocumentScreen(id: id))),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _extract() async {
    final refs = [
      for (final pg in _pages)
        if (_sel.contains(pg.id)) pg.ref
    ];
    final r = await _askSave(
      title: 'Extract ${refs.length} page${refs.length == 1 ? '' : 's'}',
      initial: '$_baseName (pages)',
      canReplace: false,
      canCompress: false,
    );
    if (r == null || !mounted) return;
    setState(() => _busy = true);
    final repo = repoOf(context);
    try {
      final tmp = await tempPdfPath();
      await engine.assemble(refs, tmp);
      final documents = await repo.list(const DocQuery());
      final compressedPaths = {
        for (final doc in documents)
          if (doc.compressed) repo.pathOf(doc)
      };
      await repo.addFile(tmp,
          title: r.name,
          compressed: refs.isNotEmpty &&
              refs.every((ref) => compressedPaths.contains(ref.src)));
      if (!mounted) return;
      setState(() {
        _busy = false;
        _sel.clear();
      });
      _toast('Saved to Home');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(friendlyError(e));
    }
  }

  // ---------- UI ----------

  /// Called by the grid after a drop with a function that applies the move.
  void _onReorder(ReorderedListFunction reorderedListFunction) {
    final before = List<_Pg>.of(_pages);
    final updated =
        reorderedListFunction(List<_Pg>.of(_pages)).cast<_Pg>().toList();
    setState(() {
      _pages
        ..clear()
        ..addAll(updated);
      _dirty = true;
    });
    HapticFeedback.lightImpact();
    toast(
      context,
      'Page moved',
      actionLabel: 'Undo',
      duration: const Duration(seconds: 3),
      onAction: () {
        if (!mounted) return;
        setState(() {
          _pages
            ..clear()
            ..addAll(before);
        });
      },
    );
  }

  // ---------- source colors ----------

  static const _palette = [
    Color(0xFF3B82F6),
    Color(0xFFF59E0B),
    Color(0xFF10B981),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFF06B6D4),
  ];

  /// Sources in order of first appearance; colors only matter with 2+.
  List<String> get _sources {
    final seen = <String>[];
    for (final src in widget.initial.map((r) => r.src)) {
      if (!seen.contains(src)) seen.add(src);
    }
    for (final pg in _pages) {
      if (!seen.contains(pg.ref.src)) seen.add(pg.ref.src);
    }
    return seen;
  }

  bool get _multiSource => {for (final pg in _pages) pg.ref.src}.length >= 2;

  Color _colorOf(String src) =>
      _palette[_sources.indexOf(src).clamp(0, 1 << 20) % _palette.length];

  String _letterOf(String src) =>
      String.fromCharCode(65 + _sources.indexOf(src) % 26);

  String _labelOf(String src) => _labels[src] ?? 'File ${_letterOf(src)}';

  Widget _legend() {
    final srcs = [
      for (final s in _sources)
        if (_pages.any((pg) => pg.ref.src == s)) s
    ];
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final s in srcs) _sourceChip(s),
        ],
      ),
    );
  }

  Widget _sourceChip(String src) {
    final ids = [
      for (final pg in _pages)
        if (pg.ref.src == src) pg.id
    ];
    final selectedCount = ids.where(_sel.contains).length;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        showCheckmark: false,
        selected: selectedCount == ids.length,
        avatar: CircleAvatar(
          backgroundColor: _colorOf(src),
          child: Text(_letterOf(src),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ),
        label: Text(_sel.isEmpty
            ? '${_labelOf(src)} · ${ids.length} pages'
            : '${_labelOf(src)} · $selectedCount/${ids.length} selected for editing'),
        // Toggle this source without changing selections from other files.
        onSelected: _busy
            ? null
            : (selected) => setState(() {
                  if (selected) {
                    _sel.addAll(ids);
                  } else {
                    _sel.removeAll(ids);
                  }
                }),
      ),
    );
  }

  Widget _tile(int i) {
    final pg = _pages[i];
    final doc = _docs[pg.ref.src]!;
    final colored = _multiSource;
    return GestureDetector(
      key: ValueKey<String>(
          'page_${pg.id}'), // String key: the grid package reads keys as String
      onTap: () => _toggle(pg.id),
      child: PageCard(
        doc: doc,
        index: pg.ref.index,
        number: i + 1,
        selected: _sel.contains(pg.id),
        tint: colored ? _colorOf(pg.ref.src) : null,
        badge: colored ? _letterOf(pg.ref.src) : null,
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback? onTap) => InkWell(
        onTap: _busy ? null : onTap,
        child: SizedBox(
          width: 76,
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      );

  Widget _bar() {
    final one = _sel.length == 1;
    return Material(
      elevation: 8,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: _sel.isEmpty
              ? Row(children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _busy ? null : () => _addPages(replace: false),
                      icon: const Icon(Icons.add),
                      label: const Text('Add pages'),
                    ),
                  ),
                ])
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _action(Icons.delete_outline, 'Delete', _delete),
                    _action(Icons.file_download_outlined, 'Extract', _extract),
                    if (one) ...[
                      _action(Icons.swap_horiz, 'Replace',
                          () => _addPages(replace: true)),
                      _action(Icons.add, 'Insert after',
                          () => _addPages(replace: false)),
                      _action(Icons.arrow_back, 'Earlier', () => _nudge(-1)),
                      _action(Icons.arrow_forward, 'Later', () => _nudge(1)),
                    ],
                    _action(
                        Icons.deselect, 'Clear', () => setState(_sel.clear)),
                  ]),
                ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child:
              Padding(padding: const EdgeInsets.all(24), child: Text(_error!)));
    }
    final cols = (MediaQuery.of(context).size.width ~/ 170).clamp(2, 6);
    final selectedSources = {
      for (final pg in _pages)
        if (_sel.contains(pg.id)) pg.ref.src
    };
    final fileSummary = '${selectedSources.length} '
        '${selectedSources.length == 1 ? 'file' : 'files'} '
        '(${selectedSources.map(_letterOf).join(', ')})';
    final desktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    return Column(
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_multiSource) _legend(),
        if (_multiSource)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  'All pages shown will be merged. Tap a file label to select pages for editing; tap again to deselect.'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _sel.isEmpty
                  ? '${_pages.length} pages  ·  ${desktop ? 'Click' : 'Tap'} to select, ${desktop ? 'drag' : 'hold and drag'} to reorder'
                  : '${_sel.length} of ${_pages.length} pages selected for editing'
                      '${_multiSource ? ' · $fileSummary' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        Expanded(
          child: _pages.isEmpty
              ? const Center(child: Text('No pages. Add some below.'))
              : ReorderableBuilder.builder(
                  scrollController: _scroll,
                  itemCount: _pages.length,
                  onReorder: _onReorder,
                  longPressDelay: desktop
                      ? Duration.zero
                      : const Duration(milliseconds: 500),
                  childBuilder: (itemBuilder) => GridView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.66,
                    ),
                    itemCount: _pages.length,
                    itemBuilder: (context, i) => itemBuilder(_tile(i), i),
                  ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.original != null
        ? _baseName
        : widget.mergeOutput
            ? 'Merge PDFs'
            : 'New PDF';
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Discard changes?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Keep editing')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Discard')),
            ],
          ),
        );
        if (discard == true && context.mounted) {
          setState(() => _dirty = false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title, overflow: TextOverflow.ellipsis),
          actions: [
            TextButton(
              onPressed: (_busy || _loading || _pages.isEmpty) ? null : _save,
              child: Text(widget.mergeOutput ? 'Save merged PDF' : 'Save'),
            ),
          ],
        ),
        body: _body(),
        bottomNavigationBar: (_loading || _error != null) ? null : _bar(),
      ),
    );
  }
}
```
