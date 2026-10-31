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
