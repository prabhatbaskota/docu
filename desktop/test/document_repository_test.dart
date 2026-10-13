import 'dart:io';

import 'package:docapp/core/database.dart';
import 'package:docapp/features/documents/document.dart';
import 'package:docapp/features/documents/document_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late Directory libDir;
  late Directory srcDir;
  late DocumentRepository repo;

  File makeSrc(String name, {int bytes = 10}) =>
      File('${srcDir.path}/$name')..writeAsBytesSync(List.filled(bytes, 1));

  setUp(() async {
    db = await AppDatabase.open(inMemoryDatabasePath);
    libDir = Directory.systemTemp.createTempSync('docapp_lib_');
    srcDir = Directory.systemTemp.createTempSync('docapp_src_');
    repo = DocumentRepository(db: db, dir: libDir, pageCounter: (_) async => 3);
  });

  tearDown(() async {
    await repo.dispose();
    await db.close();
    libDir.deleteSync(recursive: true);
    srcDir.deleteSync(recursive: true);
  });

  test('addFile moves the file into the library and records metadata',
      () async {
    final src = makeSrc('a.pdf', bytes: 42);
    final d = await repo.addFile(src.path, title: 'Invoice');
    expect(d.title, 'Invoice');
    expect(d.pageCount, 3);
    expect(d.sizeBytes, 42);
    expect(File(repo.pathOf(d)).existsSync(), isTrue);
    expect(src.existsSync(), isFalse);
  });

  test('addFile with move:false keeps the source', () async {
    final src = makeSrc('a.pdf');
    await repo.addFile(src.path, title: 'x.pdf', move: false);
    expect(src.existsSync(), isTrue);
    final all = await repo.list(const DocQuery());
    expect(all.single.title, 'x'); // ".pdf" stripped
  });

  test(
      'compression status survives rename and duplicate, and resets on replacement',
      () async {
    final doc = await repo.addFile(makeSrc('compressed.pdf').path,
        title: 'Compressed', compressed: true);
    await repo.rename(doc.id, 'Renamed');
    expect((await repo.get(doc.id))!.compressed, isTrue);
    final copy = await repo.duplicate(doc.id);
    expect((await repo.get(copy.id))!.compressed, isTrue);
    final replaced = await repo.replaceFile(doc.id, makeSrc('new.pdf').path);
    expect(replaced.compressed, isFalse);
    final compressed = await repo.replaceFile(doc.id, makeSrc('small.pdf').path,
        compressed: true);
    expect(compressed.compressed, isTrue);
  });

  test('version 1 database upgrade preserves existing documents', () async {
    final path = '${srcDir.path}/legacy.db';
    final legacy =
        await openDatabase(path, version: 1, onCreate: (db, _) async {
      await db
          .execute('CREATE TABLE documents (id TEXT PRIMARY KEY, title TEXT)');
      await db.insert('documents', {'id': 'old', 'title': 'Existing'});
    });
    await legacy.close();
    final upgraded = await AppDatabase.open(path);
    try {
      final row = (await upgraded.query('documents')).single;
      expect(row['title'], 'Existing');
      expect(row['compressed'], 0);
      expect(row['folder_id'], isNull);
      expect(await upgraded.getVersion(), 3);
    } finally {
      await upgraded.close();
    }
  });

  test('rename changes the title only', () async {
    final d = await repo.addFile(makeSrc('a.pdf').path, title: 'Old');
    await repo.rename(d.id, '  New name  ');
    final got = await repo.get(d.id);
    expect(got!.title, 'New name');
    expect(got.fileName, d.fileName);
  });

  test('duplicate creates an independent copy', () async {
    final d = await repo.addFile(makeSrc('a.pdf').path, title: 'Report');
    final copy = await repo.duplicate(d.id);
    expect(copy.id, isNot(d.id));
    expect(copy.title, 'Report copy');
    expect(File(repo.pathOf(copy)).existsSync(), isTrue);
    expect(File(repo.pathOf(d)).existsSync(), isTrue);
  });

  test('folders organize PDFs without deleting them', () async {
    final folder = await repo.createFolder('Receipts');
    final doc = await repo.addFile(makeSrc('receipt.pdf').path,
        title: 'Receipt', folderId: folder.id);
    expect((await repo.get(doc.id))!.folderId, folder.id);
    final copy = await repo.duplicate(doc.id);
    expect(copy.folderId, folder.id);
    await repo.renameFolder(folder.id, 'Taxes');
    expect((await repo.folders()).single.name, 'Taxes');
    await repo.moveToFolder([copy.id], null);
    expect((await repo.get(copy.id))!.folderId, isNull);
    await repo.deleteFolder(folder.id);
    expect((await repo.get(doc.id))!.folderId, isNull);
    expect(File(repo.pathOf(doc)).existsSync(), isTrue);
  });

  test('favorites filter', () async {
    final a = await repo.addFile(makeSrc('a.pdf').path, title: 'A');
    await repo.addFile(makeSrc('b.pdf').path, title: 'B');
    await repo.setFavorite(a.id, true);
    final favs = await repo.list(const DocQuery(favoritesOnly: true));
    expect(favs.map((d) => d.title), ['A']);
  });

  test('search treats % and _ literally', () async {
    await repo.addFile(makeSrc('a.pdf').path, title: 'Tax 100%');
    await repo.addFile(makeSrc('b.pdf').path, title: 'Tax 1000');
    final r = await repo.list(const DocQuery(text: '100%'));
    expect(r.map((d) => d.title), ['Tax 100%']);
  });

  test('sorting by name (case-insensitive) and size', () async {
    await repo.addFile(makeSrc('1.pdf', bytes: 10).path, title: 'banana');
    await repo.addFile(makeSrc('2.pdf', bytes: 99).path, title: 'Apple');
    await repo.addFile(makeSrc('3.pdf', bytes: 50).path, title: 'cherry');
    final byName = await repo.list(const DocQuery(sort: SortMode.name));
    expect(byName.map((d) => d.title), ['Apple', 'banana', 'cherry']);
    final bySize = await repo.list(const DocQuery(sort: SortMode.size));
    expect(bySize.map((d) => d.title), ['Apple', 'cherry', 'banana']);
  });

  test('soft delete hides, restore brings back, purge removes the file',
      () async {
    final d = await repo.addFile(makeSrc('a.pdf').path, title: 'A');
    await repo.softDelete([d.id]);
    expect(await repo.list(const DocQuery()), isEmpty);
    expect(await repo.get(d.id), isNull);

    await repo.restore([d.id]);
    expect((await repo.list(const DocQuery())).length, 1);

    await repo.softDelete([d.id]);
    await repo.purge([d.id]);
    expect(File(repo.pathOf(d)).existsSync(), isFalse);
    expect(await db.query('documents'), isEmpty);
  });

  test('purge never removes documents that are not in the trash', () async {
    final d = await repo.addFile(makeSrc('a.pdf').path, title: 'A');
    await repo.purge([d.id]);
    expect(File(repo.pathOf(d)).existsSync(), isTrue);
    expect((await repo.list(const DocQuery())).length, 1);
  });

  test('purgeDeleted cleans leftovers from the trash', () async {
    final d = await repo.addFile(makeSrc('a.pdf').path, title: 'A');
    await repo.softDelete([d.id]);
    await repo.purgeDeleted();
    expect(File(repo.pathOf(d)).existsSync(), isFalse);
  });

  test('replaceFile updates size, page count and modified time', () async {
    final d = await repo.addFile(makeSrc('a.pdf', bytes: 10).path, title: 'A');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final updated =
        await repo.replaceFile(d.id, makeSrc('b.pdf', bytes: 77).path);
    expect(updated.sizeBytes, 77);
    expect(updated.id, d.id);
    expect(updated.updatedAt.isAfter(d.updatedAt), isTrue);
  });

  test('syncFromDisk adopts untracked PDFs exactly once', () async {
    File('${libDir.path}/Old scan.pdf').writeAsBytesSync([1, 2, 3]);
    File('${libDir.path}/notes.txt').writeAsStringSync('ignore me');
    expect(await repo.syncFromDisk(), 1);
    final all = await repo.list(const DocQuery());
    expect(all.single.title, 'Old scan');
    expect(File(repo.pathOf(all.single)).existsSync(), isTrue);
    expect(await repo.syncFromDisk(), 0);
  });

  test('changes stream fires after a mutation', () async {
    final events = <void>[];
    final sub = repo.changes.listen(events.add);
    await repo.addFile(makeSrc('a.pdf').path, title: 'A');
    await Future<void>.delayed(Duration.zero);
    expect(events, isNotEmpty);
    await sub.cancel();
  });

  test('list honors a limit (used for Recent on Home)', () async {
    for (var i = 0; i < 4; i++) {
      await repo.addFile(makeSrc('$i.pdf').path, title: 'Doc $i');
    }
    final r = await repo.list(const DocQuery(), limit: 2);
    expect(r.length, 2);
  });
}
