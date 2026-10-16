import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/toast.dart';
import '../compress/compress_flow.dart';
import 'document.dart';
import 'document_repository.dart';
import 'providers.dart';

DocumentRepository repoOf(BuildContext context) =>
    ProviderScope.containerOf(context, listen: false).read(repositoryProvider);

/// Soft-deletes, then offers Undo for a few seconds; after that it is purged.
Future<void> deleteWithUndo(BuildContext context, List<String> ids) async {
  final repo = repoOf(context);
  final messenger = ScaffoldMessenger.of(context);
  await repo.softDelete(ids);
  toastOn(
    messenger,
    ids.length == 1 ? 'Document deleted' : '${ids.length} documents deleted',
    actionLabel: 'Undo',
    duration: const Duration(seconds: 5),
    onAction: () => repo.restore(ids),
  ).closed.then((reason) {
    if (reason != SnackBarClosedReason.action) repo.purge(ids);
  });
}

/// Shares real files named after the document titles.
Future<void> shareDocuments(BuildContext context, List<Document> docs) async {
  if (docs.isEmpty) return;
  final repo = repoOf(context);
  final tmp = await getTemporaryDirectory();
  final dir = Directory(
      p.join(tmp.path, 'share_${DateTime.now().microsecondsSinceEpoch}'));
  await dir.create(recursive: true);
  final used = <String>{};
  final files = <XFile>[];
  for (final d in docs) {
    final base = safeFileName(d.title);
    var name = base;
    var i = 2;
    while (!used.add(name.toLowerCase())) {
      name = '$base ($i)';
      i++;
    }
    final dest = p.join(dir.path, '$name.pdf');
    await File(repo.pathOf(d)).copy(dest);
    files.add(XFile(dest, mimeType: 'application/pdf'));
  }
  await Share.shareXFiles(files);
}

/// Save a library PDF to a user-selected path on desktop.
Future<void> exportDocument(BuildContext context, Document doc) async {
  final repo = repoOf(context);
  final messenger = ScaffoldMessenger.of(context);
  final destination = await FilePicker.platform.saveFile(
    dialogTitle: 'Export PDF',
    fileName: '${safeFileName(doc.title)}.pdf',
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );
  if (destination == null) return;
  final source = repo.pathOf(doc);
  if (p.normalize(destination).toLowerCase() ==
      p.normalize(source).toLowerCase()) {
    return;
  }
  try {
    await File(source).copy(destination);
    toastOn(messenger, 'PDF exported');
  } catch (e) {
    toastOn(messenger, 'Could not export PDF: $e');
  }
}

Future<void> importPdfs(BuildContext context, {String? folderId}) async {
  final repo = repoOf(context);
  final messenger = ScaffoldMessenger.of(context);
  final r = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
    allowMultiple: true,
  );
  if (r == null) return;
  var ok = 0;
  var failed = 0;
  for (final path in r.paths.whereType<String>()) {
    try {
      await repo.addFile(path,
          title: p.basenameWithoutExtension(path),
          move: false,
          folderId: folderId);
      ok++;
    } catch (_) {
      failed++;
    }
  }
  toastOn(
    messenger,
    failed == 0
        ? 'Imported $ok document${ok == 1 ? '' : 's'}'
        : 'Imported $ok; $failed file${failed == 1 ? '' : 's'} could not be opened as PDF',
  );
}

Future<void> renameDocument(BuildContext context, Document doc) async {
  final repo = repoOf(context);
  final name = await askText(context,
      title: 'Rename', initial: doc.title, label: 'Name');
  if (name != null && name.trim().isNotEmpty) {
    await repo.rename(doc.id, name);
  }
}

Future<String?> askText(
  BuildContext context, {
  required String title,
  String initial = '',
  String label = 'Name',
  String confirm = 'Save',
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(
          title: title, initial: initial, label: label, confirm: confirm),
    );

class _TextDialog extends StatefulWidget {
  final String title, initial, label, confirm;
  const _TextDialog({
    required this.title,
    required this.initial,
    required this.label,
    required this.confirm,
  });

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial);

  @override
  void initState() {
    super.initState();
    _c.selection = TextSelection(baseOffset: 0, extentOffset: _c.text.length);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _c,
          autofocus: true,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, _c.text),
              child: Text(widget.confirm)),
        ],
      );
}

/// Rename / Duplicate / Details (/ Delete) sheet for one document.
Future<void> showDocumentMenu(
  BuildContext context,
  Document doc, {
  bool includeDelete = true,
  bool leaveScreenOnDelete = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: const Text('Rename'),
            onTap: () {
              Navigator.pop(sheet);
              renameDocument(context, doc);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: const Text('Duplicate'),
            onTap: () async {
              Navigator.pop(sheet);
              final messenger = ScaffoldMessenger.of(context);
              await repoOf(context).duplicate(doc.id);
              toastOn(messenger, 'Duplicated');
            },
          ),
          ListTile(
            leading: const Icon(Icons.compress),
            title: const Text('Compress'),
            onTap: () {
              Navigator.pop(sheet);
              compressDocument(context, doc);
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Details'),
            onTap: () {
              Navigator.pop(sheet);
              showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(doc.title),
                  content: Text(
                    'Pages: ${doc.pageCount}\n'
                    'Size: ${fmtSize(doc.sizeBytes)}\n'
                    'Created: ${fmtDate(doc.createdAt)}\n'
                    'Modified: ${fmtDate(doc.updatedAt)}',
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close')),
                  ],
                ),
              );
            },
          ),
          if (includeDelete)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(sheet);
                if (leaveScreenOnDelete) Navigator.pop(context);
                deleteWithUndo(context, [doc.id]);
              },
            ),
        ],
      ),
    ),
  );
}
