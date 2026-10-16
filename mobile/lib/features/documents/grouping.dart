import 'document.dart';

class DocGroup {
  final String label;
  final List<Document> docs;
  DocGroup(this.label, this.docs);
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

/// "Today", "Yesterday", then "Tue, 6 Oct" (plus the year when it differs).
String dayLabel(DateTime d, DateTime now) {
  // UTC midnights so daylight-saving changes never skew the day count.
  final today = DateTime.utc(now.year, now.month, now.day);
  final day = DateTime.utc(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  final base = '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
  return d.year == now.year ? base : '$base ${d.year}';
}

/// Groups an already-sorted list by modified day, keeping its order.
List<DocGroup> groupByDay(List<Document> docs, DateTime now) {
  final groups = <DocGroup>[];
  for (final d in docs) {
    final label = dayLabel(d.updatedAt, now);
    if (groups.isEmpty || groups.last.label != label) {
      groups.add(DocGroup(label, []));
    }
    groups.last.docs.add(d);
  }
  return groups;
}
