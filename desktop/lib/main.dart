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

Future<void> main(List<String> args) async {
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

  String? initialPdfPath;
  if (Platform.isWindows) {
    for (final arg in args) {
      if (arg.toLowerCase().endsWith('.pdf')) {
        initialPdfPath = arg;
        break;
      }
    }
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
