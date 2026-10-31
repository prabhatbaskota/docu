import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/pdf_engine.dart';
import '../core/pdf_helpers.dart';
import '../core/progress.dart';
import '../core/toast.dart';
import '../core/ocr_service.dart';
import 'scan/import_scan.dart';
import 'scan/card_scan_screen.dart';
import 'scan/edge_correction_screen.dart';
import 'documents/actions.dart';
import 'documents/document_screen.dart';
import 'scan/scan_review_screen.dart';

enum ScanMode { single, multiple, auto }

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
            subtitle: const Text('Choose a photo, then correct its edges'),
            onTap: () => Navigator.pop(ctx, ScanMode.single),
          ),
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: const Text('Multiple pages'),
            subtitle: const Text('Choose photos and correct them in sequence'),
            onTap: () => Navigator.pop(ctx, ScanMode.multiple),
          ),
          ListTile(
            leading: const Icon(Icons.auto_fix_high_outlined),
            title: const Text('ID / Card'),
            subtitle: const Text('Front and back on one A4 page'),
            onTap: () => Navigator.pop(ctx, ScanMode.auto),
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

  List<String> imgs = const [];
  if (mode == ScanMode.auto) {
    try {
      await Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const CardScanScreen()));
      return null;
    } catch (e) {
      if (context.mounted) toast(context, friendlyError(e));
      return null;
    }
  } else {
    final draft = await ScanDraft.load();
    if (!context.mounted) return null;
    if (draft != null && draft.$1.isNotEmpty) {
      imgs = draft.$3
          ? [for (final p in draft.$1) p.corrected ?? p.path]
          : await Navigator.of(context).push<List<String>>(MaterialPageRoute(
                  builder: (_) => EdgeCorrectionScreen(
                      pages: draft.$1, initialIndex: draft.$2))) ??
              const [];
    } else {
      imgs = await importScan(context, multiple: mode == ScanMode.multiple) ??
          const [];
    }
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
