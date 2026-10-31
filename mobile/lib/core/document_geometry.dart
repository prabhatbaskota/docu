import 'dart:ui';

/// Clockwise, normalized coordinates: top left, top right, bottom right, bottom left.
const pageMargin = <Offset>[
  Offset(.03, .03),
  Offset(.97, .03),
  Offset(.97, .97),
  Offset(.03, .97),
];

/// Suppress one-frame detections and expire stale outlines.
class EdgeTracker {
  List<Offset>? _candidate;
  List<Offset>? corners;
  int _hits = 0;
  int _misses = 0;
  void update(List<Offset>? next) {
    if (next == null) {
      if (++_misses >= 3) {
        corners = null;
        _candidate = null;
        _hits = 0;
      }
      return;
    }
    _misses = 0;
    final previous = _candidate;
    final stable = previous != null &&
        List.generate(4, (i) => (previous[i] - next[i]).distance)
            .every((d) => d < .07);
    _hits = stable ? _hits + 1 : 1;
    _candidate = next;
    if (!stable) corners = null;
    if (_hits >= 3) {
      final old = corners;
      corners = old == null
          ? next
          : [for (var i = 0; i < 4; i++) Offset.lerp(old[i], next[i], .3)!];
    }
  }
}

