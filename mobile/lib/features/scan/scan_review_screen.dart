import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';

import '../../core/image_tools.dart';
import '../../core/pdf_engine.dart' show friendlyError;
import '../../core/toast.dart';
import '../camera_scan_screen.dart';
import '../crop_screen.dart';

class _Img {
  final int id;
  String path;
  _Img(this.id, this.path);
}

/// The whole scanned batch at a glance. Fix pages (crop, rotate), delete,
/// reorder by dragging, add more, then confirm.
/// Pops with the final list of image paths, or null when cancelled.
class ScanReviewScreen extends StatefulWidget {
  final List<String> initial;
  final String confirmLabel; // e.g. "Save PDF" or "Add pages"
  const ScanReviewScreen(
      {super.key, required this.initial, required this.confirmLabel});

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  final List<_Img> _imgs = [];
  final Set<int> _sel = {};
  final ScrollController _scroll = ScrollController();
  int _nextId = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _imgs.addAll([for (final p in widget.initial) _Img(_nextId++, p)]);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toggle(int id) => setState(() {
        if (!_sel.remove(id)) _sel.add(id);
      });

  void _delete() => setState(() {
        _imgs.removeWhere((i) => _sel.contains(i.id));
        _sel.clear();
      });

  Future<void> _rotate() async {
    setState(() => _busy = true);
    try {
      for (final im in _imgs.where((i) => _sel.contains(i.id))) {
        final out = await rotateImageFile(im.path);
        im.path = out;
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _crop() async {
    final im = _imgs.firstWhere((i) => _sel.contains(i.id));
    try {
      final decoded = await decodeImageFromList(await File(im.path).readAsBytes());
      final w = decoded.width, h = decoded.height;
      decoded.dispose();
      if (!mounted) return;
      final rect = await Navigator.of(context).push<Rect>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => CropScreen(path: im.path, imgW: w, imgH: h),
        ),
      );
      if (rect == null || !mounted) return;
      final full = rect.width >= w - 2 && rect.height >= h - 2;
      if (full) return;
      setState(() => _busy = true);
      final out = await cropImageFile(im.path, rect);
      if (!mounted) return;
      setState(() {
        im.path = out;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, friendlyError(e));
    }
  }

  Future<void> _addMore() async {
    final more = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CameraScanScreen(multiple: true, startAt: _imgs.length),
      ),
    );
    if (more == null || more.isEmpty || !mounted) return;
    setState(() {
      _imgs.addAll([for (final p in more) _Img(_nextId++, p)]);
    });
  }

  void _onReorder(ReorderedListFunction reorderedListFunction) {
    final updated =
        reorderedListFunction(List<_Img>.of(_imgs)).cast<_Img>().toList();
    setState(() {
      _imgs
        ..clear()
        ..addAll(updated);
    });
    HapticFeedback.lightImpact();
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Discard ${_imgs.length} page${_imgs.length == 1 ? '' : 's'}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard')),
        ],
      ),
    );
    return ok == true;
  }

  Widget _tile(int i) {
    final im = _imgs[i];
    final cs = Theme.of(context).colorScheme;
    final selected = _sel.contains(im.id);
    return GestureDetector(
      key: ValueKey<String>('img_${im.id}'),
      onTap: () => _toggle(im.id),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? cs.primary : cs.outlineVariant,
                  width: selected ? 3 : 1,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(im.path),
                      fit: BoxFit.contain, cacheWidth: 500),
                  if (selected)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Icon(Icons.check_circle, color: cs.primary),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('${i + 1}', style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap,
          {Color? color}) =>
      Expanded(
        child: InkWell(
          onTap: _busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(fontSize: 11, color: color)),
              ],
            ),
          ),
        ),
      );

  Widget _bar() {
    final one = _sel.length == 1;
    final error = Theme.of(context).colorScheme.error;
    return Material(
      elevation: 8,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: _sel.isEmpty
              ? Row(children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _addMore,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Add page'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: (_busy || _imgs.isEmpty)
                          ? null
                          : () => Navigator.pop(
                              context, [for (final i in _imgs) i.path]),
                      child: Text(widget.confirmLabel),
                    ),
                  ),
                ])
              : Row(children: [
                  if (one) _action(Icons.crop, 'Crop', _crop),
                  _action(Icons.rotate_right, 'Rotate', _rotate),
                  _action(Icons.delete_outline, 'Delete', _delete,
                      color: error),
                  _action(Icons.deselect, 'Clear',
                      () => setState(_sel.clear)),
                ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cols = (MediaQuery.of(context).size.width ~/ 170).clamp(2, 6);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_imgs.isEmpty || await _confirmDiscard()) {
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_sel.isEmpty
              ? '${_imgs.length} page${_imgs.length == 1 ? '' : 's'}'
              : '${_sel.length} selected'),
        ),
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Tap a page to fix it. Hold and drag to reorder.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            Expanded(
              child: _imgs.isEmpty
                  ? const Center(child: Text('No pages left. Add a page below.'))
                  : ReorderableBuilder.builder(
                      scrollController: _scroll,
                      itemCount: _imgs.length,
                      onReorder: _onReorder,
                      childBuilder: (itemBuilder) => GridView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.7,
                        ),
                        itemCount: _imgs.length,
                        itemBuilder: (context, i) => itemBuilder(_tile(i), i),
                      ),
                    ),
            ),
          ],
        ),
        bottomNavigationBar: _bar(),
      ),
    );
  }
}
