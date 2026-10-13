import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/format.dart';
import '../core/pdf_engine.dart';
import '../core/pdf_helpers.dart';
import '../core/toast.dart';
import 'documents/actions.dart';
import 'documents/document.dart';
import 'page_editor.dart';

void _snack(BuildContext context, Object e) {
  if (!context.mounted) return;
  toast(context, friendlyError(e));
}

/// Open the page editor on a library document.
Future<void> editDocument(BuildContext context, Document doc) async {
  try {
    final path = repoOf(context).pathOf(doc);
    final refs = await refsForPdf(path);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PageEditor(
        original: doc,
        initial: refs,
        defaultName: '${doc.title} (edited)',
      ),
    ));
  } catch (e) {
    if (!context.mounted) return;
    _snack(context, e);
  }
}

/// Open the page editor on a PDF that is not in the library.
Future<void> editExternalPdf(BuildContext context, String path) async {
  try {
    final refs = await refsForPdf(path);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PageEditor(
        initial: refs,
        defaultName: '${p.basenameWithoutExtension(path)} (edited)',
      ),
    ));
  } catch (e) {
    if (!context.mounted) return;
    _snack(context, e);
  }
}

/// Merge = open the editor with all pages of all chosen PDFs.
Future<void> mergeIntoEditor(BuildContext context, List<String> pdfs,
    {bool compress = false}) async {
  try {
    final refs = <PageRef>[];
    for (final path in pdfs) {
      refs.addAll(await refsForPdf(path));
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PageEditor(
        initial: refs,
        defaultName: 'Merged ${stamp()}',
        compressByDefault: compress,
      ),
    ));
  } catch (e) {
    if (!context.mounted) return;
    _snack(context, e);
  }
}

/// Photos / scans = open the editor with one page per image.
Future<void> imagesIntoEditor(BuildContext context, List<String> images,
    {String? defaultName}) async {
  try {
    final tmp = await imagesToTempPdf(images);
    final refs = await refsForPdf(tmp);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PageEditor(
        initial: refs,
        defaultName: defaultName ?? 'Document ${stamp()}',
      ),
    ));
  } catch (e) {
    if (!context.mounted) return;
    _snack(context, e);
  }
}
