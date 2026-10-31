import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:path_provider/path_provider.dart';
import '../../core/document_geometry.dart';

class ScanPage {
  String path;
  List<Offset> corners;
  List<Offset> automatic;
  String? corrected;
  ScanPage(this.path, List<Offset>? initial)
      : corners = List.of(initial ?? pageMargin),
        automatic = List.of(initial ?? pageMargin);
  Map<String, dynamic> toJson() => {
        'path': path,
        'corners': [
          for (final p in corners) [p.dx, p.dy]
        ],
        'automatic': [
          for (final p in automatic) [p.dx, p.dy]
        ],
        'corrected': corrected
      };
  factory ScanPage.fromJson(Map<String, dynamic> j) {
    List<Offset> points(dynamic v) => [
          for (final p in v)
            Offset((p[0] as num).toDouble(), (p[1] as num).toDouble())
        ];
    final page = ScanPage(j['path'] as String, points(j['automatic']));
    page.corners = points(j['corners']);
    page.corrected = j['corrected'] as String?;
    return page;
  }
}

/// A durable working manifest. Photos are copied before acknowledging capture.
class ScanDraft {
  static Future<void> _writing = Future<void>.value();
  static Future<File> get manifest=>_file('scan');
  static Future<File> _file(String key) async=>File('${(await getApplicationSupportDirectory()).path}/${key}_draft.json');
  static Future<void> save(List<ScanPage> pages,
      {int index = 0, bool review = false,String key='scan'}) {
    final content = jsonEncode({
      'index': index,
      'review': review,
      'pages': [for (final p in pages) p.toJson()]
    });
    final task = _writing.catchError((Object _) {}).then((_) => _save(content,key));
    _writing = task;
    return task;
  }

  static Future<void> _save(String content,String key) async {
    final f = await _file(key);
    await f.parent.create(recursive: true);
    final temp = File('${f.path}.new');
    await temp.writeAsString(content, flush: true);
    await temp.rename(f.path);
  }

  static Future<void> saveReview(List<String> paths) => save(
      [for (final path in paths) ScanPage(path, pageMargin)..corrected = path],
      review: true);
  static Future<(List<ScanPage>, int, bool)?> load({String key='scan'}) async {
    await _writing.catchError((Object _) {});
    final f = await _file(key);
    if (!await f.exists()) return null;
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return (
      [
        for (final p in j['pages'])
          ScanPage.fromJson(Map<String, dynamic>.from(p))
      ],
      j['index'] as int,
      j['review'] == true
    );
  }

  static Future<void> clear({String key='scan'}) async {
    await _writing.catchError((Object _) {});
    final f = await _file(key);
    if (await f.exists()) await f.delete();
  }
}

