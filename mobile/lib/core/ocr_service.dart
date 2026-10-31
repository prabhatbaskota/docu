import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sqflite/sqflite.dart';
import '../features/documents/document_repository.dart';
import 'database.dart';
import 'searchable_pdf.dart';

Uint8List _jpg((Uint8List, int, int) a) => img.encodeJpg(
    img.Image.fromBytes(
        width: a.$2,
        height: a.$3,
        bytes: a.$1.buffer,
        numChannels: 4,
        order: img.ChannelOrder.bgra),
    quality: 90);

/// Serialized, durable queue. Native recognition and image encoding do not run on the UI thread.
class OcrService {
  OcrService(this.repo);
  final DocumentRepository repo;
  static bool _running = false;
  Future<void> enqueue(String id) async {
    await repo.db.update('documents', {'ocr_status': 'reading'},
        where: 'id = ?', whereArgs: [id]);
    repo.refresh();
    unawaited(resume());
  }

  Future<void> resume() async {
    if (_running || (!Platform.isAndroid && !Platform.isIOS)) return;
    _running = true;
    try {
      while (true) {
        final rows = await repo.db.query('documents',
            where: "ocr_status = 'reading' AND deleted = 0", limit: 1);
        if (rows.isEmpty) break;
        final id = rows.first['id'] as String;
        try {
          await _read(id);
        } catch (_) {
          await repo.db.update('documents', {'ocr_status': 'error'},
              where: 'id = ?', whereArgs: [id]);
        }
        repo.refresh();
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _read(String id) async {
    final record = await repo.get(id);
    if (record == null) return;
    final version = record.updatedAt;
    final language = await SettingsStore(repo.db).get('ocr_language') ?? 'auto';
    final doc = await PdfDocument.openFile(repo.pathOf(record));
    final folder = await getTemporaryDirectory();
    final path = '${folder.path}/ocr_$id.jpg';
    final latin = TextRecognizer(script: TextRecognitionScript.latin);
    final deva = TextRecognizer(script: TextRecognitionScript.devanagiri);
    try {
      for (var i = 0; i < doc.pages.length; i++) {
        final page = doc.pages[i];
        final scale = math.min(2.1, 2200 / math.max(page.width, page.height));
        final raster = await page.render(
            width: (page.width * scale).round(),
            height: (page.height * scale).round());
        if (raster == null) {
          throw const FormatException('Could not read this page.');
        }
        final w = raster.width, h = raster.height;
        final pixels = Uint8List.fromList(raster.pixels);
        raster.dispose();
        await File(path).writeAsBytes(await compute(_jpg, (pixels, w, h)));
        final input = InputImage.fromFilePath(path);
        RecognizedText result;
        if (language == 'english') {
          result = await latin.processImage(input);
        } else {
          result = await deva.processImage(input);
          if (language == 'auto' &&
              !RegExp(r'[\u0900-\u097f]').hasMatch(result.text)) {
            result = await latin.processImage(input);
          }
        }
        final words = <Map<String, Object>>[];
        for (final block in result.blocks) {
          for (final line in block.lines) {
            for (final word in line.elements) {
              final r = word.boundingBox;
              words.add({
                'text': word.text,
                'x': r.left / w,
                'y': r.top / h,
                'w': r.width / w,
                'h': r.height / h
              });
            }
          }
        }
        final current = await repo.get(id);
        if (current == null || current.updatedAt != version) return;
        await repo.db.insert(
            'ocr_pages',
            {
              'document_id': id,
              'page_index': i,
              'text': result.text,
              'words': jsonEncode(words)
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await repo.db.update('documents', {'ocr_status': 'ready'},
          where: 'id = ? AND updated_at = ?',
          whereArgs: [id, version.millisecondsSinceEpoch]);
    } finally {
      await latin.close();
      await deva.close();
      doc.dispose();
      if (await File(path).exists()) await File(path).delete();
    }
  }

  Future<List<Map<String, Object?>>> pages(String id) =>
      repo.db.query('ocr_pages',
          where: 'document_id = ?', whereArgs: [id], orderBy: 'page_index');
  Future<String> text(String id) async =>
      (await pages(id)).map((p) => p['text'] as String).join('\n\n');
  Future<String?> suggestedName(String id) async {
    for (final line in (await text(id)).split('\n')) {
      final clean = line.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
      if (clean.length >= 4 && RegExp(r'[A-Za-z\u0900-\u097f]').hasMatch(clean)) {
        return clean.substring(0, math.min(70, clean.length));
      }
    }
    return null;
  }

  Future<void> searchablePdf(String id,String output)async {
    final record=await repo.get(id);if(record==null)return;
    await writeSearchablePdf(repo.pathOf(record),await pages(id),output);
  }
}
