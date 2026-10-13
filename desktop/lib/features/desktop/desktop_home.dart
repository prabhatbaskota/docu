import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/format.dart';
import '../compress/compress_flow.dart';
import '../documents/actions.dart';
import '../documents/document.dart';
import '../documents/document_repository.dart';
import '../documents/document_screen.dart';
import '../documents/providers.dart';
import '../editor_launch.dart';
import '../pickers.dart';
import 'external_pdf_screen.dart';

/// Desktop library. Folders are local library categories; PDFs remain in the
/// app's document store so renaming a folder cannot break file references.
class DesktopHome extends ConsumerStatefulWidget {
  const DesktopHome({super.key, this.initialPdfPath});

  final String? initialPdfPath;

  @override
  ConsumerState<DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends ConsumerState<DesktopHome> {
  String? _folderId;
  bool _unfiled = false;
  String _search = '';
  SortMode _sort = SortMode.recent;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    final path = widget.initialPdfPath;
    if (path != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ExternalPdfScreen(path: path),
        ));
      });
    }
  }

  Future<void> _newFolder() async {
    final name =
        await askText(context, title: 'New folder', label: 'Folder name');
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final folder = await ref.read(repositoryProvider).createFolder(name);
      setState(() {
        _folderId = folder.id;
        _unfiled = false;
      });
    } catch (_) {
      _message('A folder with that name already exists.');
    }
  }

  Future<void> _renameFolder(DocumentFolder folder) async {
    final name = await askText(context,
        title: 'Rename folder', initial: folder.name, label: 'Folder name');
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      await ref.read(repositoryProvider).renameFolder(folder.id, name);
    } catch (_) {
      _message('A folder with that name already exists.');
    }
  }

  Future<void> _deleteFolder(DocumentFolder folder) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${folder.name}?'),
        content: const Text('PDFs in this folder will move to Unfiled.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await ref.read(repositoryProvider).deleteFolder(folder.id);
    setState(() {
      if (_folderId == folder.id) {
        _folderId = null;
        _unfiled = true;
      }
    });
  }

  Future<void> _move(List<String> ids, List<DocumentFolder> folders) async {
    if (ids.isEmpty) return;
    final target = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Move to folder'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ''),
            child: const ListTile(
                leading: Icon(Icons.folder_off_outlined),
                title: Text('Unfiled')),
          ),
          for (final folder in folders)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, folder.id),
              child: ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(folder.name)),
            ),
        ],
      ),
    );
    if (target == null || !mounted) return;
    await ref
        .read(repositoryProvider)
        .moveToFolder(ids, target.isEmpty ? null : target);
    setState(_selected.clear);
  }

  Future<void> _export(Document doc) async {
    await exportDocument(context, doc);
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> _docAction(
      String action, Document doc, List<DocumentFolder> folders) async {
    switch (action) {
      case 'move':
        await _move([doc.id], folders);
        return;
      case 'export':
        await _export(doc);
        return;
      case 'rename':
        if (mounted) await renameDocument(context, doc);
        return;
      case 'edit':
        if (mounted) await editDocument(context, doc);
        return;
    }
  }

  Future<void> _mergeSelected(List<Document> documents) async {
    final ids = _selected.toSet();
    final chosen = documents.where((doc) => ids.contains(doc.id)).toList();
    if (chosen.length < 2) return;
    final compress = await askMergeMode(context);
    if (compress == null || !mounted) return;
    final repo = ref.read(repositoryProvider);
    setState(_selected.clear);
    await mergeIntoEditor(context, [for (final doc in chosen) repo.pathOf(doc)],
        compress: compress);
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    setState(_selected.clear);
    await deleteWithUndo(context, ids);
  }

  void _navigate(String? folderId, {bool unfiled = false}) {
    setState(() {
      _folderId = folderId;
      _unfiled = unfiled;
      _selected.clear();
    });
  }

  List<Document> _visible(List<Document> docs) {
    final needle = _search.trim().toLowerCase();
    final result = docs.where((d) {
      if (_folderId != null && d.folderId != _folderId) return false;
      if (_unfiled && d.folderId != null) return false;
      return needle.isEmpty || d.title.toLowerCase().contains(needle);
    }).toList();
    result.sort((a, b) => switch (_sort) {
          SortMode.recent => b.updatedAt.compareTo(a.updatedAt),
          SortMode.name =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          SortMode.size => b.sizeBytes.compareTo(a.sizeBytes),
        });
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(documentsProvider);
    final foldersAsync = ref.watch(_foldersProvider);
    final all = docsAsync.value ?? const <Document>[];
    final folders = foldersAsync.value ?? const <DocumentFolder>[];
    final docs = _visible(all);
    final title = _folderId == null
        ? (_unfiled ? 'Unfiled' : 'All documents')
        : folders
                .where((f) => f.id == _folderId)
                .map((f) => f.name)
                .firstOrNull ??
            'Folder';

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 250,
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 26, 16, 24),
                    child: Text('docu',
                        style: TextStyle(
                            fontSize: 28, fontWeight: FontWeight.bold)),
                  ),
                  _sideItem(Icons.description_outlined, 'All documents',
                      _folderId == null && !_unfiled, () => _navigate(null)),
                  _sideItem(Icons.folder_off_outlined, 'Unfiled', _unfiled,
                      () => _navigate(null, unfiled: true)),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                    child: Row(children: [
                      const Expanded(
                          child: Text('FOLDERS',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      IconButton(
                          tooltip: 'New folder',
                          onPressed: _newFolder,
                          icon: const Icon(Icons.create_new_folder_outlined)),
                    ]),
                  ),
                  Expanded(
                    child: ListView(children: [
                      for (final folder in folders)
                        ListTile(
                          dense: true,
                          selected: _folderId == folder.id,
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(folder.name,
                              overflow: TextOverflow.ellipsis),
                          onTap: () => _navigate(folder.id),
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Folder options',
                            onSelected: (value) => value == 'rename'
                                ? _renameFolder(folder)
                                : _deleteFolder(folder),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                  value: 'rename', child: Text('Rename')),
                              PopupMenuItem(
                                  value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ),
                    ]),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Stored locally on this computer',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                        width: 220,
                        child: Text(title,
                            style: Theme.of(context).textTheme.headlineSmall)),
                    SizedBox(
                      width: 280,
                      child: SearchBar(
                        hintText: 'Search PDFs',
                        leading: const Icon(Icons.search),
                        onChanged: (value) => setState(() => _search = value),
                      ),
                    ),
                    DropdownButton<SortMode>(
                      value: _sort,
                      onChanged: (value) =>
                          setState(() => _sort = value ?? _sort),
                      items: [
                        for (final mode in SortMode.values)
                          DropdownMenuItem(
                              value: mode, child: Text('Sort: ${mode.label}'))
                      ],
                    ),
                    FilledButton.icon(
                      onPressed: () => importPdfs(context, folderId: _folderId),
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('Import PDFs'),
                    ),
                    OutlinedButton.icon(
                        onPressed: _newFolder,
                        icon: const Icon(Icons.create_new_folder_outlined),
                        label: const Text('New folder')),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await pickPdf(context);
                      if (picked == null || !mounted) return;
                      if (picked.doc != null) {
                        await editDocument(this.context, picked.doc!);
                      } else {
                        await editExternalPdf(this.context, picked.path);
                      }
                    },
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Edit pages'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final paths = await pickPdfsForMerge(context);
                      if (paths == null || !mounted) return;
                      final compress = await askMergeMode(this.context);
                      if (compress == null || !mounted) return;
                      await mergeIntoEditor(this.context, paths,
                          compress: compress);
                    },
                    icon: const Icon(Icons.merge_type),
                    label: const Text('Merge'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await pickPdf(context);
                      if (picked == null || !mounted) return;
                      await compressPdfFile(this.context,
                          path: picked.path,
                          title: picked.doc?.title ??
                              p.basenameWithoutExtension(picked.path));
                    },
                    icon: const Icon(Icons.compress),
                    label: const Text('Compress'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final images = await pickImages();
                      if (images.isNotEmpty && mounted) {
                        await imagesIntoEditor(this.context, images,
                            defaultName: 'Photos ${stamp()}');
                      }
                    },
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Images to PDF'),
                  ),
                ]),
              ),
              if (_selected.isNotEmpty)
                Material(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Row(children: [
                      Text('${_selected.length} selected'),
                      const SizedBox(width: 12),
                      TextButton.icon(
                          onPressed: () => _move(_selected.toList(), folders),
                          icon: const Icon(Icons.drive_file_move_outline),
                          label: const Text('Move')),
                      if (_selected.length > 1)
                        TextButton.icon(
                            onPressed: () => _mergeSelected(all),
                            icon: const Icon(Icons.merge_type),
                            label: const Text('Merge')),
                      TextButton.icon(
                          onPressed: _deleteSelected,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete')),
                      TextButton(
                          onPressed: () => setState(_selected.clear),
                          child: const Text('Clear')),
                    ]),
                  ),
                ),
              Expanded(
                child: docsAsync.isLoading || foldersAsync.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : docsAsync.hasError || foldersAsync.hasError
                        ? Center(
                            child: Text(
                                '${docsAsync.error ?? foldersAsync.error}'))
                        : docs.isEmpty
                            ? Center(
                                child: Text(_search.isNotEmpty
                                    ? 'No matching PDFs'
                                    : 'No PDFs here. Import files or move them into this folder.'))
                            : ListView.builder(
                                itemCount: docs.length,
                                itemBuilder: (context, index) {
                                  final doc = docs[index];
                                  return ListTile(
                                    selected: _selected.contains(doc.id),
                                    leading: Checkbox(
                                      value: _selected.contains(doc.id),
                                      onChanged: (_) => setState(() {
                                        if (!_selected.add(doc.id)) {
                                          _selected.remove(doc.id);
                                        }
                                      }),
                                    ),
                                    title: Text(doc.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    subtitle: Text(
                                        '${doc.pageCount} pages · ${fmtSize(doc.sizeBytes)}'),
                                    onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                            builder: (_) =>
                                                DocumentScreen(id: doc.id))),
                                    trailing: PopupMenuButton<String>(
                                      tooltip: 'Document options',
                                      onSelected: (action) =>
                                          _docAction(action, doc, folders),
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                            value: 'edit',
                                            child: Text('Edit pages')),
                                        PopupMenuItem(
                                            value: 'move',
                                            child: Text('Move to folder')),
                                        PopupMenuItem(
                                            value: 'rename',
                                            child: Text('Rename')),
                                        PopupMenuItem(
                                            value: 'export',
                                            child: Text('Export PDF')),
                                      ],
                                    ),
                                  );
                                },
                              ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _sideItem(
          IconData icon, String title, bool selected, VoidCallback onTap) =>
      ListTile(
          leading: Icon(icon),
          title: Text(title),
          selected: selected,
          onTap: onTap);
}

final _foldersProvider = StreamProvider<List<DocumentFolder>>((ref) async* {
  final repo = ref.watch(repositoryProvider);
  yield await repo.folders();
  await for (final _ in repo.changes) {
    yield await repo.folders();
  }
});
