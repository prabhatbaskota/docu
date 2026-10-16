import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../core/pdf_engine.dart';
import 'page_card.dart';

/// Shows every page of a PDF big; the user taps the ones to take.
/// Pops with the chosen 0-based page indexes (in page order).
class PagePickerScreen extends StatefulWidget {
  final String path;
  const PagePickerScreen({super.key, required this.path});

  @override
  State<PagePickerScreen> createState() => _PagePickerScreenState();
}

class _PagePickerScreenState extends State<PagePickerScreen> {
  PdfDocument? _doc;
  String? _error;
  final Set<int> _sel = {};

  @override
  void initState() {
    super.initState();
    PdfDocument.openFile(widget.path).then((d) {
      if (!mounted) {
        d.dispose();
        return;
      }
      setState(() {
        _doc = d;
        _sel.addAll([for (var i = 0; i < d.pages.length; i++) i]); // all on
      });
    }).catchError((Object e) {
      if (mounted) setState(() => _error = friendlyError(e));
    });
  }

  @override
  void dispose() {
    _doc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final cols = (MediaQuery.of(context).size.width ~/ 170).clamp(2, 6);
    return Scaffold(
      appBar: AppBar(
        title: Text(p.basenameWithoutExtension(widget.path),
            overflow: TextOverflow.ellipsis),
        actions: [
          if (doc != null)
            IconButton(
              tooltip: _sel.length == doc.pages.length
                  ? 'Clear selection'
                  : 'Select all',
              icon: Icon(_sel.length == doc.pages.length
                  ? Icons.deselect
                  : Icons.select_all),
              onPressed: () => setState(() {
                if (_sel.length == doc.pages.length) {
                  _sel.clear();
                } else {
                  _sel.addAll([for (var i = 0; i < doc.pages.length; i++) i]);
                }
              }),
            ),
          TextButton(
            onPressed: _sel.isEmpty
                ? null
                : () => Navigator.pop(context, _sel.toList()..sort()),
            child: Text(_sel.isEmpty ? 'Add' : 'Add (${_sel.length})'),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : doc == null
              ? const Center(child: CircularProgressIndicator())
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.66,
                  ),
                  itemCount: doc.pages.length,
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => setState(
                        () => _sel.contains(i) ? _sel.remove(i) : _sel.add(i)),
                    child: PageCard(
                      doc: doc,
                      index: i,
                      number: i + 1,
                      selected: _sel.contains(i),
                      dimmed: !_sel.contains(i),
                    ),
                  ),
                ),
    );
  }
}
