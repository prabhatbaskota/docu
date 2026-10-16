import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

const _maxSide = 2400;

/// Applies EXIF rotation, shrinks very large photos, and re-saves as a plain
/// JPEG, so pixel orientation is exactly what the crop screen shows.
/// Returns (path, width, height).
(String, int, int) _normalizeSync(String path) {
  final src = img.decodeImage(File(path).readAsBytesSync());
  if (src == null) throw const FormatException('Could not read the photo.');
  var im = img.bakeOrientation(src);
  if (im.width > _maxSide || im.height > _maxSide) {
    im = im.width >= im.height
        ? img.copyResize(im, width: _maxSide)
        : img.copyResize(im, height: _maxSide);
  }
  final out = '${path}_n.jpg';
  File(out).writeAsBytesSync(img.encodeJpg(im, quality: 90));
  return (out, im.width, im.height);
}

Future<(String, int, int)> normalizeImage(String path) =>
    compute(_normalizeSync, path);

typedef _CropArgs = (String, int, int, int, int);

String _cropSync(_CropArgs a) {
  final src = img.decodeImage(File(a.$1).readAsBytesSync());
  if (src == null) throw const FormatException('Could not read the photo.');
  final x = a.$2.clamp(0, src.width - 1);
  final y = a.$3.clamp(0, src.height - 1);
  final w = a.$4.clamp(1, src.width - x);
  final h = a.$5.clamp(1, src.height - y);
  final cropped = img.copyCrop(src, x: x, y: y, width: w, height: h);
  final out = '${a.$1}_c.jpg';
  File(out).writeAsBytesSync(img.encodeJpg(cropped, quality: 90));
  return out;
}

/// Crops [path] to [r] (pixel coordinates) in a background isolate.
Future<String> cropImageFile(String path, Rect r) => compute(
      _cropSync,
      (path, r.left.round(), r.top.round(), r.width.round(), r.height.round()),
    );

String _rotateSync(String path) {
  final src = img.decodeImage(File(path).readAsBytesSync());
  if (src == null) throw const FormatException('Could not read the photo.');
  final rotated = img.copyRotate(src, angle: 90);
  final out = '${path}_r.jpg';
  File(out).writeAsBytesSync(img.encodeJpg(rotated, quality: 90));
  return out;
}

/// Rotates 90 degrees clockwise in a background isolate.
Future<String> rotateImageFile(String path) => compute(_rotateSync, path);
