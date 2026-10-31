import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/pdf_engine.dart';
import '../core/pdf_helpers.dart';
import '../core/progress.dart';
import '../core/toast.dart';
import '../core/ocr_service.dart';
import 'camera_scan_screen.dart';
import 'documents/actions.dart';
import 'documents/document_screen.dart';
import 'scan/scan_review_screen.dart';
import 'scan/edge_correction_screen.dart';
import 'scan/card_scan_screen.dart';

enum ScanMode { single, multiple, card }

Future<ScanMode?> askScanMode(BuildContext context) {
  return showModalBottomSheet<ScanMode>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.crop_portrait),
            title: const Text('Single page'),
            subtitle: const Text('Press the shutter, then crop'),
            onTap: () => Navigator.pop(ctx, ScanMode.single),
          ),
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: const Text('Multiple pages'),
            subtitle:
                const Text('Shoot page after page, review them all after'),
            onTap: () => Navigator.pop(ctx, ScanMode.multiple),
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('ID / Card'),
            subtitle: const Text('Front and back on one A4 page'),
            onTap: () => Navigator.pop(ctx, ScanMode.card),
          ),
        ],
      ),
    ),
  );
}

/// Mode prompt, capture, then the batch review. Returns the approved image
/// paths, or null if the user backed out at any point.
Future<List<String>?> scanAndReview(
  BuildContext context, {
  required String confirmLabel,
}) async {
  final mode = await askScanMode(context);
  if (mode == null || !context.mounted) return null;
  if (mode == ScanMode.card) {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => const CardScanScreen()));
    return null;
  }

  List<String> imgs = const [];
  final draft = await ScanDraft.load();
  if (!context.mounted) return null;
  if (draft != null && draft.$1.isNotEmpty) {
    final resume = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Resume unfinished scan?'),
                content: Text(
                    '${draft.$1.length} captured pages are kept on this device.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Discard')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Resume'))
                ]));
    if (!context.mounted) return null;
    if (resume == null) return null;
    if (resume) {
      imgs = draft.$3
          ? [for (final p in draft.$1) p.corrected ?? p.path]
          : await Navigator.of(context).push<List<String>>(MaterialPageRoute(
                  builder: (_) => EdgeCorrectionScreen(
                      pages: draft.$1, initialIndex: draft.$2))) ??
              const [];
      if (imgs.isEmpty || !context.mounted) return null;
      return Navigator.of(context).push<List<String>>(MaterialPageRoute(
          builder: (_) =>
              ScanReviewScreen(initial: imgs, confirmLabel: confirmLabel)));
    }
    await ScanDraft.clear();
  }
  if (!context.mounted) return null;
  {
    imgs = await Navigator.of(context).push<List<String>>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) =>
                CameraScanScreen(multiple: mode == ScanMode.multiple),
          ),
        ) ??
        const [];
  }
  if (imgs.isEmpty || !context.mounted) return null;

  return Navigator.of(context).push<List<String>>(
    MaterialPageRoute(
      builder: (_) =>
          ScanReviewScreen(initial: imgs, confirmLabel: confirmLabel),
    ),
  );
}

/// Scan, review, save as a PDF named "Scan <date time>", and open it.
Future<void> startScan(BuildContext context) async {
  final imgs = await scanAndReview(context, confirmLabel: 'Save PDF');
  if (imgs == null || imgs.isEmpty || !context.mounted) return;
  final repo = repoOf(context);
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final id =
        await runWithProgress<String>(context, 'Saving...', (report) async {
      final tmp = await tempPdfPath();
      await engine.imagesToPdf(imgs, tmp, onProgress: report);
      final doc = await repo.addFile(tmp, title: 'Scan ${stamp()}');
      await ScanDraft.clear();
      await OcrService(repo).enqueue(doc.id);
      return doc.id;
    });
    nav.push(MaterialPageRoute<void>(builder: (_) => DocumentScreen(id: id)));
  } catch (e) {
    toastOn(messenger, friendlyError(e));
  }
}
