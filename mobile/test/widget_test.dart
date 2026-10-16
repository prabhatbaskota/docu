import 'dart:io';

import 'package:docapp/core/database.dart';
import 'package:docapp/features/compress/compress_flow.dart';
import 'package:docapp/features/documents/document.dart';
import 'package:docapp/features/documents/document_repository.dart';
import 'package:docapp/features/documents/providers.dart';
import 'package:docapp/features/tools_page.dart';
import 'package:docapp/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets(
      'Already compressed document skips compression and quality picker',
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
      await source.writeAsBytes([37, 80, 68, 70, 45, 49, 46, 55]);
      doc = await repo.addFile(source.path,
          title: 'Already small', compressed: true);
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
      expect(
          find.text(
              'This file is already compressed. No new copy was created.'),
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

  testWidgets('Mobile shell opens Scan and exposes Home, Tools, and Favorites',
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
        child: const MaterialApp(home: Shell()),
      ));
      await tester.runAsync(() async {
        await repo.list(const DocQuery());
      });
      await tester.pumpAndSettle();

      expect(find.text('Scan a document'), findsOneWidget);
      expect(find.text('Start scanning'), findsOneWidget);
      await tester.tap(find.widgetWithText(NavigationDestination, 'Home'));
      await tester.pumpAndSettle();
      expect(find.text('docu'), findsOneWidget);
      expect(find.text('Nothing here yet'), findsOneWidget);
      await tester.tap(find.widgetWithText(NavigationDestination, 'Tools'));
      await tester.pumpAndSettle();
      expect(find.text('Edit pages'), findsOneWidget);
      expect(find.text('Merge'), findsOneWidget);
      expect(find.text('Compress'), findsOneWidget);
      expect(find.text('Photos to PDF'), findsOneWidget);
      expect(find.text('Import PDF'), findsOneWidget);
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

  testWidgets('Desktop library renders folder navigation', (tester) async {
    late Database db;
    late Directory dir;
    await tester.runAsync(() async {
      db = await AppDatabase.open(inMemoryDatabasePath);
      dir = await Directory.systemTemp.createTemp('docapp_desktop_');
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
        await repo.folders();
      });
      await tester.pumpAndSettle();
      expect(find.text('All documents'), findsWidgets);
      expect(find.text('Unfiled'), findsOneWidget);
      expect(find.byTooltip('New folder'), findsOneWidget);
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

  testWidgets('Merge tool selects library PDFs before choosing merge mode',
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
        await source.writeAsBytes([37, 80, 68, 70, 45, 49, 46, 55]);
        await repo.addFile(source.path, title: title);
      }
    });

    try {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          settingsStoreProvider.overrideWithValue(SettingsStore(db)),
        ],
        child: MaterialApp(home: Scaffold(body: Builder(builder: (context) {
          return TextButton(
            onPressed: () =>
                tools.firstWhere((tool) => tool.name == 'Merge').run(context),
            child: const Text('Merge'),
          );
        }))),
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
