import 'package:docapp/core/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fmtSize', () {
    expect(fmtSize(500), '500 B');
    expect(fmtSize(2048), '2 KB');
    expect(fmtSize(5 * 1024 * 1024), '5.0 MB');
  });

  test('cleanTitle trims, strips .pdf and never returns empty', () {
    expect(cleanTitle('  Report.PDF '), 'Report');
    expect(cleanTitle('   '), 'Document');
    expect(cleanTitle('.pdf'), 'Document');
  });

  test('safeFileName removes characters that are invalid in file names', () {
    expect(safeFileName('a/b:c*d'), 'a_b_c_d');
    expect(safeFileName(' '), 'Document');
  });
}
