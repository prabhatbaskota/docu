import 'dart:io';
import 'package:docapp/core/document_geometry.dart';
import 'package:docapp/core/pdf_engine.dart';
import 'package:docapp/features/scan/scan_draft.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('outline requires stable frames and expires after lost page', () {
    final tracker = EdgeTracker();
    tracker.update(pageMargin);
    tracker.update(pageMargin);
    expect(tracker.corners, isNull);
    tracker.update(pageMargin);
    expect(tracker.corners, pageMargin);
    tracker.update(null);
    tracker.update(null);
    tracker.update(null);
    expect(tracker.corners, isNull);
    tracker.update(pageMargin);
    expect(tracker.corners, isNull);
  });
  test(
      'batch survives process-style reload with ordering, edits, and page index',
      () async {
    final dir = await Directory.systemTemp.createTemp('docu_batch_');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => dir.path);
    try {
      final first = ScanPage('${dir.path}/one.jpg', pageMargin)
        ..corners = [
          const Offset(.1, .1),
          const Offset(.9, .12),
          const Offset(.95, .9),
          const Offset(.08, .94)
        ]
        ..corrected = 'corrected.jpg';
      final second = ScanPage('${dir.path}/two.jpg', null);
      await ScanDraft.save([first, second], index: 1);
      final restored = (await ScanDraft.load())!;
      expect(restored.$2, 1);
      expect(restored.$1.length, 2);
      expect(restored.$1.first.corners, first.corners);
      expect(restored.$1.first.corrected, 'corrected.jpg');
      expect(restored.$1.last.path, second.path);
      await ScanDraft.saveReview(['two.jpg', 'one.jpg']);
      final review = (await ScanDraft.load())!;
      expect(review.$3, isTrue);
      expect(review.$1.first.corrected, 'two.jpg');
      await ScanDraft.clear();
      expect(await ScanDraft.load(), isNull);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await dir.delete(recursive: true);
    }
  });
  test('merge rejects empty input before creating a corrupt PDF', () async {
    await expectLater(
        engine.assemble([], 'unused.pdf'), throwsA(isA<FormatException>()));
    expect(File('unused.pdf').existsSync(), isFalse);
  });
  test('internal errors are never shown as stack traces', () {
    expect(friendlyError(StateError('secret internal detail')),
        isNot(contains('secret')));
    expect(friendlyError(CompressionCancelled()), contains('cancelled'));
  });
}
