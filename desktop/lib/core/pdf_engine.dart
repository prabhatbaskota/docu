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
enum CompressQuality {
  small('Small', 'Smallest file. Good for chat and email.', 100, 55),
  balanced('Balanced', 'Good for most documents.', 140, 70),
  high('High', 'Sharper text, larger file.', 200, 82);

  const CompressQuality(this.label, this.hint, this.dpi, this.jpegQuality);
  final String label;
  final String hint;
  final int dpi;
  final int jpegQuality;
}

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
  return img.encodeJpg(im, quality: a.$4);
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
    final docs = <String, PdfDocument>{};
    PdfDocument? out;
    try {
      for (final s in {for (final r in pages) r.src}) {
        docs[s] = await PdfDocument.openFile(s);
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
  final s = e.toString();
  if (s.toLowerCase().contains('password')) {
    return 'This PDF is password-protected.';
  }
  if (e is FormatException) return e.message;
  return s;
}
