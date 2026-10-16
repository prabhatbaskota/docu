import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'pdf_engine.dart';

/// Every page of a PDF as PageRefs.
Future<List<PageRef>> refsForPdf(String path) async {
  final n = await engine.pageCount(path);
  return [for (var i = 0; i < n; i++) PageRef(path, i)];
}

/// Turns captured/picked images into a temporary PDF so their pages can be
/// handled exactly like pages of any other PDF.
Future<String> imagesToTempPdf(List<String> images) async {
  final tmp = await getTemporaryDirectory();
  final path =
      p.join(tmp.path, 'pages_${DateTime.now().microsecondsSinceEpoch}.pdf');
  await engine.imagesToPdf(images, path);
  return path;
}

/// A fresh path in the temp folder for an assembled PDF before it is filed.
Future<String> tempPdfPath() async {
  final tmp = await getTemporaryDirectory();
  return p.join(tmp.path, 'out_${DateTime.now().microsecondsSinceEpoch}.pdf');
}
