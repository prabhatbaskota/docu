import 'dart:io';
import '../../mobile/lib/core/database.dart';
import '../../mobile/lib/features/documents/document.dart';
import '../../mobile/lib/features/documents/document_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test(
      'OCR search finds Devanagari and returns a snippet, escaping SQL wildcards',
      () async {
    final db = await AppDatabase.open(inMemoryDatabasePath);
    final dir = await Directory.systemTemp.createTemp('docu_ocr_');
    final repo =
        DocumentRepository(db: db, dir: dir, pageCounter: (_) async => 1);
    try {
      final source = File('${dir.path}/input.pdf');
      await source.writeAsString('%PDF-1.7\nfixture');
      final doc = await repo.addFile(source.path, title: 'Scan');
      await db.insert('ocr_pages', {
        'document_id': doc.id,
        'page_index': 0,
        'text': 'नेपाल नागरिकता प्रमाणपत्र 100% complete',
        'words': '[]'
      });
      final found = await repo.list(const DocQuery(text: 'नागरिकता'));
      expect(found.single.id, doc.id);
      expect(found.single.snippet, contains('नागरिकता'));
      expect((await repo.list(const DocQuery(text: '100%'))).length, 1);
      expect(await repo.list(const DocQuery(text: '100_')), isEmpty);
    } finally {
      await repo.dispose();
      await db.close();
      await dir.delete(recursive: true);
    }
  });
  test('v3 mobile database upgrades without losing documents', () async {
    final dir = await Directory.systemTemp.createTemp('docu_migrate_');
    final path = '${dir.path}/old.db';
    final old = await openDatabase(path, version: 3, onCreate: (db, _) async {
      await db
          .execute('CREATE TABLE documents(id TEXT PRIMARY KEY,title TEXT)');
      await db.insert('documents', {'id': 'kept', 'title': 'My scan'});
    });
    await old.close();
    final db = await AppDatabase.open(path);
    try {
      expect((await db.query('documents')).single['title'], 'My scan');
      expect((await db.query('documents')).single['ocr_status'], '');
      expect(await db.query('ocr_pages'), isEmpty);
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });
}
