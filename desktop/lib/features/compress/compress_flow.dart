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
Future<CompressQuality?> askQuality(BuildContext context,
    {int? originalBytes}) {
  final input = TextEditingController();
  var unit = 'MB';
  String? error;
  return showModalBottomSheet<CompressQuality>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: SafeArea(
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
                  ListTile(
                    leading: const Icon(Icons.compress),
                    title: const Text('Optimal (recommended)'),
                    subtitle: const Text(
                        'Automatically balance clarity and file size'),
                    onTap: () => Navigator.pop(ctx, CompressQuality.balanced),
                  ),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(children: [
                        Expanded(
                            child: TextField(
                                controller: input,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                    labelText: 'Target size',
                                    hintText: 'For example, 2',
                                    errorText: error))),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                            value: unit,
                            items: [
                              for (final u in ['KB', 'MB'])
                                DropdownMenuItem(value: u, child: Text(u))
                            ],
                            onChanged: (v) => set(() => unit = v!)),
                      ])),
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: FilledButton(
                          onPressed: () {
                            final value = double.tryParse(
                                input.text.trim().replaceAll(',', '.'));
                            if (value == null ||
                                !value.isFinite ||
                                value <= 0) {
                              set(() => error = 'Enter a positive size.');
                              return;
                            }
                            final bytes =
                                (value * (unit == 'MB' ? 1024 * 1024 : 1024))
                                    .round();
                            if (bytes < 1) {
                              set(() => error = 'Enter at least 1 byte.');
                              return;
                            }
                            if (originalBytes != null &&
                                bytes >= originalBytes) {
                              set(() =>
                                  error = 'This file is already smaller.');
                              return;
                            }
                            Navigator.pop(
                                ctx,
                                CompressQuality('Target size',
                                    'Best quality within your target.', 200, 90,
                                    targetBytes: bytes));
                          },
                          child: const Text('Use target size'))),
                ],
              ),
            ))),
  );
}

Future<bool> compressWithOptions(BuildContext context, List<PageRef> pages,
    String output, CompressQuality quality) async {
  var cancelled = false;
  final baseline = '$output.original.pdf';
  try {
    await runWithProgress<void>(context, 'Compressing…', (report) async {
      await engine.assemble(pages, baseline);
      if (cancelled) throw CompressionCancelled();
      await engine.compress(pages, output, quality, onProgress: (done, total) {
        if (cancelled) throw CompressionCancelled();
        report(done, total);
      });
      if (await File(output).length() >= await File(baseline).length()) {
        await File(baseline).copy(output);
      }
    }, onCancel: () => cancelled = true);
  } finally {
    if (await File(baseline).exists()) await File(baseline).delete();
  }
  if (cancelled) throw CompressionCancelled();
  final bytes = await File(output).length();
  if (quality.targetBytes != null && bytes > quality.targetBytes!) {
    if (!context.mounted) return false;
    return await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
                    title: const Text('Target could not be reached'),
                    content: Text(
                        'Smallest size reached: ${fmtSize(bytes)}. Keep this copy?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Keep copy'))
                    ])) ==
        true;
  }
  return true;
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
    final original = await File(path).length();
    if (!context.mounted) return;
    final q = await askQuality(context, originalBytes: original);
    if (q == null || !context.mounted) return;
    final n = await engine.pageCount(path);
    final tmp = await tempPdfPath();
    if (!context.mounted) return;
    final accepted = await compressWithOptions(
        context, [for (var i = 0; i < n; i++) PageRef(path, i)], tmp, q);
    if (!accepted) {
      if (await File(tmp).exists()) await File(tmp).delete();
      return;
    }
    final compressed = await File(tmp).length();
    if (compressed >= original) {
      await File(tmp).delete();
      toastOn(messenger,
          'No useful reduction: ${fmtSize(original)} original, ${fmtSize(compressed)} after compression. Original kept.');
      return;
    }
    final doc = await repo.addFile(tmp,
        title:
            '${title.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')}_compressed',
        compressed: true);
    toastOn(
      messenger,
      'Original: ${fmtSize(original)} · Compressed: ${fmtSize(compressed)}',
      actionLabel: 'Open',
      duration: const Duration(seconds: 5),
      onAction: () => nav.push(
          MaterialPageRoute<void>(builder: (_) => DocumentScreen(id: doc.id))),
    );
  } catch (e) {
    toastOn(messenger, friendlyError(e));
  }
}
