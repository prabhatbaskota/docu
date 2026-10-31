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
  // The document association uses a dedicated page silhouette with the docu mark.
  final page = img.Image(width: 512, height: 512, numChannels: 4);
  img.fill(page, color: img.ColorRgba8(0, 0, 0, 0));
  img.fillRect(page,
      x1: 92,
      y1: 24,
      x2: 420,
      y2: 488,
      radius: 24,
      color: img.ColorRgb8(220, 229, 239));
  img.fillRect(page,
      x1: 102,
      y1: 34,
      x2: 410,
      y2: 478,
      radius: 18,
      color: img.ColorRgb8(255, 255, 255));
  final mark = img.copyResize(source,
      width: 200, height: 200, interpolation: img.Interpolation.average);
  img.compositeImage(page, mark, dstX: 156, dstY: 124);
  for (final y in [362, 394, 426]) {
    img.fillRect(page,
        x1: 152,
        y1: y,
        x2: y == 426 ? 302 : 360,
        y2: y + 10,
        radius: 5,
        color: img.ColorRgb8(127, 149, 172));
  }
  final documentImages = [
    for (final size in sizes)
      Uint8List.fromList(img.encodePng(img.copyResize(page,
          width: size, height: size, interpolation: img.Interpolation.average)))
  ];
  final documentData = ByteData(
      headerSize + documentImages.fold<int>(0, (n, b) => n + b.length));
  documentData.setUint16(2, 1, Endian.little);
  documentData.setUint16(4, sizes.length, Endian.little);
  var position = headerSize;
  for (var i = 0; i < sizes.length; i++) {
    final entry = 6 + i * 16;
    documentData.setUint8(entry, sizes[i] == 256 ? 0 : sizes[i]);
    documentData.setUint8(entry + 1, sizes[i] == 256 ? 0 : sizes[i]);
    documentData.setUint16(entry + 4, 1, Endian.little);
    documentData.setUint16(entry + 6, 32, Endian.little);
    documentData.setUint32(entry + 8, documentImages[i].length, Endian.little);
    documentData.setUint32(entry + 12, position, Endian.little);
    documentData.buffer.asUint8List().setRange(
        position, position + documentImages[i].length, documentImages[i]);
    position += documentImages[i].length;
  }
  File('windows/runner/resources/document_icon.ico')
      .writeAsBytesSync(documentData.buffer.asUint8List());
}
