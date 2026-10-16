import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/format.dart';
import '../core/pdf_engine.dart';
import '../core/toast.dart';
import 'documents/actions.dart';
import 'documents/document.dart';

/// A chosen PDF. [doc] is set when it came from the app library.
typedef PickedPdf = ({String path, Document? doc});

/// Select library documents and/or device PDFs, preserving selection order.
Future<List<String>?> pickPdfsForMerge(BuildContext context) async {
  final repo = repoOf(context);
  final docs = await repo.list(const DocQuery());
  if (!context.mounted) return null;
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _MergePdfPicker(
      documents: {for (final d in docs) repo.pathOf(d): d.title},
    ),
  );
}

class _MergePdfPicker extends StatefulWidget {
  final Map<String, String> documents;
  const _MergePdfPicker({required this.documents});

  @override
  State<_MergePdfPicker> createState() => _MergePdfPickerState();
}

class _MergePdfPickerState extends State<_MergePdfPicker> {
  final _selected = <String>{};
  final _external = <String, String>{};
  bool _browsing = false;

  Future<void> _browse() async {
    setState(() => _browsing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
      );
      if (!mounted || result == null) return;
      setState(() {
        for (final path in result.paths.whereType<String>()) {
          if (!widget.documents.containsKey(path)) {
            _external[path] = p.basenameWithoutExtension(path);
          }
          _selected.add(path);
        }
      });
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _browsing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final documents = {...widget.documents, ..._external}.entries.toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const ListTile(
              title: Text('Merge PDFs'),
              subtitle: Text('Select at least two PDFs in the order to merge.'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Browse files...'),
              enabled: !_browsing,
              onTap: _browse,
            ),
            const Divider(height: 1),
            Expanded(
              child: documents.isEmpty
                  ? const Center(child: Text('Browse files to choose PDFs'))
                  : ListView.builder(
                      itemCount: documents.length,
                      itemBuilder: (_, i) {
                        final document = documents[i];
                        return CheckboxListTile(
                          title: Text(document.value,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          value: _selected.contains(document.key),
                          onChanged: _browsing
                              ? null
                              : (selected) => setState(() {
                                    if (selected == true) {
                                      _selected.add(document.key);
                                    } else {
                                      _selected.remove(document.key);
                                    }
                                  }),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _selected.length < 2 || _browsing
                        ? null
                        : () => Navigator.pop(context, _selected.toList()),
                    child: Text('Continue (${_selected.length})'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets the user choose a PDF from the library or browse the device.
Future<PickedPdf?> pickPdf(BuildContext context) async {
  final repo = repoOf(context);
  final docs = await repo.list(const DocQuery());
  if (!context.mounted) return null;
  return showModalBottomSheet<PickedPdf>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Browse files...'),
              onTap: () async {
                final r = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['pdf'],
                );
                if (!ctx.mounted) return;
                final path =
                    (r == null || r.paths.isEmpty) ? null : r.paths.first;
                final PickedPdf? result =
                    path == null ? null : (path: path, doc: null);
                Navigator.pop(ctx, result);
              },
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final d in docs)
                    ListTile(
                      leading: const Icon(Icons.picture_as_pdf_outlined),
                      title: Text(d.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${d.pageCount} pages  ·  ${fmtSize(d.sizeBytes)}'),
                      onTap: () {
                        final PickedPdf result = (path: repo.pathOf(d), doc: d);
                        Navigator.pop(ctx, result);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<List<String>> pickImages() async {
  final r = await FilePicker.platform.pickFiles(
    type: FileType.image,
    allowMultiple: true,
  );
  if (r == null) return [];
  return r.paths.whereType<String>().toList();
}
