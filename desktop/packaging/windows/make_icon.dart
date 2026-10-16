import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Builds the Windows icon from the same source artwork as the mobile icon.
void main() {
  final source = img.decodePng(File('assets/icon/icon.png').readAsBytesSync());
  if (source == null) throw StateError('Could not read app icon');
  const sizes = [16, 24, 32, 48, 64, 128, 256];
  final images = [
    for (final size in sizes)
      Uint8List.fromList(img.encodePng(img.copyResize(source,
          width: size,
          height: size,
          interpolation: img.Interpolation.average))),
  ];
  final headerSize = 6 + sizes.length * 16;
  final total =
      headerSize + images.fold<int>(0, (n, bytes) => n + bytes.length);
  final data = ByteData(total);
  data.setUint16(2, 1, Endian.little);
  data.setUint16(4, sizes.length, Endian.little);
  var offset = headerSize;
  for (var i = 0; i < sizes.length; i++) {
    final entry = 6 + i * 16;
    data.setUint8(entry, sizes[i] == 256 ? 0 : sizes[i]);
    data.setUint8(entry + 1, sizes[i] == 256 ? 0 : sizes[i]);
    data.setUint16(entry + 4, 1, Endian.little);
    data.setUint16(entry + 6, 32, Endian.little);
    data.setUint32(entry + 8, images[i].length, Endian.little);
    data.setUint32(entry + 12, offset, Endian.little);
    data.buffer
        .asUint8List()
        .setRange(offset, offset + images[i].length, images[i]);
    offset += images[i].length;
  }
  final output = File('windows/runner/resources/app_icon.ico');
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(data.buffer.asUint8List());
}
