import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/ocr_service.dart';
import '../../core/pdf_helpers.dart';
import '../../core/progress.dart';
import '../../core/toast.dart';
import 'actions.dart';
import 'document.dart';

Future<void> showTextActions(BuildContext context, Document doc) async {
  final repo = repoOf(context), service = OcrService(repoOf(context));
  final pages = await service.pages(doc.id);
  final suggestion = await service.suggestedName(doc.id);
  if (!context.mounted) return;
  var selected = 0;
  await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (doc.ocrStatus != 'ready')
                  ListTile(
                      title: Text(doc.ocrStatus == 'reading'
                          ? 'Reading text…'
                          : 'Read text'),
                      subtitle:
                          const Text('Text recognition runs on this device.'),
                      onTap: doc.ocrStatus == 'reading'
                          ? null
                          : () async {
                              await service.enqueue(doc.id);
                              if (ctx.mounted) Navigator.pop(ctx);
                            }),
                if (pages.isNotEmpty) ...[
                  ListTile(
                      title: const Text('Page'),
                      trailing: DropdownButton<int>(
                          value: selected,
                          items: [
                            for (var i = 0; i < pages.length; i++)
                              DropdownMenuItem(
                                  value: i, child: Text('${i + 1}'))
                          ],
                          onChanged: (v) => set(() => selected = v!))),
                  ListTile(
                      leading: const Icon(Icons.copy),
                      title: const Text('Copy text'),
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(
                            text: pages[selected]['text'] as String));
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) toast(context, 'Page text copied');
                      }),
                  ListTile(
                      leading: const Icon(Icons.text_snippet_outlined),
                      title: const Text('Share as .txt'),
                      onTap: () async {
                        try {
                          final dir = await getTemporaryDirectory();
                          final file = File('${dir.path}/docu_text.txt');
                          await file.writeAsString(await service.text(doc.id));
                          await Share.shareXFiles([XFile(file.path)],
                              subject: doc.title);
                        } catch (_) {
                          if (context.mounted) {
                            toast(context, 'Could not share text.');
                          }
                        }
                      }),
                  ListTile(
                      leading: const Icon(Icons.picture_as_pdf_outlined),
                      title: const Text('Export searchable PDF'),
                      onTap: () async {
                        Navigator.pop(ctx);
                        try {
                          final output = await tempPdfPath();
                          if (!context.mounted) return;
                          await runWithProgress<void>(
                              context,
                              'Creating searchable PDF…',
                              (_) => service.searchablePdf(doc.id, output));
                          final saved = await repo.addFile(output,
                              title: '${doc.title}_searchable');
                          if (context.mounted) {
                            toast(context, 'Saved ${saved.title}');
                          }
                        } catch (_) {
                          if (context.mounted) {
                            toast(context,
                                'Could not export searchable PDF. Your original is kept.');
                          }
                        }
                      }),
                  if (suggestion != null && suggestion != doc.title)
                    ListTile(
                        leading: const Icon(Icons.drive_file_rename_outline),
                        title: Text(suggestion,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: const Text('Use suggested file name'),
                        onTap: () async {
                          await repo.rename(doc.id, suggestion);
                          if (ctx.mounted) Navigator.pop(ctx);
                        }),
                ],
              ]))));
}
