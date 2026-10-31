import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../mobile/lib/core/scan_cleanup.dart' as mobile;
import '../../desktop/lib/core/scan_cleanup.dart' as desktop;

void main() {
  for (final app in {
    'mobile': mobile.cleanOldScanImages,
    'desktop': desktop.cleanOldScanImages,
  }.entries) {
    test(
      '${app.key} cleanup preserves drafts, recent files and external images',
      () async {
        final root = await Directory.systemTemp.createTemp('docu_cleanup_');
        addTearDown(() => root.delete(recursive: true));
        final pages = await Directory('${root.path}/scan_pages').create();
        final now = DateTime.now();
        Future<File> image(String path, {bool old = true}) async {
          final file = await File(path).writeAsString('image');
          if (old)
            await file.setLastModified(now.subtract(const Duration(days: 10)));
          return file;
        }

        final orphan = await image('${pages.path}/orphan.jpg');
        final original = await image('${pages.path}/original.jpg');
        final corrected = await image('${pages.path}/corrected.jpg');
        final card = await image('${pages.path}/card.jpg');
        final pending = await image('${pages.path}/pending.jpg');
        final recent = await image('${pages.path}/recent.jpg', old: false);
        final external = await image('${root.path}/external.jpg');
        await File('${root.path}/scan_draft.json').writeAsString(
          jsonEncode({
            'pages': [
              {'path': original.path, 'corrected': corrected.path},
            ],
          }),
        );
        await File('${root.path}/card_draft.json').writeAsString(
          jsonEncode({
            'sides': [card.path, null],
          }),
        );
        await File('${root.path}/card_side_draft.json.new').writeAsString(
          jsonEncode({
            'pages': [
              {'path': pending.path},
            ],
          }),
        );
        await app.value(support: root, now: now);
        expect(await orphan.exists(), isFalse);
        for (final file in [
          original,
          corrected,
          card,
          pending,
          recent,
          external,
        ]) {
          expect(await file.exists(), isTrue, reason: file.path);
        }
      },
    );
    test('${app.key} corrupt draft prevents cleanup', () async {
      final root = await Directory.systemTemp.createTemp('docu_cleanup_');
      addTearDown(() => root.delete(recursive: true));
      final pages = await Directory('${root.path}/scan_pages').create();
      final file = await File(
        '${pages.path}/recoverable.jpg',
      ).writeAsString('image');
      await file.setLastModified(
        DateTime.now().subtract(const Duration(days: 10)),
      );
      await File('${root.path}/card_draft.json').writeAsString('{');
      await app.value(support: root);
      expect(await file.exists(), isTrue);
    });
  }
}
