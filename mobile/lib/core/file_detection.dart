import 'dart:io';

/// Checks the file signature before handing untrusted input to the PDF parser.
/// Parsing is still required: a header alone does not make a valid PDF.
class FileDetectionService {
  const FileDetectionService();

  Future<bool> isPdf(String path) async {
    final file = File(path);
    if (!await file.exists() || await file.length() < 8) return false;
    final header = await file.openRead(0, 8).first;
    return header.length >= 5 &&
        header[0] == 0x25 &&
        header[1] == 0x50 &&
        header[2] == 0x44 &&
        header[3] == 0x46 &&
        header[4] == 0x2d;
  }
}

const fileDetection = FileDetectionService();
