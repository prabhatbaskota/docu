import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/database.dart';
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
  pdfrxFlutterInitialize();
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
