import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/pdf_engine.dart';
import '../../core/progress.dart';
import '../../core/pdf_helpers.dart';
import '../../core/toast.dart';
import '../documents/actions.dart';
import '../documents/document.dart';
import '../documents/document_screen.dart';

/// Small / Balanced / High. Null if dismissed.
Future<CompressQuality?> askQuality(BuildContext context, {int? originalBytes}) {
  return showModalBottomSheet<CompressQuality>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text('Compress',
                style: Theme.of(ctx).textTheme.titleMedium),
            subtitle: const Text(
                'Makes a smaller copy. Pages become images, so text can no longer be selected.'),
          ),
          if (originalBytes != null)
            ListTile(
              title: Text('Original size: ${fmtSize(originalBytes)}'),
              subtitle: const Text(
                  'The final size depends on the page content and will be shown after compression.'),
            ),
          for (final q in CompressQuality.values)
            ListTile(
              leading: const Icon(Icons.compress),
              title: Text(q.label),
              subtitle: Text(q.hint),
              onTap: () => Navigator.pop(ctx, q),
            ),
        ],
      ),
    ),
  );
}

/// Merge or Compress and merge. Returns true for compress, null if dismissed.
Future<bool?> askMergeMode(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.merge_type),
            title: const Text('Merge'),
            subtitle: const Text('Keep original quality'),
            onTap: () => Navigator.pop(ctx, false),
          ),
          ListTile(
            leading: const Icon(Icons.compress),
            title: const Text('Compress and merge'),
            subtitle: const Text('Smaller file; text becomes unselectable'),
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    ),
  );
}

Future<void> compressDocument(BuildContext context, Document doc) =>
    compressPdfFile(context,
        path: repoOf(context).pathOf(doc), title: doc.title);

/// Compresses any PDF into a *copy* in the library; the original is untouched.
Future<void> compressPdfFile(
  BuildContext context, {
  required String path,
  required String title,
}) async {
  final repo = repoOf(context);
  final messenger = ScaffoldMessenger.of(context);
  final nav = Navigator.of(context);
  try {
    final documents = await repo.list(const DocQuery());
    if (documents.any((doc) => repo.pathOf(doc) == path && doc.compressed)) {
      toastOn(messenger, 'This file is already compressed. No new copy was created.');
      return;
    }
    final original = await File(path).length();
    if (!context.mounted) return;
    final q = await askQuality(context, originalBytes: original);
    if (q == null || !context.mounted) return;
    final n = await engine.pageCount(path);
    final tmp = await tempPdfPath();
    if (!context.mounted) return;
    await runWithProgress<void>(
      context,
      'Compressing...',
      (report) => engine.compress(
          [for (var i = 0; i < n; i++) PageRef(path, i)], tmp, q,
          onProgress: report),
    );
    final compressed = await File(tmp).length();
    if (compressed >= original * 0.95) {
      await File(tmp).delete();
      toastOn(messenger,
          'No useful reduction: ${fmtSize(original)} original, ${fmtSize(compressed)} after compression. Original kept.');
      return;
    }
    final doc = await repo.addFile(tmp,
        title: '$title (compressed)', compressed: true);
    toastOn(
      messenger,
      'Original: ${fmtSize(original)} · Compressed: ${fmtSize(compressed)}',
      actionLabel: 'Open',
      duration: const Duration(seconds: 5),
      onAction: () => nav.push(MaterialPageRoute<void>(
          builder: (_) => DocumentScreen(id: doc.id))),
    );
  } catch (e) {
    toastOn(messenger, friendlyError(e));
  }
}
