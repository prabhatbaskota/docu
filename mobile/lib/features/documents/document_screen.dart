import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../editor_launch.dart';
import 'actions.dart';
import 'providers.dart';

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
