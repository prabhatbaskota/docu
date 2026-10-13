import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../branding/docu_logo.dart';
import '../settings/settings_page.dart';
import '../tools_page.dart';
import 'actions.dart';
import 'document.dart';
import 'document_card.dart';
import 'grouping.dart';
import 'providers.dart';
import 'selection_bar.dart';

/// Everything, newest first, grouped Today / Yesterday / by date.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  static const _collapsedCount = 10;
  static const _shortcutNames = ['Edit pages', 'Merge', 'Compress', 'Photos to PDF'];

  bool _expanded = false;
  bool _searching = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _closeSearch() {
    _search.clear();
    ref.read(queryProvider.notifier).setText('');
    setState(() => _searching = false);
  }

  /// Headers (String), documents, and a trailing "Show all" (int = hidden).
  List<Object> _items(List<Document> docs, DocQuery q) {
    final collapsed = !_expanded && docs.length > _collapsedCount;
    final shown = collapsed ? docs.take(_collapsedCount).toList() : docs;
    final out = <Object>[];
    if (q.sort == SortMode.recent) {
      for (final g in groupByDay(shown, DateTime.now())) {
        out.add(g.label);
        out.addAll(g.docs);
      }
    } else {
      out.addAll(shown);
    }
    if (collapsed) out.add(docs.length - _collapsedCount);
    return out;
  }

  Widget _shortcuts(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = [
      for (final n in _shortcutNames) tools.firstWhere((t) => t.name == n)
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          for (final t in items)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Material(
                  color: cs.secondaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => t.run(this.context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        children: [
                          Icon(t.icon, color: cs.onSecondaryContainer),
                          const SizedBox(height: 6),
                          Text(
                            t.name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: cs.onSecondaryContainer),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _empty(DocQuery q) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
        child: Column(
          children: [
            const DocuLogo(size: 72),
            const SizedBox(height: 16),
            Text(
              q.isFiltered ? 'No matching documents' : 'Nothing here yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              q.isFiltered
                  ? 'Try a different search'
                  : 'Tap the scan button to create your first document',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );

  AppBar _normalBar(DocQuery q) => AppBar(
        title: const DocuTitle(),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () => setState(() => _searching = true),
          ),
          PopupMenuButton<SortMode>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            onSelected: ref.read(queryProvider.notifier).setSort,
            itemBuilder: (_) => [
              for (final s in SortMode.values)
                CheckedPopupMenuItem<SortMode>(
                  value: s,
                  checked: q.sort == s,
                  child: Text(s.label),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.file_open_outlined),
            tooltip: 'Import PDF',
            onPressed: () => importPdfs(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      );

  AppBar _searchBar() => AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Close search',
          onPressed: _closeSearch,
        ),
        title: TextField(
          controller: _search,
          autofocus: true,
          onChanged: ref.read(queryProvider.notifier).setText,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search documents',
            border: InputBorder.none,
            filled: false,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(queryProvider);
    final async = ref.watch(documentsProvider);
    final sel = ref.watch(selectionProvider);
    final repo = ref.watch(repositoryProvider);
    final notifier = ref.read(selectionProvider.notifier);
    final selecting = sel.isNotEmpty;
    final docs = async.value ?? const <Document>[];

    return PopScope(
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: Scaffold(
        appBar: selecting
            ? selectionAppBar(ref, all: docs)
            : (_searching ? _searchBar() : _normalBar(q)),
        body: async.when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (list) {
            final items = _items(list, q);
            final header = _searching ? 0 : 1; // shortcuts row
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 110),
              itemCount: header + (items.isEmpty ? 1 : items.length),
              itemBuilder: (context, i) {
                if (header == 1 && i == 0) return _shortcuts(context);
                if (items.isEmpty) return _empty(q);
                final item = items[i - header];
                if (item is String) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: Text(item,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant)),
                  );
                }
                if (item is int) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: TextButton(
                      onPressed: () => setState(() => _expanded = true),
                      child: Text('Show all (${list.length})'),
                    ),
                  );
                }
                final d = item as Document;
                return DocumentRow(
                  doc: d,
                  path: repo.pathOf(d),
                  selected: sel.contains(d.id),
                  selecting: selecting,
                  onTap: () => onDocTap(context, ref, d),
                  onLongPress: () => notifier.add(d.id),
                  onFavorite: () => repo.setFavorite(d.id, !d.favorite),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
