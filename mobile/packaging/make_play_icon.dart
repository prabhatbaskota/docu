import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final source = img.decodePng(File('assets/icon/icon.png').readAsBytesSync());
  if (source == null) throw StateError('Could not read app icon');
  final icon = img.copyResize(source,
      width: 512, height: 512, interpolation: img.Interpolation.average);
  final output = File('assets/store/icon_512.png');
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(img.encodePng(icon));
}
