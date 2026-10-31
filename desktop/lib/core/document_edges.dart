import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
export 'document_geometry.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

List<Offset>? detectLuma((Uint8List, int, int) frame) {
  final gray =
      cv.Mat.fromList(frame.$3, frame.$2, cv.MatType.CV_8UC1, frame.$1);
  final blur = cv.gaussianBlur(gray, (5, 5), 0);
  final edges = cv.canny(blur, 50, 150);
  final (contours, hierarchy) =
      cv.findContours(edges, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
  try {
    List<Offset>? best;
    var area = frame.$2 * frame.$3 * .12;
    for (final contour in contours) {
      final a = cv.contourArea(contour).abs();
      if (a <= area) continue;
      final polygon =
          cv.approxPolyDP(contour, cv.arcLength(contour, true) * .02, true);
      try {
        if (polygon.length != 4 || !cv.isContourConvex(polygon)) continue;
        final points = [
          for (final p in polygon) Offset(p.x / frame.$2, p.y / frame.$3)
        ];
        // Angular ordering avoids duplicate corners on diamond-shaped pages.
        final center = points.reduce((a, b) => a + b) / 4;
        points.sort((a, b) => math
            .atan2(a.dy - center.dy, a.dx - center.dx)
            .compareTo(math.atan2(b.dy - center.dy, b.dx - center.dx)));
        var first = 0;
        for (var i = 1; i < 4; i++) {
          if (points[i].dx + points[i].dy < points[first].dx + points[first].dy) {
            first = i;
          }
        }
        best = [for (var i = 0; i < 4; i++) points[(first + i) % 4]];
        area = a;
      } finally {
        polygon.dispose();
      }
    }
    return best;
  } finally {
    contours.dispose();
    hierarchy.dispose();
    edges.dispose();
    blur.dispose();
    gray.dispose();
  }
}

String _warp((String, List<Offset>) args) {
  final source = cv.imread(args.$1);
  final p = args.$2
      .map((v) => Offset(v.dx * source.cols, v.dy * source.rows))
      .toList();
  final width=math.max((p[1]-p[0]).distance,(p[2]-p[3]).distance);
  final height=math.max((p[3]-p[0]).distance,(p[2]-p[1]).distance);
  final scale=math.min(1.0,3000/math.max(width,height));
  final w=(width*scale).round().clamp(2,3000);
  final h=(height*scale).round().clamp(2,3000);
  final from = cv.VecPoint.fromList(
      [for (final v in p) cv.Point(v.dx.round(), v.dy.round())]);
  final to = cv.VecPoint.fromList([
    cv.Point(0, 0),
    cv.Point(w - 1, 0),
    cv.Point(w - 1, h - 1),
    cv.Point(0, h - 1)
  ]);
  final transform = cv.getPerspectiveTransform(from, to);
  final result = cv.warpPerspective(source, transform, (w, h));
  try {
    final path = '${args.$1}_${DateTime.now().microsecondsSinceEpoch}_flat.jpg';
    if (!cv.imwrite(path, result)) {
      throw const FileSystemException('Could not save corrected page.');
    }
    return path;
  } finally {
    result.dispose();
    transform.dispose();
    from.dispose();
    to.dispose();
    source.dispose();
  }
}

Future<String> flattenPage(String path, List<Offset> corners) =>
    compute(_warp, (path, corners));

(String,int,int) _normalizePhoto(String path) {
  final image=cv.imread(path);
  try {
    final output='${path}_normalized.jpg';
    if(!cv.imwrite(output,image))throw const FileSystemException('Could not prepare photo.');
    return (output,image.cols,image.rows);
  }finally{image.dispose();}
}
Future<(String,int,int)> normalizeScanPhoto(String path)=>compute(_normalizePhoto,path);

List<Offset>? _detectPhoto(String path) {
  final source = cv.imread(path, flags: cv.IMREAD_GRAYSCALE);
  final small =
      cv.resize(source, (480, (480 * source.rows / source.cols).round()));
  try {
    return detectLuma((Uint8List.fromList(small.data), small.cols, small.rows));
  } finally {
    small.dispose();
    source.dispose();
  }
}

Future<List<Offset>?> detectPhoto(String path) => compute(_detectPhoto, path);
