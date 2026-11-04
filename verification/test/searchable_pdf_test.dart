import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'pdfium_test_support.dart';
import '../../mobile/lib/core/searchable_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeTestPdfium);
  test(
    'invisible word layer preserves searchable Latin and Devanagari Unicode',
    () async {
      final dir = await Directory.systemTemp.createTemp('docu_searchable_');
      try {
        final source = pw.Document();
        source.addPage(pw.Page(build: (_) => pw.Text('Visible page image')));
        final input = '${dir.path}/input.pdf',
            output = '${dir.path}/searchable.pdf';
        await File(input).writeAsBytes(await source.save());
        final latin = ByteData.sublistView(
          await File(
            '../mobile/assets/fonts/NotoSans-Regular.ttf',
          ).readAsBytes(),
        );
        final deva = ByteData.sublistView(
          await File(
            '../mobile/assets/fonts/NotoSansDevanagari-Regular.ttf',
          ).readAsBytes(),
        );
        await writeSearchablePdf(
          input,
          [
            {
              'page_index': 0,
              'words': jsonEncode([
                {'text': 'Invoice', 'x': .1, 'y': .1, 'w': .2, 'h': .04},
                {'text': 'नेपाल', 'x': .1, 'y': .2, 'w': .2, 'h': .04},
              ]),
            },
          ],
          output,
          latinFont: latin,
          devanagariFont: deva,
        );
        final doc = await PdfDocument.openFile(output);
        try {
          final text = (await doc.pages.first.loadStructuredText()).fullText;
          expect(text, contains('Invoice'));
          expect(text, contains('नेपाल'));
          expect(doc.pages.length, 1);
        } finally {
          doc.dispose();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
