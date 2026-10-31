import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Run before opening scan screens so active captures cannot race cleanup.
Future<void> cleanOldScanImages({Directory? support, DateTime? now}) async {
  try {
    final root = support ?? await getApplicationSupportDirectory();
    final protected = <String>{};
    void collect(dynamic value) {
      if (value is String) {
        protected.add(p.normalize(p.absolute(value)));
      } else if (value is List) {
        value.forEach(collect);
      } else if (value is Map) {
        value.values.forEach(collect);
      }
    }

    for (final name in ['scan', 'card', 'card_side']) {
      for (final suffix in ['.json', '.json.new']) {
        final manifest = File(p.join(root.path, '${name}_draft$suffix'));
        if (await manifest.exists()) {
          // A damaged manifest might still describe recoverable photos.
          // Abort cleanup rather than guessing which photos are unreferenced.
          collect(jsonDecode(await manifest.readAsString()));
        }
      }
    }
    final pages = Directory(p.join(root.path, 'scan_pages'));
    if (!await pages.exists()) return;
    final cutoff = (now ?? DateTime.now()).subtract(const Duration(days: 7));
    await for (final entry in pages.list(followLinks: false)) {
      if (entry is! File ||
          p.extension(entry.path).toLowerCase() != '.jpg' ||
          protected.contains(p.normalize(p.absolute(entry.path)))) {
        continue;
      }
      try {
        if ((await entry.stat()).modified.isBefore(cutoff)) {
          await entry.delete();
        }
      } on FileSystemException {
        // A locked or removed working image must not prevent app startup.
      }
    }
  } on FileSystemException {
    // Cleanup is best effort; storage errors must not block the library.
  } on FormatException {
    // Preserve all photos when draft recovery data cannot be decoded.
  }
}
