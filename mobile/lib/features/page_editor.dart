import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../core/format.dart';
import '../core/pdf_engine.dart';
import '../core/pdf_helpers.dart';
import '../core/progress.dart';
import '../core/toast.dart';
import 'documents/actions.dart';
import 'documents/document.dart';
import 'documents/document_screen.dart';
import 'page_card.dart';
import 'page_picker_screen.dart';
import 'pickers.dart';
import 'scan_flow.dart';

class _Pg {
  final PageRef ref;
  final int id;
  _Pg(this.ref, this.id);
}

/// Page-level editor: big page thumbnails you can select, drag to reorder,
/// delete, extract, replace (scan / other PDF / photos) or add to.
/// Nothing is written until the user taps Save.
class PageEditor extends StatefulWidget {
  /// Set only when editing a library document (enables "Replace original").
  final Document? original;
  final List<PageRef> initial;
  final String? defaultName;

  /// "Compress and merge": the Save dialog opens with compression selected.
  final bool compressByDefault;

  const PageEditor({
    super.key,
    this.original,
    required this.initial,
    this.defaultName,
    this.compressByDefault = false,
  });

  @override
  State<PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends State<PageEditor> {
  final Map<String, PdfDocument> _docs = {};
  final List<_Pg> _pages = [];
  final Set<int> _sel = {};
  int _nextId = 0;
  bool _loading = true;
  bool _busy = false;
  bool _dirty = false;
  String? _error;
  final ScrollController _scroll = ScrollController();
  final Map<String, String> _labels = {}; // src path -> friendly name

  String get _baseName => widget.original?.title ?? 'Document';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _ensureDocs(widget.initial);
      if (!mounted) return;
      setState(() {
        _pages.addAll([for (final r in widget.initial) _Pg(r, _nextId++)]);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final d in _docs.values) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _ensureDocs(List<PageRef> refs) async {
    for (final s in {for (final r in refs) r.src}) {
      if (!_docs.containsKey(s)) {
        _docs[s] = await PdfDocument.openFile(s);
      }
    }
  }

  void _toast(String msg) {
    toast(context, msg);
  }

  // ---------- selection & ordering ----------

  void _toggle(int id) => setState(() {
        if (!_sel.remove(id)) _sel.add(id);
      });

  void _move(int from, int to) {
    if (from == to) return;
    setState(() {
      _pages.insert(to, _pages.removeAt(from));
      _dirty = true;
    });
  }

  void _nudge(int delta) {
    final i = _pages.indexWhere((pg) => _sel.contains(pg.id));
    final j = i + delta;
    if (i < 0 || j < 0 || j >= _pages.length) return;
    _move(i, j);
  }

  void _delete() => setState(() {
        _pages.removeWhere((pg) => _sel.contains(pg.id));
        _sel.clear();
        _dirty = true;
      });

  // ---------- adding / replacing ----------

  Future<void> _addPages({required bool replace}) async {
    final src = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                replace ? 'Replace page with...' : 'Add pages from...',
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Scan'),
              onTap: () => Navigator.pop(ctx, 'scan'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Another PDF'),
              subtitle: const Text('Pick the pages you want'),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Photos'),
              onTap: () => Navigator.pop(ctx, 'photos'),
            ),
          ],
        ),
      ),
    );
    if (src == null || !mounted) return;
    try {
      List<PageRef>? refs;
      switch (src) {
        case 'scan':
          refs = await _fromScan();
        case 'pdf':
          refs = await _fromPdf();
        case 'photos':
          refs = await _fromPhotos();
      }
      if (refs == null || refs.isEmpty || !mounted) return;
      _labels.putIfAbsent(
          refs.first.src,
          () => switch (src) {
                'scan' => 'Scan',
                'photos' => 'Photos',
                _ => p.basenameWithoutExtension(refs!.first.src),
              });
      await _ensureDocs(refs);
      if (!mounted) return;
      _insert(refs, replace: replace);
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    }
  }

  Future<List<PageRef>?> _fromScan() async {
    final imgs = await scanAndReview(context, confirmLabel: 'Add pages');
    if (imgs == null || imgs.isEmpty) return null;
    return refsForPdf(await imagesToTempPdf(imgs));
  }

  Future<List<PageRef>?> _fromPdf() async {
    final picked = await pickPdf(context);
    if (picked == null || !mounted) return null;
    final path = picked.path;
    final idx = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(builder: (_) => PagePickerScreen(path: path)),
    );
    if (idx == null) return null;
    return [for (final i in idx) PageRef(path, i)];
  }

  Future<List<PageRef>?> _fromPhotos() async {
    final imgs = await pickImages();
    if (imgs.isEmpty) return null;
    return refsForPdf(await imagesToTempPdf(imgs));
  }

  /// One page selected: replace it, or insert after it. Otherwise: append.
  void _insert(List<PageRef> refs, {required bool replace}) {
    final fresh = [for (final r in refs) _Pg(r, _nextId++)];
    setState(() {
      final selIdx = [
        for (var i = 0; i < _pages.length; i++)
          if (_sel.contains(_pages[i].id)) i
      ];
      var at = _pages.length;
      if (selIdx.length == 1) {
        at = selIdx.first;
        if (replace) {
          _pages.removeAt(at);
        } else {
          at += 1;
        }
      }
      _pages.insertAll(at, fresh);
      _sel.clear();
      _dirty = true;
    });
  }

  // ---------- saving ----------

  Future<({String name, bool replace, CompressQuality? quality})?> _askSave({
    required String initial,
    required bool canReplace,
    required String title,
    bool canCompress = true,
    int? beforeBytes,
    bool alreadyCompressed = false,
  }) {
    final c = TextEditingController(text: initial);
    var replace = false;
    CompressQuality? quality = (canCompress && widget.compressByDefault)
        ? CompressQuality.balanced
        : null;
    return showDialog<({String name, bool replace, CompressQuality? quality})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: c,
                  enabled: !replace,
                  decoration: const InputDecoration(labelText: 'File name'),
                ),
                if (canReplace)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: replace,
                    onChanged: (v) => set(() => replace = v ?? false),
                    title: const Text('Replace original'),
                  ),
                if (alreadyCompressed)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text(
                        'These files are already compressed. Saving keeps their current quality.'),
                  ),
                if (canCompress) ...[
                  const SizedBox(height: 16),
                  Text('Compression',
                      style: Theme.of(ctx).textTheme.labelLarge),
                  if (beforeBytes != null)
                    Text('Estimated original size: ${fmtSize(beforeBytes)}'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Off'),
                        selected: quality == null,
                        onSelected: (_) => set(() => quality = null),
                      ),
                      for (final q in CompressQuality.values)
                        ChoiceChip(
                          label: Text(q.label),
                          selected: quality == q,
                          onSelected: (_) => set(() => quality = q),
                        ),
                    ],
                  ),
                  if (quality != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${quality!.hint} Pages become images, so text can no longer be selected.',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    const Text(
                        'The actual compressed size will be shown after saving.'),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(
                  ctx, (name: c.text, replace: replace, quality: quality)),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// Rough "before" size: each page's share of its source file.
  int _estimateBytes(List<PageRef> refs) {
    final perPage = <String, double>{};
    var total = 0.0;
    for (final r in refs) {
      total += perPage.putIfAbsent(r.src, () {
        final n = _docs[r.src]?.pages.length ?? 1;
        return File(r.src).lengthSync() / (n == 0 ? 1 : n);
      });
    }
    return total.round();
  }

  Future<void> _save() async {
    try {
      await _saveWithOptions();
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    }
  }

  Future<void> _saveWithOptions() async {
    final orig = widget.original;
    final repo = repoOf(context);
    final documents = await repo.list(const DocQuery());
    if (!mounted) return;
    final compressedPaths = {
      for (final doc in documents)
        if (doc.compressed) repo.pathOf(doc)
    };
    final alreadyCompressed = _pages.isNotEmpty &&
        _pages.every((pg) => compressedPaths.contains(pg.ref.src));
    final r = await _askSave(
      title: 'Save',
      initial: widget.defaultName ?? 'Document ${stamp()}',
      canReplace: orig != null,
      canCompress: !alreadyCompressed,
      alreadyCompressed: alreadyCompressed,
      beforeBytes: _estimateBytes([for (final pg in _pages) pg.ref]),
    );
    if (r == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final refs = [for (final pg in _pages) pg.ref];
      final tmp = await tempPdfPath();
      if (!mounted) return;
      var message = 'Saved ${refs.length} page${refs.length == 1 ? '' : 's'}';
      final q = r.quality;
      if (q != null) {
        final before = _estimateBytes(refs);
        await runWithProgress<void>(
          context,
          'Compressing...',
          (report) => engine.compress(refs, tmp, q, onProgress: report),
        );
        final after = await File(tmp).length();
        message =
            '$message · Estimated original: ${fmtSize(before)} · Compressed: ${fmtSize(after)}';
      } else {
        await runWithProgress<void>(
          context,
          'Saving...',
          (report) => engine.assemble(refs, tmp),
        );
      }
      final String id;
      if (r.replace && orig != null) {
        id = (await repo.replaceFile(orig.id, tmp,
                compressed: q != null || alreadyCompressed))
            .id;
      } else {
        id = (await repo.addFile(tmp,
                title: r.name, compressed: q != null || alreadyCompressed))
            .id;
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final nav = Navigator.of(context);
      setState(() => _dirty = false);
      nav.pop();
      toastOn(
        messenger,
        message,
        actionLabel: 'Open',
        duration: const Duration(seconds: 5),
        onAction: () => nav.push(
            MaterialPageRoute<void>(builder: (_) => DocumentScreen(id: id))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(friendlyError(e));
    }
  }

  Future<void> _extract() async {
    final refs = [
      for (final pg in _pages)
        if (_sel.contains(pg.id)) pg.ref
    ];
    final r = await _askSave(
      title: 'Extract ${refs.length} page${refs.length == 1 ? '' : 's'}',
      initial: '$_baseName (pages)',
      canReplace: false,
      canCompress: false,
    );
    if (r == null || !mounted) return;
    setState(() => _busy = true);
    final repo = repoOf(context);
    try {
      final tmp = await tempPdfPath();
      await engine.assemble(refs, tmp);
      final documents = await repo.list(const DocQuery());
      final compressedPaths = {
        for (final doc in documents)
          if (doc.compressed) repo.pathOf(doc)
      };
      await repo.addFile(tmp,
          title: r.name,
          compressed: refs.isNotEmpty &&
              refs.every((ref) => compressedPaths.contains(ref.src)));
      if (!mounted) return;
      setState(() {
        _busy = false;
        _sel.clear();
      });
      _toast('Saved to Home');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(friendlyError(e));
    }
  }

  // ---------- UI ----------

  /// Called by the grid after a drop with a function that applies the move.
  void _onReorder(ReorderedListFunction reorderedListFunction) {
    final before = List<_Pg>.of(_pages);
    final updated =
        reorderedListFunction(List<_Pg>.of(_pages)).cast<_Pg>().toList();
    setState(() {
      _pages
        ..clear()
        ..addAll(updated);
      _dirty = true;
    });
    HapticFeedback.lightImpact();
    toast(
      context,
      'Page moved',
      actionLabel: 'Undo',
      duration: const Duration(seconds: 3),
      onAction: () {
        if (!mounted) return;
        setState(() {
          _pages
            ..clear()
            ..addAll(before);
        });
      },
    );
  }

  // ---------- source colors ----------

  static const _palette = [
    Color(0xFF3B82F6),
    Color(0xFFF59E0B),
    Color(0xFF10B981),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFF06B6D4),
  ];

  /// Sources in order of first appearance; colors only matter with 2+.
  List<String> get _sources {
    final seen = <String>[];
    for (final src in widget.initial.map((r) => r.src)) {
      if (!seen.contains(src)) seen.add(src);
    }
    for (final pg in _pages) {
      if (!seen.contains(pg.ref.src)) seen.add(pg.ref.src);
    }
    return seen;
  }

  bool get _multiSource => {for (final pg in _pages) pg.ref.src}.length >= 2;

  Color _colorOf(String src) =>
      _palette[_sources.indexOf(src).clamp(0, 1 << 20) % _palette.length];

  String _letterOf(String src) =>
      String.fromCharCode(65 + _sources.indexOf(src) % 26);

  String _labelOf(String src) => _labels[src] ?? 'File ${_letterOf(src)}';

  Widget _legend() {
    final srcs = [
      for (final s in _sources)
        if (_pages.any((pg) => pg.ref.src == s)) s
    ];
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final s in srcs) _sourceChip(s),
        ],
      ),
    );
  }

  Widget _sourceChip(String src) {
    final ids = [
      for (final pg in _pages)
        if (pg.ref.src == src) pg.id
    ];
    final selectedCount = ids.where(_sel.contains).length;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        showCheckmark: false,
        selected: selectedCount == ids.length,
        avatar: CircleAvatar(
          backgroundColor: _colorOf(src),
          child: Text(_letterOf(src),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ),
        label: Text(_sel.isEmpty
            ? '${_labelOf(src)} · ${ids.length} pages'
            : '${_labelOf(src)} · $selectedCount/${ids.length} selected for editing'),
        // Toggle this source without changing selections from other files.
        onSelected: _busy
            ? null
            : (selected) => setState(() {
                  if (selected) {
                    _sel.addAll(ids);
                  } else {
                    _sel.removeAll(ids);
                  }
                }),
      ),
    );
  }

  Widget _tile(int i) {
    final pg = _pages[i];
    final doc = _docs[pg.ref.src]!;
    final colored = _multiSource;
    return GestureDetector(
      key: ValueKey<String>(
          'page_${pg.id}'), // String key: the grid package reads keys as String
      onTap: () => _toggle(pg.id),
      child: PageCard(
        doc: doc,
        index: pg.ref.index,
        number: i + 1,
        selected: _sel.contains(pg.id),
        dimmed: _sel.isNotEmpty && !_sel.contains(pg.id),
        tint: colored ? _colorOf(pg.ref.src) : null,
        badge: colored ? _letterOf(pg.ref.src) : null,
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback? onTap) => InkWell(
        onTap: _busy ? null : onTap,
        child: SizedBox(
          width: 76,
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      );

  Widget _bar() {
    final one = _sel.length == 1;
    return Material(
      elevation: 8,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: _sel.isEmpty
              ? Row(children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _busy ? null : () => _addPages(replace: false),
                      icon: const Icon(Icons.add),
                      label: const Text('Add pages'),
                    ),
                  ),
                ])
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _action(Icons.delete_outline, 'Delete', _delete),
                    _action(Icons.file_download_outlined, 'Extract', _extract),
                    if (one) ...[
                      _action(Icons.swap_horiz, 'Replace',
                          () => _addPages(replace: true)),
                      _action(Icons.add, 'Insert after',
                          () => _addPages(replace: false)),
                      _action(Icons.arrow_back, 'Earlier', () => _nudge(-1)),
                      _action(Icons.arrow_forward, 'Later', () => _nudge(1)),
                    ],
                    _action(
                        Icons.deselect, 'Clear', () => setState(_sel.clear)),
                  ]),
                ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child:
              Padding(padding: const EdgeInsets.all(24), child: Text(_error!)));
    }
    final cols = (MediaQuery.of(context).size.width ~/ 170).clamp(2, 6);
    final selectedSources = {
      for (final pg in _pages)
        if (_sel.contains(pg.id)) pg.ref.src
    };
    final fileSummary = '${selectedSources.length} '
        '${selectedSources.length == 1 ? 'file' : 'files'} '
        '(${selectedSources.map(_letterOf).join(', ')})';
    return Column(
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_multiSource) _legend(),
        if (_multiSource)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  'All pages shown will be merged. Tap a file label to select pages for editing; tap again to deselect.'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _sel.isEmpty
                  ? '${_pages.length} pages  ·  Tap to select, hold and drag to reorder'
                  : '${_sel.length} of ${_pages.length} pages selected for editing'
                      '${_multiSource ? ' · $fileSummary' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        Expanded(
          child: _pages.isEmpty
              ? const Center(child: Text('No pages. Add some below.'))
              : ReorderableBuilder.builder(
                  scrollController: _scroll,
                  itemCount: _pages.length,
                  onReorder: _onReorder,
                  childBuilder: (itemBuilder) => GridView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.66,
                    ),
                    itemCount: _pages.length,
                    itemBuilder: (context, i) => itemBuilder(_tile(i), i),
                  ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.original != null ? _baseName : 'New PDF';
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Discard changes?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Keep editing')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Discard')),
            ],
          ),
        );
        if (discard == true && context.mounted) {
          setState(() => _dirty = false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title, overflow: TextOverflow.ellipsis),
          actions: [
            TextButton(
              onPressed: (_busy || _loading || _pages.isEmpty) ? null : _save,
              child: const Text('Save'),
            ),
          ],
        ),
        body: _body(),
        bottomNavigationBar: (_loading || _error != null) ? null : _bar(),
      ),
    );
  }
}
