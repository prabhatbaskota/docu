import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/painting.dart' show decodeImageFromList, Rect;
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
  /// Rasterize only the retained area, so excluded content is not embedded.
  Future<void> cropPage(PageRef ref, Rect crop, String outPath) async {
    if (!crop.left.isFinite ||
        !crop.top.isFinite ||
        !crop.right.isFinite ||
        !crop.bottom.isFinite ||
        crop.left < 0 ||
        crop.top < 0 ||
        crop.right > 1 ||
        crop.bottom > 1 ||
        crop.width < .02 ||
        crop.height < .02) {
      throw const FormatException('Select a larger area within the page.');
    }
    final doc = await PdfDocument.openFile(ref.src);
    try {
      final page = doc.pages[ref.index];
      final scale =
          math.min(300 / 72, 4000 / math.max(page.width, page.height));
      final fullWidth = (page.width * scale).round();
      final fullHeight = (page.height * scale).round();
      final x = (crop.left * fullWidth).round();
      final y = (crop.top * fullHeight).round();
      final image = await page.render(
          x: x,
          y: y,
          width: math.max(1, (crop.right * fullWidth).round() - x),
          height: math.max(1, (crop.bottom * fullHeight).round() - y),
          fullWidth: fullWidth.toDouble(),
          fullHeight: fullHeight.toDouble());
      if (image == null) {
        throw StateError('Could not render the selected area.');
      }
      late Uint8List png;
      try {
        png = await compute(_encodeCrop,
            (Uint8List.fromList(image.pixels), image.width, image.height));
      } finally {
        image.dispose();
      }
      final out = pw.Document();
      out.addPage(pw.Page(
        pageFormat: pdflib.PdfPageFormat(
            page.width * crop.width, page.height * crop.height),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill)),
      ));
      await File(outPath).writeAsBytes(await out.save(), flush: true);
    } finally {
      doc.dispose();
    }
  }

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

Uint8List _encodeCrop((Uint8List, int, int) data) =>
    img.encodePng(img.Image.fromBytes(
      width: data.$2,
      height: data.$3,
      bytes: data.$1.buffer,
      numChannels: 4,
      order: img.ChannelOrder.bgra,
    ));

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
