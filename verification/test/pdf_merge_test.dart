import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'pdfium_test_support.dart';
import '../../mobile/lib/core/pdf_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeTestPdfium);
  test('merge keeps pages from both source PDFs in requested order', () async {
    final dir = await Directory.systemTemp.createTemp('docu_merge_');
    Future<String> fixture(String name, List<String> labels) async {
      final doc = pw.Document();
      for (final text in labels) {
        doc.addPage(pw.Page(build: (_) => pw.Text(text)));
      }
      final path = '${dir.path}/$name.pdf';
      await File(path).writeAsBytes(await doc.save());
      return path;
    }

    try {
      final a = await fixture('a', ['alpha', 'beta']);
      final b = await fixture('b', ['gamma']);
      final output = '${dir.path}/merged.pdf';
      await engine.assemble([
        PageRef(b, 0),
        PageRef(a, 1),
        PageRef(a, 0),
      ], output);
      final result = await PdfDocument.openFile(output);
      try {
        expect(result.pages.length, 3);
        expect(
          (await result.pages[0].loadStructuredText()).fullText,
          contains('gamma'),
        );
        expect(
          (await result.pages[1].loadStructuredText()).fullText,
          contains('beta'),
        );
        expect(
          (await result.pages[2].loadStructuredText()).fullText,
          contains('alpha'),
        );
      } finally {
        result.dispose();
      }
      expect(await File(a).exists(), isTrue);
      expect(await File(b).exists(), isTrue);
      await expectLater(
        engine.assemble([PageRef(a, 99)], '${dir.path}/bad.pdf'),
        throwsA(isA<FormatException>()),
      );
      expect(await File('${dir.path}/bad.pdf').exists(), isFalse);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
