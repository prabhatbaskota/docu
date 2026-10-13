import 'dart:io';

import 'package:docapp/core/database.dart';
import 'package:docapp/features/compress/compress_flow.dart';
import 'package:docapp/features/documents/document.dart';
import 'package:docapp/features/documents/document_repository.dart';
import 'package:docapp/features/documents/providers.dart';
import 'package:docapp/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('Already compressed document skips compression and quality picker',
      (tester) async {
    late Database db;
    late Directory dir;
    late DocumentRepository repo;
    late Document doc;
    await tester.runAsync(() async {
      db = await AppDatabase.open(inMemoryDatabasePath);
      dir = await Directory.systemTemp.createTemp('docapp_compress_');
      repo = DocumentRepository(db: db, dir: dir, pageCounter: (_) async => 1);
      final source = File('${dir.path}/source.pdf');
      await source.writeAsBytes([1, 2, 3]);
      doc = await repo.addFile(source.path, title: 'Already small', compressed: true);
    });
    try {
      await tester.pumpWidget(ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(home: Scaffold(body: Builder(builder: (context) {
          return TextButton(
            onPressed: () => compressDocument(context, doc),
            child: const Text('Try compression'),
          );
        }))),
      ));
      await tester.tap(find.text('Try compression'));
      await tester.runAsync(() async {
        await repo.list(const DocQuery());
      });
      await tester.pumpAndSettle();
      expect(find.text('This file is already compressed. No new copy was created.'),
          findsOneWidget);
      expect(find.text('Balanced'), findsNothing);
      await tester.runAsync(() async {
        expect((await repo.list(const DocQuery())).length, 1);
      });
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await repo.dispose();
        await db.close();
        await dir.delete(recursive: true);
      });
    }
  });

  testWidgets('Document app opens Home and switches to Favorites',
      (tester) async {
    late Database db;
    late Directory dir;
    await tester.runAsync(() async {
      db = await AppDatabase.open(inMemoryDatabasePath);
      dir = await Directory.systemTemp.createTemp('docapp_widget_');
    });
    final repo = DocumentRepository(
      db: db,
      dir: dir,
      pageCounter: (_) async => 1,
    );

    try {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          settingsStoreProvider.overrideWithValue(SettingsStore(db)),
        ],
        child: const DocApp(),
      ));
      await tester.runAsync(() async {
        await repo.list(const DocQuery());
      });
      await tester.pumpAndSettle();

      expect(find.text('docu'), findsOneWidget);
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(find.byTooltip('Scan'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();
      expect(find.text('No favorites yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await repo.dispose();
        await db.close();
        await dir.delete(recursive: true);
      });
    }
  });

  testWidgets('Top Merge selects library PDFs before choosing merge mode',
      (tester) async {
    late Database db;
    late Directory dir;
    late DocumentRepository repo;
    await tester.runAsync(() async {
      db = await AppDatabase.open(inMemoryDatabasePath);
      dir = await Directory.systemTemp.createTemp('docapp_merge_');
      repo = DocumentRepository(db: db, dir: dir, pageCounter: (_) async => 1);
      for (final title in ['Invoice', 'Receipt']) {
        final source = File('${dir.path}/$title.pdf');
        await source.writeAsBytes([1, 2, 3]);
        await repo.addFile(source.path, title: title);
      }
    });

    try {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          settingsStoreProvider.overrideWithValue(SettingsStore(db)),
          // Keep Home empty so this test exercises selection rather than rendering.
          documentsProvider.overrideWith((ref) => Stream.value(<Document>[])),
          favoritesProvider.overrideWith((ref) => Stream.value(<Document>[])),
        ],
        child: const DocApp(),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Merge'));
      await tester.runAsync(() async {
        await repo.list(const DocQuery());
      });
      await tester.pumpAndSettle();

      expect(find.text('Merge PDFs'), findsOneWidget);
      expect(find.text('Browse files...'), findsOneWidget);
      expect(find.text('Invoice'), findsOneWidget);
      expect(find.text('Receipt'), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Continue (0)'))
              .onPressed,
          isNull);

      await tester.tap(find.text('Receipt'));
      await tester.pump();
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Continue (1)'))
              .onPressed,
          isNull);
      await tester.tap(find.text('Invoice'));
      await tester.pump();
      await tester.tap(find.text('Continue (2)'));
      await tester.pumpAndSettle();

      expect(find.text('Compress and merge'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await repo.dispose();
        await db.close();
        await dir.delete(recursive: true);
      });
    }
  });
}
