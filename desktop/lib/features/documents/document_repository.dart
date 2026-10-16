import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/format.dart';
import '../../core/file_detection.dart';
import 'document.dart';

typedef PageCounter = Future<int> Function(String path);

class DocumentFolder {
  const DocumentFolder({required this.id, required this.name});
  final String id;
  final String name;
}

class RecentPdf {
  const RecentPdf({required this.path, required this.openedAt});
  final String path;
  final DateTime openedAt;
}

/// All reads/writes of documents: database rows + PDF files on disk.
/// UI never touches files or SQL directly.
class DocumentRepository {
  DocumentRepository({
    required this.db,
    required this.dir,
    required this.pageCounter,
  });

  final Database db;
  final Directory dir;
  final PageCounter pageCounter;

  final _changes = StreamController<void>.broadcast();

  /// Emits after every change; providers re-query on it.
  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> dispose() => _changes.close();

  static int _seq = 0;
  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_seq++).toRadixString(36)}';

  String pathOf(Document d) => p.join(dir.path, d.fileName);

  // ---------- reading ----------

  static String _escapeLike(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

  Future<List<Document>> list(DocQuery q, {int? limit}) async {
    final where = <String>['deleted = 0'];
    final args = <Object?>[];
    if (q.favoritesOnly) where.add('favorite = 1');
    final text = q.text.trim();
    if (text.isNotEmpty) {
      where.add(r"title LIKE ? ESCAPE '\'");
      args.add('%${_escapeLike(text)}%');
    }
    final order = switch (q.sort) {
      SortMode.recent => 'updated_at DESC',
      SortMode.name => 'title COLLATE NOCASE ASC',
      SortMode.size => 'size_bytes DESC',
    };
    final rows = await db.query('documents',
        where: where.join(' AND '),
        whereArgs: args,
        orderBy: order,
        limit: limit);
    return rows.map(Document.fromRow).toList();
  }

  Future<Document?> get(String id) async {
    final rows = await db.query('documents',
        where: 'id = ? AND deleted = 0', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Document.fromRow(rows.first);
  }

  Future<List<DocumentFolder>> folders() async {
    final rows = await db.query('folders', orderBy: 'name COLLATE NOCASE ASC');
    return [
      for (final row in rows)
        DocumentFolder(id: row['id'] as String, name: row['name'] as String),
    ];
  }

  Future<List<RecentPdf>> recentFiles() async {
    final rows =
        await db.query('recent_files', orderBy: 'opened_at DESC, path ASC');
    return [
      for (final row in rows)
        RecentPdf(
          path: row['path'] as String,
          openedAt:
              DateTime.fromMicrosecondsSinceEpoch(row['opened_at'] as int),
        ),
    ];
  }

  String _recentPath(String path) => p.normalize(p.absolute(path));

  Future<void> recordRecentFile(String path) async {
    final absolute = _recentPath(path);
    if (!await File(absolute).exists()) return;
    await db.insert(
        'recent_files',
        {
          'path': absolute,
          'opened_at': DateTime.now().microsecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    _notify();
  }

  Future<void> removeRecentFile(String path) async {
    await db.delete('recent_files',
        where: 'path = ?', whereArgs: [_recentPath(path)]);
    _notify();
  }

  Future<DocumentFolder> createFolder(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError('Folder name cannot be empty');
    final folder = DocumentFolder(id: _newId(), name: clean);
    await db.insert('folders', {
      'id': folder.id,
      'name': folder.name,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    _notify();
    return folder;
  }

  Future<void> renameFolder(String id, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError('Folder name cannot be empty');
    await db.update('folders', {'name': clean},
        where: 'id = ?', whereArgs: [id]);
    _notify();
  }

  /// Deleting a folder keeps its documents in Unfiled.
  Future<void> deleteFolder(String id) async {
    await db.transaction((txn) async {
      await txn.update('documents', {'folder_id': null},
          where: 'folder_id = ?', whereArgs: [id]);
      await txn.delete('folders', where: 'id = ?', whereArgs: [id]);
    });
    _notify();
  }

  Future<void> moveToFolder(List<String> ids, String? folderId) async {
    if (ids.isEmpty) return;
    if (folderId != null) {
      final exists = await db.query('folders',
          columns: ['id'], where: 'id = ?', whereArgs: [folderId], limit: 1);
      if (exists.isEmpty) throw StateError('Folder not found');
    }
    await db.update('documents', {'folder_id': folderId},
        where: 'id IN (${_inClause(ids)}) AND deleted = 0', whereArgs: ids);
    _notify();
  }

  // ---------- creating ----------

  Future<void> _place(String src, String dest, {required bool move}) async {
    final f = File(src);
    if (move) {
      try {
        await f.rename(dest);
        return;
      } on FileSystemException {
        // e.g. different volumes: fall back to copy + delete
      }
    }
    await f.copy(dest);
    if (move) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  Future<int> _validatedPageCount(String path) async {
    if (!await fileDetection.isPdf(path)) {
      throw const FormatException('This file is not a PDF.');
    }
    try {
      final count = await pageCounter(path);
      if (count < 1) throw const FormatException('This PDF has no pages.');
      return count;
    } catch (e) {
      if (e is FormatException) rethrow;
      throw const FormatException('This PDF could not be opened.');
    }
  }

  /// Adds a PDF to the library. [move] = take the file (temp output);
  /// otherwise it is copied (user's imported file).
  Future<Document> addFile(String src,
      {required String title,
      bool move = true,
      bool compressed = false,
      String? folderId}) async {
    final pageCount = await _validatedPageCount(src);
    final id = _newId();
    final fileName = '$id.pdf';
    final dest = p.join(dir.path, fileName);
    await _place(src, dest, move: move);
    try {
      final now = DateTime.now();
      final doc = Document(
        id: id,
        title: cleanTitle(title),
        fileName: fileName,
        pageCount: pageCount,
        sizeBytes: await File(dest).length(),
        createdAt: now,
        updatedAt: now,
        compressed: compressed,
        folderId: folderId,
      );
      await db.insert('documents', doc.toRow());
      _notify();
      return doc;
    } catch (_) {
      if (await File(dest).exists()) await File(dest).delete();
      rethrow;
    }
  }

  /// Replaces a document's PDF content (editing "Replace original").
  Future<Document> replaceFile(String id, String src,
      {bool compressed = false}) async {
    final doc = await get(id);
    if (doc == null) throw StateError('Document not found');
    final pageCount = await _validatedPageCount(src);
    final dest = pathOf(doc);
    await _place(src, dest, move: true);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'documents',
      {
        'page_count': pageCount,
        'size_bytes': await File(dest).length(),
        'updated_at': now,
        'compressed': compressed ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _notify();
    return (await get(id))!;
  }

  Future<Document> duplicate(String id) async {
    final doc = await get(id);
    if (doc == null) throw StateError('Document not found');
    final newId = _newId();
    final fileName = '$newId.pdf';
    await File(pathOf(doc)).copy(p.join(dir.path, fileName));
    final now = DateTime.now();
    final copy = Document(
      id: newId,
      title: '${doc.title} copy',
      compressed: doc.compressed,
      folderId: doc.folderId,
      fileName: fileName,
      pageCount: doc.pageCount,
      sizeBytes: doc.sizeBytes,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('documents', copy.toRow());
    _notify();
    return copy;
  }

  // ---------- updating ----------

  Future<void> rename(String id, String title) async {
    await db.update(
      'documents',
      {
        'title': cleanTitle(title),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _notify();
  }

  Future<void> setFavorite(String id, bool value) async {
    await db.update('documents', {'favorite': value ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
    _notify();
  }

  // ---------- deleting (soft first, so Undo works) ----------

  String _inClause(List<String> ids) => ids.map((_) => '?').join(',');

  Future<void> softDelete(List<String> ids) async {
    if (ids.isEmpty) return;
    await db.update('documents', {'deleted': 1},
        where: 'id IN (${_inClause(ids)})', whereArgs: ids);
    _notify();
  }

  Future<void> restore(List<String> ids) async {
    if (ids.isEmpty) return;
    await db.update('documents', {'deleted': 0},
        where: 'id IN (${_inClause(ids)})', whereArgs: ids);
    _notify();
  }

  /// Permanently removes rows and files.
  Future<void> purge(List<String> ids) async {
    if (ids.isEmpty) return;
    final rows = await db.query('documents',
        where: 'id IN (${_inClause(ids)}) AND deleted = 1', whereArgs: ids);
    for (final r in rows) {
      final f = File(p.join(dir.path, r['file_name'] as String));
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await db.delete('documents',
        where: 'id IN (${_inClause(ids)}) AND deleted = 1', whereArgs: ids);
  }

  /// Startup cleanup of anything left in the trash.
  Future<void> purgeDeleted() async {
    final rows =
        await db.query('documents', columns: ['id'], where: 'deleted = 1');
    await purge([for (final r in rows) r['id'] as String]);
  }

  // ---------- migration ----------

  /// Adopts PDFs that exist in the folder but not in the database
  /// (files created by earlier versions of the app).
  Future<int> syncFromDisk() async {
    final known = {
      for (final r in await db.query('documents', columns: ['file_name']))
        r['file_name'] as String
    };
    final entries = await dir.list().toList();
    var added = 0;
    for (final e in entries) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      if (!name.toLowerCase().endsWith('.pdf') || known.contains(name)) {
        continue;
      }
      int pageCount;
      try {
        pageCount = await _validatedPageCount(e.path);
      } catch (_) {
        continue;
      }
      final stat = await e.stat();
      final id = _newId();
      final fileName = '$id.pdf';
      final dest = p.join(dir.path, fileName);
      await e.rename(dest);
      final doc = Document(
        id: id,
        title: cleanTitle(p.basenameWithoutExtension(name)),
        fileName: fileName,
        pageCount: pageCount,
        sizeBytes: stat.size,
        createdAt: stat.modified,
        updatedAt: stat.modified,
      );
      await db.insert('documents', doc.toRow());
      added++;
    }
    if (added > 0) _notify();
    return added;
  }
}
