import 'package:docapp/features/documents/document.dart';
import 'package:docapp/features/documents/grouping.dart';
import 'package:flutter_test/flutter_test.dart';

Document _doc(String id, DateTime t) => Document(
      id: id,
      title: id,
      fileName: '$id.pdf',
      pageCount: 1,
      sizeBytes: 1,
      createdAt: t,
      updatedAt: t,
    );

void main() {
  final now = DateTime(2026, 10, 10, 15, 30);

  test('dayLabel: today, yesterday, older, other year', () {
    expect(dayLabel(DateTime(2026, 10, 10, 0, 1), now), 'Today');
    expect(dayLabel(DateTime(2026, 10, 9, 23, 59), now), 'Yesterday');
    expect(dayLabel(DateTime(2026, 10, 6), now), 'Tue, 6 Oct');
    expect(dayLabel(DateTime(2025, 12, 31), now), 'Wed, 31 Dec 2025');
  });

  test('dayLabel: yesterday survives a daylight-saving change', () {
    final spring = DateTime(2026, 3, 30, 0, 30);
    expect(dayLabel(DateTime(2026, 3, 29, 23, 0), spring), 'Yesterday');
  });

  test('groupByDay keeps order and merges same-day neighbours', () {
    final groups = groupByDay([
      _doc('a', DateTime(2026, 10, 10, 14)),
      _doc('b', DateTime(2026, 10, 10, 9)),
      _doc('c', DateTime(2026, 10, 9, 20)),
      _doc('d', DateTime(2026, 10, 1)),
    ], now);
    expect(groups.map((g) => g.label).toList(),
        ['Today', 'Yesterday', 'Thu, 1 Oct']);
    expect(groups.first.docs.map((d) => d.id).toList(), ['a', 'b']);
  });

  test('groupByDay on empty list', () {
    expect(groupByDay(const [], now), isEmpty);
  });
}
