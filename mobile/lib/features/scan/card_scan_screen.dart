import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/pdf_helpers.dart';
import '../../core/toast.dart';
import '../../core/ocr_service.dart';
import 'edge_correction_screen.dart';
import '../camera_scan_screen.dart';
import '../documents/actions.dart';
import '../documents/document_screen.dart';

enum CardType {
  id1('ID-1 · ID, licence, bank card', 85.60, 53.98),
  passport('Passport page', 125, 88);

  const CardType(this.label, this.widthMm, this.heightMm);
  final String label;
  final double widthMm, heightMm;
}

Future<void> buildCardPdf(
    CardType type, List<String> sides, String output) async {
  final images = [
    for (final s in sides) pw.MemoryImage(await File(s).readAsBytes())
  ];
  final doc = pw.Document();
  doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(20 * PdfPageFormat.mm),
      build: (_) => pw.Column(children: [
            for (var i = 0; i < images.length; i++) ...[
              if (i > 0) pw.SizedBox(height: 12 * PdfPageFormat.mm),
              pw.Center(
                  child: pw.Container(
                      width: type.widthMm * PdfPageFormat.mm,
                      height: type.heightMm * PdfPageFormat.mm,
                      foregroundDecoration: pw.BoxDecoration(
                          border: pw.Border.all(
                              color: PdfColors.grey400, width: .4)),
                      child: pw.Image(images[i], fit: pw.BoxFit.cover))),
            ]
          ])));
  await File(output).writeAsBytes(await doc.save(), flush: true);
}

class CardScanScreen extends StatefulWidget {
  const CardScanScreen({super.key});
  @override
  State<CardScanScreen> createState() => _CardScanScreenState();
}

class _CardScanScreenState extends State<CardScanScreen> {
  CardType type = CardType.id1;
  final List<String?> sides = [null, null];
  bool busy = false;
  int? pendingSide;
  Future<File> get draft async =>
      File('${(await getApplicationSupportDirectory()).path}/card_draft.json');
  Future<void> persist() async {
    final file = await draft;
    await file.writeAsString(
        jsonEncode({'type': type.name, 'sides': sides, 'pending': pendingSide}),
        flush: true);
  }

  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    try {
      final file = await draft;
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      if (!mounted) return;
      setState(() {
        type = CardType.values.firstWhere((t) => t.name == data['type'],
            orElse: () => CardType.id1);
        sides[0] = data['sides'][0];
        sides[1] = data['sides'][1];
        pendingSide = data['pending'];
      });
      final unfinished = await ScanDraft.load(key:'card_side');
      if (pendingSide != null &&
          unfinished != null &&
          unfinished.$1.isNotEmpty &&
          mounted) {
        final paths = await Navigator.of(context).push<List<String>>(
            MaterialPageRoute(
                builder: (_) => EdgeCorrectionScreen(
                    pages: unfinished.$1, initialIndex: unfinished.$2,draftKey:'card_side')));
        if (paths != null && paths.isNotEmpty && mounted) {
          setState(() => sides[pendingSide!] = paths.first);
          pendingSide = null;
          await persist();
          await ScanDraft.clear(key:'card_side');
        }
      }
    } catch (_) {
      if (mounted) {
        toast(context,
            'Could not restore the card draft. Please retake the missing side.');
      }
    }
  }

  Future<void> capture(int side) async {
    pendingSide = side;
    await persist();
    if (!mounted) return;
    final paths = await Navigator.of(context).push<List<String>>(
        MaterialPageRoute(
            builder: (_) => CameraScanScreen(
                multiple: false,draftKey:'card_side',
                prompt: side == 0 ? 'Scan the FRONT' : 'Now scan the BACK',
                guideAspect: type.widthMm / type.heightMm)));
    if (!mounted || paths == null || paths.isEmpty) return;
    setState(() => sides[side] = paths.first);
    pendingSide = null;
    await persist();
    await ScanDraft.clear(key:'card_side');
    if (side == 0 && sides[1] == null) await capture(1);
  }

  Future<void> save() async {
    setState(() => busy = true);
    final repo = repoOf(context);
    try {
      final path = await tempPdfPath();
      await buildCardPdf(type, sides.cast<String>(), path);
      final doc = await repo.addFile(path, title: 'ID Card');
      await ScanDraft.clear(key:'card_side');
      final file = await draft;
      if (await file.exists()) await file.delete();
      await OcrService(repo).enqueue(doc.id);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => DocumentScreen(id: doc.id)));
    } catch (_) {
      if (mounted) toast(context, 'Could not save the card. Please try again.');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('ID / Card')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        DropdownButtonFormField<CardType>(
            initialValue: type,
            items: [
              for (final t in CardType.values)
                DropdownMenuItem(value: t, child: Text(t.label))
            ],
            onChanged: busy ? null : (v) => setState(() => type = v!)),
        const SizedBox(height: 20),
        AspectRatio(
            aspectRatio: 210 / 297,
            child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(20),
                child: LayoutBuilder(
                    builder: (context, c) => Column(children: [
                          for (var i = 0; i < 2; i++) ...[
                            if (i == 1) SizedBox(height: c.maxWidth * 12 / 170),
                            Center(
                                child: SizedBox(
                                    width: c.maxWidth * type.widthMm / 170,
                                    height: c.maxWidth * type.heightMm / 170,
                                    child: InkWell(
                                        onTap: busy ? null : () => capture(i),
                                        child: Container(
                                            decoration: BoxDecoration(
                                                border: Border.all(
                                                    color:
                                                        Colors.grey.shade400)),
                                            child: sides[i] == null
                                                ? Center(
                                                    child: Text(
                                                        i == 0
                                                            ? 'Scan the FRONT'
                                                            : 'Now scan the BACK',
                                                        style: const TextStyle(
                                                            color:
                                                                Colors.black)))
                                                : Image.file(File(sides[i]!),
                                                    fit: BoxFit.cover,
                                                    cacheWidth: 900))))),
                          ]
                        ])))),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          for (var i = 0; i < 2; i++)
            TextButton(
                onPressed: busy ? null : () => capture(i),
                child: Text(
                    '${sides[i] == null ? 'Scan' : 'Retake'} ${i == 0 ? 'front' : 'back'}'))
        ]),
        FilledButton(
            onPressed: busy || sides.any((s) => s == null) ? null : save,
            child: Text(busy ? 'Saving…' : 'Save PDF')),
      ]));
}
