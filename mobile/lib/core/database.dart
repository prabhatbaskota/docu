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
    return openDatabase(dbPath, version: 3, onCreate: _create,
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
