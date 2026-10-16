import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../compress/compress_flow.dart';
import '../editor_launch.dart';
import 'actions.dart';
import 'document.dart';
import 'document_screen.dart';
import 'providers.dart';

/// Top bar shown while documents are selected: close + count (+ Select all).
AppBar selectionAppBar(WidgetRef ref, {List<Document> all = const []}) {
  final sel = ref.watch(selectionProvider);
  final notifier = ref.read(selectionProvider.notifier);
  return AppBar(
    leading: IconButton(
      icon: const Icon(Icons.close),
      tooltip: 'Cancel selection',
      onPressed: notifier.clear,
    ),
    title: Text('${sel.length} selected'),
    actions: [
      if (all.isNotEmpty)
        TextButton(
          onPressed: () => notifier.setAll([for (final d in all) d.id]),
          child: const Text('Select all'),
        ),
    ],
  );
}

/// Tap = open (or toggle while selecting). Long-press = start selecting.
void onDocTap(BuildContext context, WidgetRef ref, Document d) {
  final notifier = ref.read(selectionProvider.notifier);
  if (ref.read(selectionProvider).isNotEmpty) {
    notifier.toggle(d.id);
  } else {
    Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => DocumentScreen(id: d.id)));
  }
}

/// Bottom action bar for the current selection, with labeled actions.
/// [hostContext] must belong to a widget that stays mounted (the shell).
class SelectionBar extends ConsumerWidget {
  final BuildContext hostContext;
  const SelectionBar({super.key, required this.hostContext});

  Future<List<Document>> _docs(WidgetRef ref) async {
    final repo = ref.read(repositoryProvider);
    final out = <Document>[];
    for (final id in ref.read(selectionProvider)) {
      final d = await repo.get(id);
      if (d != null) out.add(d);
    }
    return out;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(selectionProvider);
    final one = ids.length == 1;
    final notifier = ref.read(selectionProvider.notifier);
    final repo = ref.read(repositoryProvider);
    final error = Theme.of(context).colorScheme.error;

    return Material(
      elevation: 8,
      child: SafeArea(
        child: Row(
          children: [
            if (!one)
              _Act(Icons.merge_type, 'Merge', () async {
                final docs = await _docs(ref);
                if (docs.length < 2 || !hostContext.mounted) return;
                final compress = await askMergeMode(hostContext);
                if (compress == null || !hostContext.mounted) return;
                final paths = [for (final d in docs) repo.pathOf(d)];
                notifier.clear();
                await mergeIntoEditor(hostContext, paths, compress: compress);
              }),
            _Act(Icons.ios_share, 'Share', () async {
              final docs = await _docs(ref);
              if (!hostContext.mounted) return;
              await shareDocuments(hostContext, docs);
            }),
            if (one)
              _Act(Icons.view_module_outlined, 'Edit pages', () async {
                final docs = await _docs(ref);
                if (docs.isEmpty || !hostContext.mounted) return;
                notifier.clear();
                await editDocument(hostContext, docs.first);
              }),
            _Act(Icons.star_border, 'Favorite', () async {
              final docs = await _docs(ref);
              final makeFav = !docs.every((d) => d.favorite);
              for (final d in docs) {
                await repo.setFavorite(d.id, makeFav);
              }
              notifier.clear();
            }),
            _Act(Icons.delete_outline, 'Delete', () async {
              final list = ids.toList();
              notifier.clear();
              if (hostContext.mounted) await deleteWithUndo(hostContext, list);
            }, color: error),
            if (one)
              _Act(Icons.more_horiz, 'More', () async {
                final docs = await _docs(ref);
                if (docs.isEmpty || !hostContext.mounted) return;
                await showDocumentMenu(hostContext, docs.first,
                    includeDelete: false);
                notifier.clear();
              }),
          ],
        ),
      ),
    );
  }
}

class _Act extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _Act(this.icon, this.label, this.onTap, {this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color),
                const SizedBox(height: 2),
                Text(label,
                    maxLines: 1,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: color)),
              ],
            ),
          ),
        ),
      );
}
