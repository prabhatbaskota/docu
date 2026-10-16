import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/format.dart';
import '../core/pdf_engine.dart';
import '../core/toast.dart';
import 'compress/compress_flow.dart';
import 'documents/actions.dart';
import 'editor_launch.dart';
import 'pickers.dart';
import 'scan_flow.dart';

/// Registry of tools. Adding a tool = adding one entry here.
class Tool {
  final String name;
  final String hint;
  final IconData icon;
  final Future<void> Function(BuildContext) run;
  const Tool(this.name, this.hint, this.icon, this.run);
}

final tools = <Tool>[
  Tool('Scan', 'Camera to PDF', Icons.document_scanner_outlined,
      (c) => startScan(c)),
  Tool('Edit pages', 'Reorder, replace, insert', Icons.view_module_outlined,
      (c) async {
    final picked = await pickPdf(c);
    if (picked == null || !c.mounted) return;
    final doc = picked.doc;
    if (doc != null) {
      await editDocument(c, doc);
    } else {
      await editExternalPdf(c, picked.path);
    }
  }),
  Tool('Merge', 'Combine PDFs', Icons.merge_type, (c) async {
    try {
      final paths = await pickPdfsForMerge(c);
      if (paths == null || !c.mounted) return;
      final compress = await askMergeMode(c);
      if (compress == null || !c.mounted) return;
      await mergeIntoEditor(c, paths, compress: compress);
    } catch (e) {
      if (c.mounted) toast(c, friendlyError(e));
    }
  }),
  Tool('Compress', 'Make a PDF smaller', Icons.compress, (c) async {
    final picked = await pickPdf(c);
    if (picked == null || !c.mounted) return;
    await compressPdfFile(
      c,
      path: picked.path,
      title: picked.doc?.title ?? p.basenameWithoutExtension(picked.path),
    );
  }),
  Tool('Photos to PDF', 'Gallery images into a PDF', Icons.image_outlined,
      (c) async {
    final imgs = await pickImages();
    if (imgs.isEmpty || !c.mounted) return;
    await imagesIntoEditor(c, imgs, defaultName: 'Photos ${stamp()}');
  }),
  Tool('Import PDF', 'Add files to your library', Icons.file_open_outlined,
      (c) => importPdfs(c)),
];

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Tools')),
        body: ListView.builder(
          padding: const EdgeInsets.only(bottom: 110),
          itemCount: tools.length,
          itemBuilder: (context, index) {
            final tool = tools[index];
            return ListTile(
              leading: Icon(tool.icon),
              title: Text(tool.name),
              subtitle: Text(tool.hint),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => tool.run(context),
            );
          },
        ),
      );
}
