String _two(int n) => n.toString().padLeft(2, '0');

String stamp([DateTime? t]) {
  final d = t ?? DateTime.now();
  return '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}.${_two(d.minute)}';
}

String fmtDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

String fmtSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// User-typed title -> stored title (trimmed, no ".pdf" suffix, never empty).
String cleanTitle(String input) {
  var t = input.trim();
  if (t.toLowerCase().endsWith('.pdf')) t = t.substring(0, t.length - 4).trim();
  return t.isEmpty ? 'Document' : t;
}

/// Title -> safe file name (without extension) for sharing/exporting.
String safeFileName(String title) {
  final n = title.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  return n.isEmpty ? 'Document' : n;
}
