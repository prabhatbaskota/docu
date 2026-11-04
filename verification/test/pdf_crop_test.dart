import 'dart:io';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat, PdfColors;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'pdfium_test_support.dart';
import '../../mobile/lib/core/pdf_engine.dart' as mobile;
import '../../desktop/lib/core/pdf_engine.dart' as desktop;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeTestPdfium();
  });
  for (final app in ['mobile', 'desktop']) {
    test(
      '$app crop retains selected pixels and survives PDF assembly',
      () async {
        final dir = await Directory.systemTemp.createTemp('docu_crop_');
        try {
          final source = '${dir.path}/source.pdf';
          final cropped = '${dir.path}/crop.pdf';
          final merged = '${dir.path}/merged.pdf';
          final pdf = pw.Document();
          pdf.addPage(
            pw.Page(
              pageFormat: const PdfPageFormat(200, 100),
              margin: pw.EdgeInsets.zero,
              build: (_) => pw.Row(
                children: [
                  pw.Expanded(child: pw.Container(color: PdfColors.red)),
                  pw.Expanded(child: pw.Container(color: PdfColors.blue)),
                ],
              ),
            ),
          );
          await File(source).writeAsBytes(await pdf.save());
          final original = await File(source).readAsBytes();
          const area = Rect.fromLTWH(.5, 0, .5, 1);
          if (app == 'mobile') {
            await mobile.PdfrxEngine().cropPage(
              mobile.PageRef(source, 0),
              area,
              cropped,
            );
            await mobile.engine.assemble([
              mobile.PageRef(cropped, 0),
              mobile.PageRef(source, 0),
            ], merged);
            await expectLater(
              mobile.PdfrxEngine().cropPage(
                mobile.PageRef(source, 0),
                const Rect.fromLTWH(0, 0, 0, 1),
                cropped,
              ),
              throwsFormatException,
            );
          } else {
            await desktop.PdfrxEngine().cropPage(
              desktop.PageRef(source, 0),
              area,
              cropped,
            );
            await desktop.engine.assemble([
              desktop.PageRef(cropped, 0),
              desktop.PageRef(source, 0),
            ], merged);
          }
          final result = await PdfDocument.openFile(merged);
          try {
            expect(result.pages.length, 2);
            expect(result.pages.first.width, closeTo(100, .1));
            expect(result.pages.first.height, closeTo(100, .1));
            final image = await result.pages.first.render(
              width: 20,
              height: 20,
              fullWidth: 20,
              fullHeight: 20,
            );
            try {
              // BGRA: every retained pixel is blue, with no red half remaining.
              for (var i = 0; i < image!.pixels.length; i += 4) {
                expect(image.pixels[i], greaterThan(200));
                expect(image.pixels[i + 2], lessThan(60));
              }
            } finally {
              image?.dispose();
            }
            expect(result.pages[1].width, closeTo(200, .1));
          } finally {
            result.dispose();
          }
          expect(await File(source).readAsBytes(), original);
        } finally {
          await dir.delete(recursive: true);
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
