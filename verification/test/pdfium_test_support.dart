import 'dart:ffi';
import 'dart:io';
import 'package:pdfrx/pdfrx.dart';

/// The pinned PDFium loader predates Flutter's current native-assets manifest.
/// Point tests at the host library already downloaded by its build hook.
Future<void> initializeTestPdfium() async {
  final host = switch (Abi.current()) {
    Abi.linuxX64 => 'linux-x64/libpdfium.so',
    Abi.linuxArm64 => 'linux-arm64/libpdfium.so',
    Abi.windowsX64 => 'win-x64/pdfium.dll',
    Abi.windowsArm64 => 'win-arm64/pdfium.dll',
    Abi.macosX64 => 'mac-x64/libpdfium.dylib',
    Abi.macosArm64 => 'mac-arm64/libpdfium.dylib',
    _ => null,
  };
  final cache = Directory('.dart_tool/hooks_runner/shared/pdfium_dart');
  if (host != null && await cache.exists()) {
    await for (final entry in cache.list(recursive: true, followLinks: false)) {
      if (entry is File &&
          entry.path.replaceAll('\\', '/').endsWith('/$host')) {
        Pdfrx.pdfiumModulePath = entry.absolute.path;
        break;
      }
    }
  }
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  await pdfrxFlutterInitialize();
}
