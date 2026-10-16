import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'document.dart';
import 'document_card.dart';
import 'providers.dart';
import 'selection_bar.dart';

/// Starred documents, newest first.
class FavoritesPage extends ConsumerWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(favoritesProvider);
    final sel = ref.watch(selectionProvider);
    final repo = ref.watch(repositoryProvider);
    final notifier = ref.read(selectionProvider.notifier);
    final selecting = sel.isNotEmpty;
    final docs = async.value ?? const <Document>[];
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: selecting
          ? selectionAppBar(ref, all: docs)
          : AppBar(title: const Text('Favorites')),
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_border_rounded, size: 64, color: cs.outline),
                    const SizedBox(height: 12),
                    Text('No favorites yet',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Tap the star on a document to find it here',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 110),
            itemCount: list.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (_, i) {
              final d = list[i];
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
    );
  }
}
