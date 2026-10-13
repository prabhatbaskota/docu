import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../documents/document_screen.dart';
import '../documents/providers.dart';
import '../editor_launch.dart';

/// Reads a PDF opened from Windows Explorer without copying it into the library.
class ExternalPdfScreen extends ConsumerWidget {
  const ExternalPdfScreen({super.key, required this.path});

  final String path;

  Future<void> _addToLibrary(BuildContext context, WidgetRef ref) async {
    try {
      final doc = await ref.read(repositoryProvider).addFile(
            path,
            title: p.basenameWithoutExtension(path),
            move: false,
          );
      if (!context.mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => DocumentScreen(id: doc.id),
      ));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add PDF: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exists = File(path).existsSync();
    return Scaffold(
      appBar: AppBar(
        title: Text(p.basename(path), overflow: TextOverflow.ellipsis),
        actions: exists
            ? [
                TextButton.icon(
                  onPressed: () => _addToLibrary(context, ref),
                  icon: const Icon(Icons.library_add_outlined),
                  label: const Text('Add to library'),
                ),
                IconButton(
                  tooltip: 'Edit pages',
                  onPressed: () => editExternalPdf(context, path),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ]
            : null,
      ),
      body: exists
          ? PdfViewer.file(path)
          : const Center(child: Text('PDF file not found')),
    );
  }
}
