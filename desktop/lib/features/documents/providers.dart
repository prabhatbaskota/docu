import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database.dart';
import 'document.dart';
import 'document_repository.dart';

// Overridden in main() once the database is open.
final repositoryProvider = Provider<DocumentRepository>(
    (ref) => throw UnimplementedError('repositoryProvider not overridden'));
final settingsStoreProvider = Provider<SettingsStore>(
    (ref) => throw UnimplementedError('settingsStoreProvider not overridden'));
final initialThemeProvider = Provider<ThemeMode>((ref) => ThemeMode.system);

class QueryNotifier extends Notifier<DocQuery> {
  @override
  DocQuery build() => const DocQuery();

  void setText(String t) => state = state.copyWith(text: t);
  void setFavoritesOnly(bool v) => state = state.copyWith(favoritesOnly: v);
  void setSort(SortMode s) => state = state.copyWith(sort: s);
}

final queryProvider =
    NotifierProvider<QueryNotifier, DocQuery>(QueryNotifier.new);

/// The home list: re-queries when the filter changes or the library changes.
final documentsProvider = StreamProvider<List<Document>>((ref) async* {
  final repo = ref.watch(repositoryProvider);
  final q = ref.watch(queryProvider);
  yield await repo.list(q);
  await for (final _ in repo.changes) {
    yield await repo.list(q);
  }
});

final recentFilesProvider = StreamProvider<List<RecentPdf>>((ref) async* {
  final repo = ref.watch(repositoryProvider);
  yield await repo.recentFiles();
  await for (final _ in repo.changes) {
    yield await repo.recentFiles();
  }
});

final documentProvider =
    StreamProvider.family<Document?, String>((ref, id) async* {
  final repo = ref.watch(repositoryProvider);
  yield await repo.get(id);
  await for (final _ in repo.changes) {
    yield await repo.get(id);
  }
});

class ThemeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.read(initialThemeProvider);

  void setMode(ThemeMode m) {
    state = m;
    ref.read(settingsStoreProvider).set('theme', m.name);
  }
}

final themeProvider =
    NotifierProvider<ThemeNotifier, ThemeMode>(ThemeNotifier.new);

/// Selected document ids, in the order they were tapped. Shared by Home,
/// Favorites and the bottom action bar.
class SelectionNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  void toggle(String id) {
    final s = {...state};
    if (!s.remove(id)) s.add(id);
    state = s;
  }

  void add(String id) => state = {...state, id};
  void setAll(Iterable<String> ids) => state = {...ids};
  void clear() => state = <String>{};
}

final selectionProvider =
    NotifierProvider<SelectionNotifier, Set<String>>(SelectionNotifier.new);

/// Starred documents for the Favorites tab.
final favoritesProvider = StreamProvider<List<Document>>((ref) async* {
  final repo = ref.watch(repositoryProvider);
  const q = DocQuery(favoritesOnly: true);
  yield await repo.list(q);
  await for (final _ in repo.changes) {
    yield await repo.list(q);
  }
});
