import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/pdf_engine.dart';
import '../core/pdf_helpers.dart';
import '../core/progress.dart';
import '../core/toast.dart';
import 'camera_scan_screen.dart';
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
            subtitle: const Text('Press the shutter, then crop'),
            onTap: () => Navigator.pop(ctx, ScanMode.single),
          ),
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: const Text('Multiple pages'),
            subtitle: const Text('Shoot page after page, review them all after'),
            onTap: () => Navigator.pop(ctx, ScanMode.multiple),
          ),
          ListTile(
            leading: const Icon(Icons.auto_fix_high_outlined),
            title: const Text('Auto-detect edges'),
            subtitle: const Text("Google's scanner finds the page and captures by itself"),
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
      imgs = await CunningDocumentScanner.getPictures(
            noOfPages: 30,
            isGalleryImportAllowed: true,
          ) ??
          const [];
    } catch (e) {
      if (context.mounted) toast(context, 'Scanner failed: $e');
      return null;
    }
  } else {
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
    final id = await runWithProgress<String>(context, 'Saving...', (report) async {
      final tmp = await tempPdfPath();
      await engine.imagesToPdf(imgs, tmp, onProgress: report);
      final doc = await repo.addFile(tmp, title: 'Scan ${stamp()}');
      return doc.id;
    });
    nav.push(MaterialPageRoute<void>(builder: (_) => DocumentScreen(id: id)));
  } catch (e) {
    toastOn(messenger, friendlyError(e));
  }
}
