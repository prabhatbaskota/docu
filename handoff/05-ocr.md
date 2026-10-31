# 05-ocr

Complete final integrated files. Apply the bundle as a whole; shared imports cross feature boundaries.

See [test steps and limits](README.md).

## `mobile/lib/core/database.dart`

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  /// Pass [path] only in tests (e.g. inMemoryDatabasePath).
  static Future<Database> open([String? path]) async {
    String dbPath;
    if (path != null) {
      dbPath = path;
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final support = await getApplicationSupportDirectory();
      await support.create(recursive: true);
      dbPath = p.join(support.path, 'docapp.db');
    } else {
      dbPath = p.join(await getDatabasesPath(), 'docapp.db');
    }
    return openDatabase(dbPath, version: 4, onCreate: _create,
        onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await db.execute(
            'ALTER TABLE documents ADD COLUMN compressed INTEGER NOT NULL DEFAULT 0');
      }
      if (oldVersion < 3) {
        await db.execute('''CREATE TABLE folders(
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL COLLATE NOCASE UNIQUE,
          created_at INTEGER NOT NULL
        )''');
        await db.execute('ALTER TABLE documents ADD COLUMN folder_id TEXT');
        await db.execute(
            'CREATE INDEX idx_documents_folder ON documents(folder_id)');
      }
      if (oldVersion < 4) await _ocr(db);
    });
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE documents(
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        file_name TEXT NOT NULL,
        page_count INTEGER NOT NULL,
        size_bytes INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        favorite INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        compressed INTEGER NOT NULL DEFAULT 0,
        folder_id TEXT
      )''');
    await db
        .execute('CREATE INDEX idx_documents_updated ON documents(updated_at)');
    await db
        .execute('CREATE INDEX idx_documents_folder ON documents(folder_id)');
    await db.execute('''CREATE TABLE folders(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL COLLATE NOCASE UNIQUE,
      created_at INTEGER NOT NULL
    )''');
    await db.execute('''
      CREATE TABLE settings(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''');
    await _ocr(db);
  }

  static Future<void> _ocr(Database db) async {
    await db.execute(
        "ALTER TABLE documents ADD COLUMN ocr_status TEXT NOT NULL DEFAULT ''");
    await db.execute('''CREATE TABLE ocr_pages(
      document_id TEXT NOT NULL, page_index INTEGER NOT NULL,
      text TEXT NOT NULL, words TEXT NOT NULL,
      PRIMARY KEY(document_id,page_index))''');
  }
}

/// Where PDFs live: <app documents>/DocApp
Future<Directory> documentsDir() async {
  final base = await getApplicationDocumentsDirectory();
  final d = Directory(p.join(base.path, 'DocApp'));
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

class SettingsStore {
  SettingsStore(this.db);
  final Database db;

  Future<String?> get(String key) async {
    final r = await db.query('settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  Future<void> set(String key, String value) async {
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
```

## `mobile/lib/core/ocr_service.dart`

```dart
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
```

## `mobile/lib/core/searchable_pdf.dart`

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

Uint8List _jpg((Uint8List,int,int) a)=>img.encodeJpg(img.Image.fromBytes(
  width:a.$2,height:a.$3,bytes:a.$1.buffer,numChannels:4,order:img.ChannelOrder.bgra),quality:90);

/// Visible page raster plus Unicode word text using PDF text rendering mode 3.
Future<void> writeSearchablePdf(String sourcePath,List<Map<String,Object?>> recognized,String output,
    {ByteData? latinFont,ByteData? devanagariFont})async {
    final latin =
        pw.Font.ttf(latinFont ?? await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final deva = pw.Font.ttf(
        devanagariFont ?? await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf'));
    final source = await PdfDocument.openFile(sourcePath);
    final out = pw.Document();
    try {
      for (var i = 0; i < source.pages.length; i++) {
        final p = source.pages[i];
        final scale = math.min(2.5, 3000 / math.max(p.width, p.height));
        final raster = await p.render(
            width: (p.width * scale).round(),
            height: (p.height * scale).round());
        if (raster == null) {
          throw const FormatException('Could not export this page.');
        }
        final pixels = Uint8List.fromList(raster.pixels),
            w = raster.width,
            h = raster.height;
        raster.dispose();
        final image = pw.MemoryImage(await compute(_jpg, (pixels, w, h)));
        final row = recognized.where((r) => r['page_index'] == i).firstOrNull;
        final words =
            row == null ? [] : jsonDecode(row['words'] as String) as List;
        out.addPage(pw.Page(
            pageFormat: PdfPageFormat(p.width, p.height),
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Stack(children: [
                  pw.Positioned.fill(
                      child: pw.Image(image, fit: pw.BoxFit.fill)),
                  for (final word in words)
                    pw.Positioned(
                        left: (word['x'] as num) * p.width,
                        top: (word['y'] as num) * p.height,
                        child: pw.SizedBox(
                            width: math.max(1, (word['w'] as num) * p.width),
                            height: math.max(1, (word['h'] as num) * p.height),
                            child: pw.FittedBox(
                                fit: pw.BoxFit.fill,
                                child: pw.Text(word['text'] as String,
                                    style: pw.TextStyle(
                                        font: RegExp(r'[\u0900-\u097f]')
                                                .hasMatch(word['text'])
                                            ? deva
                                            : latin,
                                        fontSize: 12,
                                        renderingMode:
                                            PdfTextRenderingMode.invisible))))),
                ])));
      }
      await File(output).writeAsBytes(await out.save(), flush: true);
    } finally {
      source.dispose();
    }
}
```

## `mobile/lib/features/documents/document.dart`

```dart
enum SortMode { recent, name, size }

extension SortModeLabel on SortMode {
  String get label => switch (this) {
        SortMode.recent => 'Recent',
        SortMode.name => 'Name',
        SortMode.size => 'Size',
      };
}

class DocQuery {
  final String text;
  final bool favoritesOnly;
  final SortMode sort;
  const DocQuery({
    this.text = '',
    this.favoritesOnly = false,
    this.sort = SortMode.recent,
  });

  bool get isFiltered => text.trim().isNotEmpty || favoritesOnly;

  DocQuery copyWith({String? text, bool? favoritesOnly, SortMode? sort}) =>
      DocQuery(
        text: text ?? this.text,
        favoritesOnly: favoritesOnly ?? this.favoritesOnly,
        sort: sort ?? this.sort,
      );
}

class Document {
  final String id;
  final String title;
  final String fileName; // relative to the library folder
  final int pageCount;
  final int sizeBytes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool favorite;
  final bool compressed;
  final String? folderId;
  final String ocrStatus;
  final String? snippet;

  const Document({
    required this.id,
    required this.title,
    required this.fileName,
    required this.pageCount,
    required this.sizeBytes,
    required this.createdAt,
    required this.updatedAt,
    this.favorite = false,
    this.compressed = false,
    this.folderId,
    this.ocrStatus = '',
    this.snippet,
  });

  factory Document.fromRow(Map<String, Object?> r) => Document(
        id: r['id'] as String,
        title: r['title'] as String,
        fileName: r['file_name'] as String,
        pageCount: r['page_count'] as int,
        sizeBytes: r['size_bytes'] as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
        favorite: (r['favorite'] as int) == 1,
        compressed: r['compressed'] == 1,
        folderId: r['folder_id'] as String?,
        ocrStatus: r['ocr_status'] as String? ?? '',
        snippet: r['snippet'] as String?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'title': title,
        'file_name': fileName,
        'page_count': pageCount,
        'size_bytes': sizeBytes,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'favorite': favorite ? 1 : 0,
        'deleted': 0,
        'compressed': compressed ? 1 : 0,
        'folder_id': folderId,
      };
}
```

## `mobile/lib/features/documents/document_card.dart`

```dart
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/format.dart';
import 'document.dart';

/// First-page preview of a PDF file.
class DocThumb extends StatelessWidget {
  final String path;
  final Object versionKey;
  const DocThumb({super.key, required this.path, required this.versionKey});

  @override
  Widget build(BuildContext context) {
    return PdfDocumentViewBuilder.file(
      path,
      key: ValueKey('$path|$versionKey'),
      builder: (context, document) {
        if (document == null || document.pages.isEmpty) {
          return const Center(child: Icon(Icons.picture_as_pdf_outlined));
        }
        final page = document.pages.first;
        return Center(
          child: AspectRatio(
            aspectRatio: page.width / page.height,
            child: PdfPageView(document: document, pageNumber: 1),
          ),
        );
      },
    );
  }
}

class DocumentCard extends StatelessWidget {
  final Document doc;
  final String path;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onFavorite;

  const DocumentCard({
    super.key,
    required this.doc,
    required this.path,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? cs.primary : cs.outlineVariant,
          width: selected ? 3 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: cs.surfaceContainerHighest,
                    padding: const EdgeInsets.all(8),
                    child: DocThumb(path: path, versionKey: doc.updatedAt),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      tooltip: doc.favorite
                          ? 'Remove from favorites'
                          : 'Add to favorites',
                      icon: Icon(
                        doc.favorite ? Icons.star : Icons.star_border,
                        color:
                            doc.favorite ? Colors.amber : cs.onSurfaceVariant,
                      ),
                      onPressed: onFavorite,
                    ),
                  ),
                  if (selected)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Icon(Icons.check_circle, color: cs.primary),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doc.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleSmall),
                  if (doc.snippet != null)
                    Text(doc.snippet!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall),
                  if (doc.ocrStatus.isNotEmpty)
                    Text(
                        switch (doc.ocrStatus) {
                          'reading' => 'Reading text…',
                          'ready' => 'Text ready',
                          _ => 'Text reading failed'
                        },
                        style: tt.labelSmall),
                  const SizedBox(height: 2),
                  Text(
                    '${doc.pageCount} page${doc.pageCount == 1 ? '' : 's'}  ·  ${fmtDate(doc.updatedAt)}',
                    style: tt.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact row used on Home and in the Files list view.
class DocumentRow extends StatelessWidget {
  final Document doc;
  final String path;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onFavorite;

  const DocumentRow({
    super.key,
    required this.doc,
    required this.path,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: selected ? cs.secondaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              if (selecting)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected ? cs.primary : cs.outline,
                  ),
                ),
              Container(
                width: 40,
                height: 52,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: DocThumb(path: path, versionKey: doc.updatedAt),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(doc.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleSmall),
                    if (doc.snippet != null)
                      Text(doc.snippet!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall),
                    if (doc.ocrStatus.isNotEmpty)
                      Text(
                          switch (doc.ocrStatus) {
                            'reading' => 'Reading text…',
                            'ready' => 'Text ready',
                            _ => 'Text reading failed'
                          },
                          style: tt.labelSmall),
                    const SizedBox(height: 2),
                    Text(
                      '${doc.pageCount} page${doc.pageCount == 1 ? '' : 's'}  ·  ${fmtDate(doc.updatedAt)}',
                      style: tt.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip:
                    doc.favorite ? 'Remove from favorites' : 'Add to favorites',
                icon: Icon(
                  doc.favorite ? Icons.star : Icons.star_border,
                  color: doc.favorite ? Colors.amber : cs.onSurfaceVariant,
                ),
                onPressed: onFavorite,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

## `mobile/lib/features/documents/document_repository.dart`

```dart
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

  void refresh() => _notify();

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
      where.add(
          r"(title LIKE ? ESCAPE '\' OR EXISTS (SELECT 1 FROM ocr_pages o WHERE o.document_id=documents.id AND o.text LIKE ? ESCAPE '\'))");
      args.add('%${_escapeLike(text)}%');
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
    final result = <Document>[];
    for (final row in rows) {
      final data = Map<String, Object?>.from(row);
      if (text.isNotEmpty) {
        final matches = await db.query('ocr_pages',
            columns: ['text'],
            where: r"document_id = ? AND text LIKE ? ESCAPE '\'",
            whereArgs: [row['id'], '%${_escapeLike(text)}%'],
            orderBy: 'page_index',
            limit: 1);
        if (matches.isNotEmpty) {
          final content = matches.first['text'] as String;
          final match = content.toLowerCase().indexOf(text.toLowerCase());
          final start = (match - 30).clamp(0, content.length);
          data['snippet'] =
              '${start > 0 ? '…' : ''}${content.substring(start, (start + 120).clamp(0, content.length)).replaceAll('\n', ' ')}';
        }
      }
      result.add(Document.fromRow(data));
    }
    return result;
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
    await db.delete('ocr_pages', where: 'document_id = ?', whereArgs: [id]);
    await db.update(
      'documents',
      {
        'page_count': pageCount,
        'size_bytes': await File(dest).length(),
        'updated_at': now,
        'compressed': compressed ? 1 : 0,
        'ocr_status': '',
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
      await db.delete('ocr_pages',where:'document_id = ?',whereArgs:[r['id']]);
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
```

## `mobile/lib/features/documents/document_screen.dart`

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../editor_launch.dart';
import 'actions.dart';
import 'providers.dart';
import 'ocr_actions.dart';

class DocumentScreen extends ConsumerWidget {
  final String id;
  const DocumentScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(documentProvider(id));
    final doc = async.value;
    if (doc == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: async.isLoading
              ? const CircularProgressIndicator()
              : const Text('Document not found'),
        ),
      );
    }
    final repo = ref.watch(repositoryProvider);
    final path = repo.pathOf(doc);

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () => renameDocument(context, doc),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(doc.title, overflow: TextOverflow.ellipsis),
          ),
        ),
        actions: [
          IconButton(
              tooltip: 'Text',
              icon: const Icon(Icons.text_snippet_outlined),
              onPressed: () => showTextActions(context, doc)),
          IconButton(
            tooltip:
                doc.favorite ? 'Remove from favorites' : 'Add to favorites',
            icon: Icon(doc.favorite ? Icons.star : Icons.star_border,
                color: doc.favorite ? Colors.amber : null),
            onPressed: () => repo.setFavorite(doc.id, !doc.favorite),
          ),
        ],
      ),
      body: PdfViewer.file(path, key: ValueKey('$path|${doc.updatedAt}')),
      bottomNavigationBar: Material(
        elevation: 3,
        child: SafeArea(
          child: Row(
            children: [
              Platform.isWindows || Platform.isMacOS || Platform.isLinux
                  ? _BarButton(Icons.save_alt_outlined, 'Export',
                      () => exportDocument(context, doc))
                  : _BarButton(Icons.ios_share, 'Share',
                      () => shareDocuments(context, [doc])),
              _BarButton(Icons.view_module_outlined, 'Edit pages',
                  () => editDocument(context, doc)),
              _BarButton(
                  Icons.more_horiz,
                  'More',
                  () => showDocumentMenu(context, doc,
                      leaveScreenOnDelete: true)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _BarButton(this.icon, this.label, this.onTap);

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon),
                const SizedBox(height: 2),
                Text(label, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        ),
      );
}
```

## `mobile/lib/features/documents/ocr_actions.dart`

```dart
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
```

## `mobile/lib/features/settings/settings_page.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../branding/docu_logo.dart';
import '../documents/providers.dart';
import '../../core/database.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Center(child: DocuLogo(size: 72)),
          ),
          Center(
            child: Text('docu',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Appearance',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto),
                    label: Text('System')),
                ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('Light')),
                ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('Dark')),
              ],
              selected: {mode},
              onSelectionChanged: (s) =>
                  ref.read(themeProvider.notifier).setMode(s.first),
            ),
          ),
          const SizedBox(height: 16),
          _OcrLanguage(store: ref.read(settingsStoreProvider)),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Private by default'),
            subtitle:
                Text('Documents stay on this device unless you share them.'),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            subtitle: Text('0.1.1'),
          ),
        ],
      ),
    );
  }
}

class _OcrLanguage extends StatefulWidget {
  final SettingsStore store;
  const _OcrLanguage({required this.store});
  @override
  State<_OcrLanguage> createState() => _OcrLanguageState();
}

class _OcrLanguageState extends State<_OcrLanguage> {
  String value = 'auto';
  @override
  void initState() {
    super.initState();
    widget.store.get('ocr_language').then((v) {
      if (mounted) setState(() => value = v ?? 'auto');
    });
  }

  @override
  Widget build(BuildContext context) => ListTile(
      title: const Text('Text recognition'),
      trailing: DropdownButton<String>(
          value: value,
          items: const [
            DropdownMenuItem(value: 'auto', child: Text('Auto')),
            DropdownMenuItem(value: 'english', child: Text('English')),
            DropdownMenuItem(value: 'devanagari', child: Text('Devanagari'))
          ],
          onChanged: (v) {
            setState(() => value = v!);
            widget.store.set('ocr_language', v!);
          }));
}
```

## `mobile/lib/main.dart`

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/database.dart';
import 'core/scan_cleanup.dart';
import 'core/ocr_service.dart';
import 'core/pdf_engine.dart';
import 'features/documents/document_repository.dart';
import 'features/branding/theme.dart';
import 'features/documents/favorites_page.dart';
import 'features/documents/home_page.dart';
import 'features/documents/providers.dart';
import 'features/scan_flow.dart';
import 'features/documents/selection_bar.dart';
import 'features/desktop/desktop_home.dart';
import 'features/tools_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await cleanOldScanImages();
  await pdfrxFlutterInitialize();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final db = await AppDatabase.open();
  final dir = await documentsDir();
  final repo = DocumentRepository(
    db: db,
    dir: dir,
    pageCounter: engine.pageCount,
  );
  final settings = SettingsStore(db);

  await repo.purgeDeleted();
  await repo.syncFromDisk(); // adopt PDFs created by earlier versions
  OcrService(repo).resume();

  final saved = await settings.get('theme');
  var theme = ThemeMode.system;
  for (final m in ThemeMode.values) {
    if (m.name == saved) theme = m;
  }

  runApp(ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      settingsStoreProvider.overrideWithValue(settings),
      initialThemeProvider.overrideWithValue(theme),
    ],
    child: const DocApp(),
  ));
}

class DocApp extends ConsumerWidget {
  const DocApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
        title: 'docu',
        debugShowCheckedModeBanner: false,
        themeMode: ref.watch(themeProvider),
        theme: docuTheme(Brightness.light),
        darkTheme: docuTheme(Brightness.dark),
        home: Platform.isWindows || Platform.isLinux || Platform.isMacOS
            ? const DesktopHome()
            : const Shell(),
      );
}

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});
  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final selecting = ref.watch(selectionProvider).isNotEmpty;
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(selectionProvider.notifier).clear();
      },
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(
          index: _i,
          children: const [
            ScanPage(),
            HomePage(),
            ToolsPage(),
            FavoritesPage()
          ],
        ),
        bottomNavigationBar: selecting
            ? SelectionBar(hostContext: context)
            : NavigationBar(
                selectedIndex: _i,
                onDestinationSelected: (index) => setState(() => _i = index),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.document_scanner_outlined),
                    selectedIcon: Icon(Icons.document_scanner_rounded),
                    label: 'Scan',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.build_outlined),
                    selectedIcon: Icon(Icons.build_rounded),
                    label: 'Tools',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.star_outline_rounded),
                    selectedIcon: Icon(Icons.star_rounded),
                    label: 'Favorites',
                  ),
                ],
              ),
      ),
    );
  }
}

class ScanPage extends StatelessWidget {
  const ScanPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scan')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.document_scanner_outlined,
                    size: 80, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 24),
                Text('Scan a document',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text('Capture pages and save them as a PDF.'),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => startScan(context),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Start scanning'),
                ),
              ],
            ),
          ),
        ),
      );
}
```

## `mobile/test/ocr_repository_test.dart`

```dart
import 'dart:io';
import 'package:docapp/core/database.dart';
import 'package:docapp/features/documents/document.dart';
import 'package:docapp/features/documents/document_repository.dart';
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
```

## `desktop/lib/core/database.dart`

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  /// Pass [path] only in tests (e.g. inMemoryDatabasePath).
  static Future<Database> open([String? path]) async {
    String dbPath;
    if (path != null) {
      dbPath = path;
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final support = await getApplicationSupportDirectory();
      await support.create(recursive: true);
      dbPath = p.join(support.path, 'docapp.db');
    } else {
      dbPath = p.join(await getDatabasesPath(), 'docapp.db');
    }
    return openDatabase(dbPath, version: 5, onCreate: _create,
        onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await db.execute(
            'ALTER TABLE documents ADD COLUMN compressed INTEGER NOT NULL DEFAULT 0');
      }
      if (oldVersion < 3) {
        await db.execute('''CREATE TABLE folders(
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL COLLATE NOCASE UNIQUE,
          created_at INTEGER NOT NULL
        )''');
        await db.execute('ALTER TABLE documents ADD COLUMN folder_id TEXT');
        await db.execute(
            'CREATE INDEX idx_documents_folder ON documents(folder_id)');
      }
      if (oldVersion < 4) {
        await db.execute('''CREATE TABLE recent_files(
          path TEXT PRIMARY KEY,
          opened_at INTEGER NOT NULL
        )''');
      }
      if (oldVersion < 5) await _ocr(db);
    });
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE documents(
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        file_name TEXT NOT NULL,
        page_count INTEGER NOT NULL,
        size_bytes INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        favorite INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        compressed INTEGER NOT NULL DEFAULT 0,
        folder_id TEXT
      )''');
    await db
        .execute('CREATE INDEX idx_documents_updated ON documents(updated_at)');
    await db
        .execute('CREATE INDEX idx_documents_folder ON documents(folder_id)');
    await db.execute('''CREATE TABLE folders(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL COLLATE NOCASE UNIQUE,
      created_at INTEGER NOT NULL
    )''');
    await db.execute('''
      CREATE TABLE settings(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''');
    await db.execute('''CREATE TABLE recent_files(
      path TEXT PRIMARY KEY,
      opened_at INTEGER NOT NULL
    )''');
    await _ocr(db);
  }

  static Future<void> _ocr(Database db) async {
    await db.execute(
        "ALTER TABLE documents ADD COLUMN ocr_status TEXT NOT NULL DEFAULT ''");
    await db.execute('''CREATE TABLE ocr_pages(
      document_id TEXT NOT NULL, page_index INTEGER NOT NULL,
      text TEXT NOT NULL, words TEXT NOT NULL,
      PRIMARY KEY(document_id,page_index))''');
  }
}

/// Where PDFs live: <app documents>/DocApp
Future<Directory> documentsDir() async {
  final base = await getApplicationDocumentsDirectory();
  final d = Directory(p.join(base.path, 'DocApp'));
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

class SettingsStore {
  SettingsStore(this.db);
  final Database db;

  Future<String?> get(String key) async {
    final r = await db.query('settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  Future<void> set(String key, String value) async {
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
```

## `desktop/lib/core/ocr_service.dart`

```dart
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
    if (_running) return;
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
    if (!Platform.isAndroid && !Platform.isIOS) {
      await _readDesktop(id);
      return;
    }
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

  Future<void> _readDesktop(String id) async {
    final record = await repo.get(id);
    if (record == null) return;
    final settings = SettingsStore(repo.db);
    var executable = await settings.get('tesseract_path') ?? 'tesseract';
    if (executable == 'tesseract' && Platform.isWindows) {
      final installed = File(r'C:\Program Files\Tesseract-OCR\tesseract.exe');
      if (await installed.exists()) executable = installed.path;
    }
    final language = await settings.get('ocr_language') ?? 'auto';
    final languages = language == 'english'
        ? 'eng'
        : language == 'devanagari'
            ? 'hin+nep'
            : 'eng+hin+nep';
    final source = await PdfDocument.openFile(repo.pathOf(record));
    final folder = await getTemporaryDirectory();
    final input = File('${folder.path}/ocr_$id.jpg');
    try {
      for (var i = 0; i < source.pages.length; i++) {
        final page = source.pages[i];
        final scale = math.min(2.8, 2600 / math.max(page.width, page.height));
        final raster = await page.render(
            width: (page.width * scale).round(),
            height: (page.height * scale).round());
        if (raster == null) throw const FormatException('Could not read page.');
        final w = raster.width, h = raster.height;
        final pixels = Uint8List.fromList(raster.pixels);
        raster.dispose();
        await input.writeAsBytes(await compute(_jpg, (pixels, w, h)));
        final result = await Process.run(
            executable, [input.path, 'stdout', '-l', languages, 'tsv'],
            stdoutEncoding: utf8, stderrEncoding: utf8);
        if (result.exitCode != 0) {
          throw const FormatException(
              'Install Tesseract with English, Hindi and Nepali data.');
        }
        final words = <Map<String, Object>>[];
        final lines = <String, List<String>>{};
        for (final row
            in const LineSplitter().convert(result.stdout as String).skip(1)) {
          final c = row.split('\t');
          if (c.length < 12 || c[0] != '5' || c[11].trim().isEmpty) continue;
          final text = c.sublist(11).join('\t');
          words.add({
            'text': text,
            'x': int.parse(c[6]) / w,
            'y': int.parse(c[7]) / h,
            'w': int.parse(c[8]) / w,
            'h': int.parse(c[9]) / h
          });
          lines.putIfAbsent(c.sublist(1, 5).join(':'), () => []).add(text);
        }
        final current = await repo.get(id);
        if (current == null || current.updatedAt != record.updatedAt) return;
        await repo.db.insert(
            'ocr_pages',
            {
              'document_id': id,
              'page_index': i,
              'text': lines.values.map((l) => l.join(' ')).join('\n'),
              'words': jsonEncode(words)
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await repo.db.update('documents', {'ocr_status': 'ready'},
          where: 'id = ?', whereArgs: [id]);
    } finally {
      source.dispose();
      if (await input.exists()) await input.delete();
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
```

## `desktop/lib/core/searchable_pdf.dart`

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

Uint8List _jpg((Uint8List,int,int) a)=>img.encodeJpg(img.Image.fromBytes(
  width:a.$2,height:a.$3,bytes:a.$1.buffer,numChannels:4,order:img.ChannelOrder.bgra),quality:90);

/// Visible page raster plus Unicode word text using PDF text rendering mode 3.
Future<void> writeSearchablePdf(String sourcePath,List<Map<String,Object?>> recognized,String output,
    {ByteData? latinFont,ByteData? devanagariFont})async {
    final latin =
        pw.Font.ttf(latinFont ?? await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final deva = pw.Font.ttf(
        devanagariFont ?? await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf'));
    final source = await PdfDocument.openFile(sourcePath);
    final out = pw.Document();
    try {
      for (var i = 0; i < source.pages.length; i++) {
        final p = source.pages[i];
        final scale = math.min(2.5, 3000 / math.max(p.width, p.height));
        final raster = await p.render(
            width: (p.width * scale).round(),
            height: (p.height * scale).round());
        if (raster == null) {
          throw const FormatException('Could not export this page.');
        }
        final pixels = Uint8List.fromList(raster.pixels),
            w = raster.width,
            h = raster.height;
        raster.dispose();
        final image = pw.MemoryImage(await compute(_jpg, (pixels, w, h)));
        final row = recognized.where((r) => r['page_index'] == i).firstOrNull;
        final words =
            row == null ? [] : jsonDecode(row['words'] as String) as List;
        out.addPage(pw.Page(
            pageFormat: PdfPageFormat(p.width, p.height),
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Stack(children: [
                  pw.Positioned.fill(
                      child: pw.Image(image, fit: pw.BoxFit.fill)),
                  for (final word in words)
                    pw.Positioned(
                        left: (word['x'] as num) * p.width,
                        top: (word['y'] as num) * p.height,
                        child: pw.SizedBox(
                            width: math.max(1, (word['w'] as num) * p.width),
                            height: math.max(1, (word['h'] as num) * p.height),
                            child: pw.FittedBox(
                                fit: pw.BoxFit.fill,
                                child: pw.Text(word['text'] as String,
                                    style: pw.TextStyle(
                                        font: RegExp(r'[\u0900-\u097f]')
                                                .hasMatch(word['text'])
                                            ? deva
                                            : latin,
                                        fontSize: 12,
                                        renderingMode:
                                            PdfTextRenderingMode.invisible))))),
                ])));
      }
      await File(output).writeAsBytes(await out.save(), flush: true);
    } finally {
      source.dispose();
    }
}
```

## `desktop/lib/features/documents/document.dart`

```dart
enum SortMode { recent, name, size }

extension SortModeLabel on SortMode {
  String get label => switch (this) {
        SortMode.recent => 'Recent',
        SortMode.name => 'Name',
        SortMode.size => 'Size',
      };
}

class DocQuery {
  final String text;
  final bool favoritesOnly;
  final SortMode sort;
  const DocQuery({
    this.text = '',
    this.favoritesOnly = false,
    this.sort = SortMode.recent,
  });

  bool get isFiltered => text.trim().isNotEmpty || favoritesOnly;

  DocQuery copyWith({String? text, bool? favoritesOnly, SortMode? sort}) =>
      DocQuery(
        text: text ?? this.text,
        favoritesOnly: favoritesOnly ?? this.favoritesOnly,
        sort: sort ?? this.sort,
      );
}

class Document {
  final String id;
  final String title;
  final String fileName; // relative to the library folder
  final int pageCount;
  final int sizeBytes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool favorite;
  final bool compressed;
  final String? folderId;
  final String ocrStatus;
  final String? snippet;

  const Document({
    required this.id,
    required this.title,
    required this.fileName,
    required this.pageCount,
    required this.sizeBytes,
    required this.createdAt,
    required this.updatedAt,
    this.favorite = false,
    this.compressed = false,
    this.folderId,
    this.ocrStatus = '',
    this.snippet,
  });

  factory Document.fromRow(Map<String, Object?> r) => Document(
        id: r['id'] as String,
        title: r['title'] as String,
        fileName: r['file_name'] as String,
        pageCount: r['page_count'] as int,
        sizeBytes: r['size_bytes'] as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
        favorite: (r['favorite'] as int) == 1,
        compressed: r['compressed'] == 1,
        folderId: r['folder_id'] as String?,
        ocrStatus: r['ocr_status'] as String? ?? '',
        snippet: r['snippet'] as String?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'title': title,
        'file_name': fileName,
        'page_count': pageCount,
        'size_bytes': sizeBytes,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'favorite': favorite ? 1 : 0,
        'deleted': 0,
        'compressed': compressed ? 1 : 0,
        'folder_id': folderId,
      };
}
```

## `desktop/lib/features/documents/document_card.dart`

```dart
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/format.dart';
import 'document.dart';

/// First-page preview of a PDF file.
class DocThumb extends StatelessWidget {
  final String path;
  final Object versionKey;
  const DocThumb({super.key, required this.path, required this.versionKey});

  @override
  Widget build(BuildContext context) {
    return PdfDocumentViewBuilder.file(
      path,
      key: ValueKey('$path|$versionKey'),
      builder: (context, document) {
        if (document == null || document.pages.isEmpty) {
          return const Center(child: Icon(Icons.picture_as_pdf_outlined));
        }
        final page = document.pages.first;
        return Center(
          child: AspectRatio(
            aspectRatio: page.width / page.height,
            child: PdfPageView(document: document, pageNumber: 1),
          ),
        );
      },
    );
  }
}

class DocumentCard extends StatelessWidget {
  final Document doc;
  final String path;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onFavorite;

  const DocumentCard({
    super.key,
    required this.doc,
    required this.path,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? cs.primary : cs.outlineVariant,
          width: selected ? 3 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: cs.surfaceContainerHighest,
                    padding: const EdgeInsets.all(8),
                    child: DocThumb(path: path, versionKey: doc.updatedAt),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      tooltip: doc.favorite
                          ? 'Remove from favorites'
                          : 'Add to favorites',
                      icon: Icon(
                        doc.favorite ? Icons.star : Icons.star_border,
                        color:
                            doc.favorite ? Colors.amber : cs.onSurfaceVariant,
                      ),
                      onPressed: onFavorite,
                    ),
                  ),
                  if (selected)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Icon(Icons.check_circle, color: cs.primary),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doc.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleSmall),
                  if (doc.snippet != null)
                    Text(doc.snippet!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall),
                  if (doc.ocrStatus.isNotEmpty)
                    Text(
                        switch (doc.ocrStatus) {
                          'reading' => 'Reading text…',
                          'ready' => 'Text ready',
                          _ => 'Text reading failed'
                        },
                        style: tt.labelSmall),
                  const SizedBox(height: 2),
                  Text(
                    '${doc.pageCount} page${doc.pageCount == 1 ? '' : 's'}  ·  ${fmtDate(doc.updatedAt)}',
                    style: tt.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact row used on Home and in the Files list view.
class DocumentRow extends StatelessWidget {
  final Document doc;
  final String path;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onFavorite;

  const DocumentRow({
    super.key,
    required this.doc,
    required this.path,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: selected ? cs.secondaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              if (selecting)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected ? cs.primary : cs.outline,
                  ),
                ),
              Container(
                width: 40,
                height: 52,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: DocThumb(path: path, versionKey: doc.updatedAt),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(doc.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleSmall),
                    if (doc.snippet != null)
                      Text(doc.snippet!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall),
                    if (doc.ocrStatus.isNotEmpty)
                      Text(
                          switch (doc.ocrStatus) {
                            'reading' => 'Reading text…',
                            'ready' => 'Text ready',
                            _ => 'Text reading failed'
                          },
                          style: tt.labelSmall),
                    const SizedBox(height: 2),
                    Text(
                      '${doc.pageCount} page${doc.pageCount == 1 ? '' : 's'}  ·  ${fmtDate(doc.updatedAt)}',
                      style: tt.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip:
                    doc.favorite ? 'Remove from favorites' : 'Add to favorites',
                icon: Icon(
                  doc.favorite ? Icons.star : Icons.star_border,
                  color: doc.favorite ? Colors.amber : cs.onSurfaceVariant,
                ),
                onPressed: onFavorite,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

## `desktop/lib/features/documents/document_repository.dart`

```dart
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

  void refresh() => _notify();

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
      where.add(
          r"(title LIKE ? ESCAPE '\' OR EXISTS (SELECT 1 FROM ocr_pages o WHERE o.document_id=documents.id AND o.text LIKE ? ESCAPE '\'))");
      args.add('%${_escapeLike(text)}%');
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
    final result = <Document>[];
    for (final row in rows) {
      final data = Map<String, Object?>.from(row);
      if (text.isNotEmpty) {
        final matches = await db.query('ocr_pages',
            columns: ['text'],
            where: r"document_id = ? AND text LIKE ? ESCAPE '\'",
            whereArgs: [row['id'], '%${_escapeLike(text)}%'],
            orderBy: 'page_index',
            limit: 1);
        if (matches.isNotEmpty) {
          final content = matches.first['text'] as String;
          final match = content.toLowerCase().indexOf(text.toLowerCase());
          final start = (match - 30).clamp(0, content.length);
          data['snippet'] =
              '${start > 0 ? '…' : ''}${content.substring(start, (start + 120).clamp(0, content.length)).replaceAll('\n', ' ')}';
        }
      }
      result.add(Document.fromRow(data));
    }
    return result;
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
    await db.delete('ocr_pages', where: 'document_id = ?', whereArgs: [id]);
    await db.update(
      'documents',
      {
        'page_count': pageCount,
        'size_bytes': await File(dest).length(),
        'updated_at': now,
        'compressed': compressed ? 1 : 0,
        'ocr_status': '',
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
      await db.delete('ocr_pages',where:'document_id = ?',whereArgs:[r['id']]);
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
```

## `desktop/lib/features/documents/document_screen.dart`

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../editor_launch.dart';
import 'actions.dart';
import 'providers.dart';
import 'ocr_actions.dart';

class DocumentScreen extends ConsumerWidget {
  final String id;
  const DocumentScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(documentProvider(id));
    final doc = async.value;
    if (doc == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: async.isLoading
              ? const CircularProgressIndicator()
              : const Text('Document not found'),
        ),
      );
    }
    final repo = ref.watch(repositoryProvider);
    final path = repo.pathOf(doc);

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () => renameDocument(context, doc),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(doc.title, overflow: TextOverflow.ellipsis),
          ),
        ),
        actions: [
          IconButton(
              tooltip: 'Text',
              icon: const Icon(Icons.text_snippet_outlined),
              onPressed: () => showTextActions(context, doc)),
          IconButton(
            tooltip:
                doc.favorite ? 'Remove from favorites' : 'Add to favorites',
            icon: Icon(doc.favorite ? Icons.star : Icons.star_border,
                color: doc.favorite ? Colors.amber : null),
            onPressed: () => repo.setFavorite(doc.id, !doc.favorite),
          ),
        ],
      ),
      body: PdfViewer.file(path, key: ValueKey('$path|${doc.updatedAt}')),
      bottomNavigationBar: Material(
        elevation: 3,
        child: SafeArea(
          child: Row(
            children: [
              Platform.isWindows || Platform.isMacOS || Platform.isLinux
                  ? _BarButton(Icons.save_alt_outlined, 'Export',
                      () => exportDocument(context, doc))
                  : _BarButton(Icons.ios_share, 'Share',
                      () => shareDocuments(context, [doc])),
              _BarButton(Icons.view_module_outlined, 'Edit pages',
                  () => editDocument(context, doc)),
              _BarButton(
                  Icons.more_horiz,
                  'More',
                  () => showDocumentMenu(context, doc,
                      leaveScreenOnDelete: true)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _BarButton(this.icon, this.label, this.onTap);

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon),
                const SizedBox(height: 2),
                Text(label, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        ),
      );
}
```

## `desktop/lib/features/documents/ocr_actions.dart`

```dart
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
                      subtitle: Text(doc.ocrStatus == 'error'
                          ? 'Install Tesseract with eng, hin and nep data, then choose its executable in Settings.'
                          : 'Text recognition runs on this device.'),
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
```

## `desktop/lib/features/settings/settings_page.dart`

```dart
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../branding/docu_logo.dart';
import '../documents/providers.dart';
import '../../core/database.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Center(child: DocuLogo(size: 72)),
          ),
          Center(
            child: Text('docu',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Appearance',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto),
                    label: Text('System')),
                ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('Light')),
                ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('Dark')),
              ],
              selected: {mode},
              onSelectionChanged: (s) =>
                  ref.read(themeProvider.notifier).setMode(s.first),
            ),
          ),
          const SizedBox(height: 16),
          _OcrLanguage(store: ref.read(settingsStoreProvider)),
          if (Platform.isWindows)
            ListTile(
                title: const Text('Tesseract OCR'),
                subtitle: const Text(
                    'Use a local Tesseract executable with eng, hin and nep language data.'),
                trailing: const Icon(Icons.folder_open),
                onTap: () async {
                  final selected = await FilePicker.platform.pickFiles(
                      type: FileType.custom, allowedExtensions: ['exe']);
                  final path = selected?.files.single.path;
                  if (path != null) {
                    await ref
                        .read(settingsStoreProvider)
                        .set('tesseract_path', path);
                  }
                }),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Private by default'),
            subtitle:
                Text('Documents stay on this device unless you share them.'),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            subtitle: Text('0.1.1'),
          ),
        ],
      ),
    );
  }
}

class _OcrLanguage extends StatefulWidget {
  final SettingsStore store;
  const _OcrLanguage({required this.store});
  @override
  State<_OcrLanguage> createState() => _OcrLanguageState();
}

class _OcrLanguageState extends State<_OcrLanguage> {
  String value = 'auto';
  @override
  void initState() {
    super.initState();
    widget.store.get('ocr_language').then((v) {
      if (mounted) setState(() => value = v ?? 'auto');
    });
  }

  @override
  Widget build(BuildContext context) => ListTile(
      title: const Text('Text recognition'),
      trailing: DropdownButton<String>(
          value: value,
          items: const [
            DropdownMenuItem(value: 'auto', child: Text('Auto')),
            DropdownMenuItem(value: 'english', child: Text('English')),
            DropdownMenuItem(value: 'devanagari', child: Text('Devanagari'))
          ],
          onChanged: (v) {
            setState(() => value = v!);
            widget.store.set('ocr_language', v!);
          }));
}
```

## `desktop/lib/main.dart`

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/database.dart';
import 'core/scan_cleanup.dart';
import 'core/ocr_service.dart';
import 'core/pdf_engine.dart';
import 'features/documents/document_repository.dart';
import 'features/branding/theme.dart';
import 'features/documents/favorites_page.dart';
import 'features/documents/home_page.dart';
import 'features/documents/providers.dart';
import 'features/scan_flow.dart';
import 'features/documents/selection_bar.dart';
import 'features/desktop/desktop_home.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await cleanOldScanImages();
  await pdfrxFlutterInitialize();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final db = await AppDatabase.open();
  final dir = await documentsDir();
  final repo = DocumentRepository(
    db: db,
    dir: dir,
    pageCounter: engine.pageCount,
  );
  final settings = SettingsStore(db);

  await repo.purgeDeleted();
  await repo.syncFromDisk(); // adopt PDFs created by earlier versions

  OcrService(repo).resume();
  final saved = await settings.get('theme');
  var theme = ThemeMode.system;
  for (final m in ThemeMode.values) {
    if (m.name == saved) theme = m;
  }

  String? initialPdfPath;
  if (Platform.isWindows) {
    for (final arg in args) {
      if (arg.toLowerCase().endsWith('.pdf')) {
        initialPdfPath = arg;
        break;
      }
    }
  }
  if (initialPdfPath != null) {
    await repo.recordRecentFile(initialPdfPath);
  }

  runApp(ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      settingsStoreProvider.overrideWithValue(settings),
      initialThemeProvider.overrideWithValue(theme),
    ],
    child: DocApp(initialPdfPath: initialPdfPath),
  ));
}

class DocApp extends ConsumerWidget {
  const DocApp({super.key, this.initialPdfPath});

  final String? initialPdfPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
        title: 'docu',
        debugShowCheckedModeBanner: false,
        themeMode: ref.watch(themeProvider),
        theme: docuTheme(Brightness.light),
        darkTheme: docuTheme(Brightness.dark),
        home: Platform.isWindows || Platform.isLinux || Platform.isMacOS
            ? DesktopHome(initialPdfPath: initialPdfPath)
            : const Shell(),
      );
}

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});
  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  int _i = 1; // 0 = Favorites (left), 1 = Home (right)

  @override
  Widget build(BuildContext context) {
    final selecting = ref.watch(selectionProvider).isNotEmpty;
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(selectionProvider.notifier).clear();
      },
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(
          index: _i,
          children: const [FavoritesPage(), HomePage()],
        ),
        floatingActionButton: selecting
            ? null
            : FloatingActionButton(
                tooltip: 'Scan',
                onPressed: () => startScan(context),
                child: const Icon(Icons.document_scanner_outlined, size: 28),
              ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: selecting
            ? SelectionBar(hostContext: context)
            : BottomAppBar(
                shape: const CircularNotchedRectangle(),
                notchMargin: 8,
                padding: EdgeInsets.zero,
                child: Row(
                  children: [
                    Expanded(
                      child: _NavItem(
                        icon: Icons.star_outline_rounded,
                        selectedIcon: Icons.star_rounded,
                        label: 'Favorites',
                        selected: _i == 0,
                        onTap: () => setState(() => _i = 0),
                      ),
                    ),
                    const SizedBox(width: 88), // room for the scan button
                    Expanded(
                      child: _NavItem(
                        icon: Icons.home_outlined,
                        selectedIcon: Icons.home_rounded,
                        label: 'Home',
                        selected: _i == 1,
                        onTap: () => setState(() => _i = 1),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.primary : cs.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 68,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? selectedIcon : icon, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
```

## `desktop/test/ocr_repository_test.dart`

```dart
import 'dart:io';
import 'package:docapp/core/database.dart';
import 'package:docapp/features/documents/document.dart';
import 'package:docapp/features/documents/document_repository.dart';
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
  test('v4 desktop database upgrades without losing documents', () async {
    final dir = await Directory.systemTemp.createTemp('docu_migrate_');
    final path = '${dir.path}/old.db';
    final old = await openDatabase(path, version: 4, onCreate: (db, _) async {
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
```
