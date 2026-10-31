import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

Uint8List _jpg((Uint8List,int,int) a)=>img.encodeJpg(img.Image.fromBytes(
  width:a.$2,height:a.$3,bytes:a.$1.buffer,numChannels:4,order:img.ChannelOrder.bgra),quality:90);

/// Visible page raster plus Unicode word text using PDF text rendering mode 3.
Future<void> writeSearchablePdf(String sourcePath,List<Map<String,Object?>> recognized,String output,
    {ByteData? latinFont,ByteData? devanagariFont})async {
    final latin =
        pw.Font.ttf(latinFont ?? await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final deva = pw.Font.ttf(
        devanagariFont ?? await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf'));
    final source = await PdfDocument.openFile(sourcePath);
    final out = pw.Document();
    try {
      for (var i = 0; i < source.pages.length; i++) {
        final p = source.pages[i];
        final scale = math.min(2.5, 3000 / math.max(p.width, p.height));
        final raster = await p.render(
            width: (p.width * scale).round(),
            height: (p.height * scale).round());
        if (raster == null) {
          throw const FormatException('Could not export this page.');
        }
        final pixels = Uint8List.fromList(raster.pixels),
            w = raster.width,
            h = raster.height;
        raster.dispose();
        final image = pw.MemoryImage(await compute(_jpg, (pixels, w, h)));
        final row = recognized.where((r) => r['page_index'] == i).firstOrNull;
        final words =
            row == null ? [] : jsonDecode(row['words'] as String) as List;
        out.addPage(pw.Page(
            pageFormat: PdfPageFormat(p.width, p.height),
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Stack(children: [
                  pw.Positioned.fill(
                      child: pw.Image(image, fit: pw.BoxFit.fill)),
                  for (final word in words)
                    pw.Positioned(
                        left: (word['x'] as num) * p.width,
                        top: (word['y'] as num) * p.height,
                        child: pw.SizedBox(
                            width: math.max(1, (word['w'] as num) * p.width),
                            height: math.max(1, (word['h'] as num) * p.height),
                            child: pw.FittedBox(
                                fit: pw.BoxFit.fill,
                                child: pw.Text(word['text'] as String,
                                    style: pw.TextStyle(
                                        font: RegExp(r'[\u0900-\u097f]')
                                                .hasMatch(word['text'])
                                            ? deva
                                            : latin,
                                        fontSize: 12,
                                        renderingMode:
                                            PdfTextRenderingMode.invisible))))),
                ])));
      }
      await File(output).writeAsBytes(await out.save(), flush: true);
    } finally {
      source.dispose();
    }
}
