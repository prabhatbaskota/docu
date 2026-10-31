# 01-live-edges

Complete final integrated files. Apply the bundle as a whole; shared imports cross feature boundaries.

See [test steps and limits](README.md).

## `mobile/lib/core/document_edges.dart`

```dart
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
export 'document_geometry.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Transfer one owned plane; sampling, rotation, and detection all run off the UI isolate.
List<Offset>? detectPreview((TransferableTypedData,int,int,int,int,bool,int) frame) {
  final raw=frame.$1.materialize().asUint8List();
  final portrait=frame.$7==90||frame.$7==270;
  final sourceW=portrait?frame.$3:frame.$2,sourceH=portrait?frame.$2:frame.$3;
  const width=480;
  final height=(480*sourceH/sourceW).round();
  final luma=Uint8List(width*height);
  for(var y=0;y<height;y++) {
    for(var x=0;x<width;x++) {
      final px=x*sourceW~/width,py=y*sourceH~/height;
      final sx=frame.$7==90?py:frame.$7==270?frame.$2-1-py:frame.$7==180?frame.$2-1-px:px;
      final sy=frame.$7==90?frame.$3-1-px:frame.$7==270?px:frame.$7==180?frame.$3-1-py:py;
      final offset=sy*frame.$4+sx*frame.$5;
      luma[y*width+x]=frame.$6?((raw[offset]*29+raw[offset+1]*150+raw[offset+2]*77)>>8):raw[offset];
    }
  }
  return detectLuma((luma,width,height));
}

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
  // OpenCV applies EXIF orientation while decoding; retain photo resolution.
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
```

## `mobile/lib/core/document_geometry.dart`

```dart
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
```

## `mobile/lib/features/camera_scan_screen.dart`

```dart
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../core/document_edges.dart';
import 'scan/edge_correction_screen.dart';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/pdf_engine.dart' show friendlyError;
import '../core/toast.dart';

class _Shot {
  final int id;
  String? path; // set once the photo is normalized in the background
  _Shot(this.id);
}

/// Manual-capture camera.
/// Single mode: shutter, then crop, then done.
/// Multiple mode: shutter again and again with nothing in between; photos are
/// prepared in the background and the whole batch is reviewed afterwards.
/// Pops with the list of image paths (empty/null = cancelled).
class CameraScanScreen extends StatefulWidget {
  final bool multiple;
  final String draftKey;

  /// Pages already in the batch (so numbering continues when adding more).
  final int startAt;
  final String? prompt;
  final double? guideAspect;
  const CameraScanScreen({super.key, required this.multiple, this.startAt = 0,this.prompt,this.guideAspect,this.draftKey='scan'});

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen> with WidgetsBindingObserver {
  final _tracker = EdgeTracker();
  bool _detecting = false;
  int _lastFrame = 0;
  double? _frameAspect;
  bool _paused = false;
  final List<ScanPage> _pages = [];
  Future<void> _preparation=Future<void>.value();
  CameraController? _c;
  String? _error;
  bool _busy = false; // taking a photo (single mode: also crop step)
  bool _finishing = false;
  bool _torch = false;
  int _nextId = 0;
  final List<_Shot> _shots = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _init();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw StateError('No camera found.');
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final c = CameraController(
        back,
        ResolutionPreset.ultraHigh,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
      );
      await c.initialize();
      await c.setFlashMode(FlashMode.off);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _c = c);
      await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await c.startImageStream(_frame);
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _error = e.code.contains('Denied')
            ? 'Camera permission is needed to scan. Allow it in the phone settings.'
            : 'The camera is unavailable. Close other camera apps and try again.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _c?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _paused = true;
      final old = _c; _c = null; old?.dispose();
    } else if (state == AppLifecycleState.resumed && _paused) {
      _paused = false; _init();
    }
  }

  Future<void> _frame(CameraImage image) async {
    final now=DateTime.now().millisecondsSinceEpoch;
    if (_detecting || _busy || _finishing || now-_lastFrame<110) return;
    _lastFrame=now; _detecting=true;
    try {
      final rotate=(_c?.description.sensorOrientation ?? 90);
      final portrait=rotate==90 || rotate==270;
      final sourceW=portrait?image.height:image.width;
      final sourceH=portrait?image.width:image.height;
      _frameAspect=sourceW/sourceH;
      final plane=image.planes.first;
      final found=await compute(detectPreview,(
        TransferableTypedData.fromList([plane.bytes]),image.width,image.height,
        plane.bytesPerRow,plane.bytesPerPixel??1,image.format.group==ImageFormatGroup.bgra8888,rotate));
      if(mounted) setState(()=>_tracker.update(found));
    } catch (_) {
      if(mounted)setState(()=>_tracker.update(null));
    } finally { _detecting=false; }
  }

  Future<void> _toggleTorch() async {
    final c = _c;
    if (c == null) return;
    try {
      await c.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      setState(() => _torch = !_torch);
    } catch (_) {}
  }

  Future<void> _shoot() async {
    final c = _c;
    if (_busy || _finishing || c == null || !c.value.isInitialized) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      final corners=_tracker.corners==null?null:List<Offset>.of(_tracker.corners!);
      final frameAspect=_frameAspect;
      await c.stopImageStream();
      final file = await c.takePicture();
      if (!mounted) return;
      final dir=Directory('${(await getApplicationSupportDirectory()).path}/scan_pages');
      await dir.create(recursive:true);
      final original=await File(file.path).copy('${dir.path}/${DateTime.now().microsecondsSinceEpoch}.jpg');
      final page=ScanPage(original.path,corners);
      _pages.add(page);
      await ScanDraft.save(_pages,key:widget.draftKey);
      final shot=_Shot(_nextId++)..path=original.path;
      _shots.add(shot);
      _preparation=_preparation.then((_)async{
        try {
          final n=await normalizeScanPhoto(original.path);
          page.path=n.$1; shot.path=n.$1;
          if(corners!=null && frameAspect!=null) {
            final photoAspect=n.$2/n.$3;
            final adjusted=[for(final p in corners)Offset(
              photoAspect > frameAspect ? 0.5+(p.dx-0.5)*frameAspect/photoAspect : p.dx,
              photoAspect < frameAspect ? 0.5+(p.dy-0.5)*photoAspect/frameAspect : p.dy)];
            page.corners=List.of(adjusted);page.automatic=List.of(adjusted);
          }
          await ScanDraft.save(_pages,key:widget.draftKey);
          if(mounted)setState((){});
        } catch (_) {
          if(mounted)toast(context,'Photo kept. It will be opened for correction when you tap Done.');
        }
      });
      if(!mounted)return;
      if (widget.multiple) {
        setState(()=>_busy=false);
        await c.startImageStream(_frame);
        return;
      }
      await _done();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, 'Could not prepare this photo. Captured pages are kept; tap Done to recover them.');
    }
  }

  Future<void> _done() async {
    setState(() => _finishing = true);
    try {
      await _preparation;
      if(_c?.value.isStreamingImages==true)await _c!.stopImageStream();
      if(!mounted)return;
      final paths=await Navigator.of(context).push<List<String>>(MaterialPageRoute(
        builder:(_)=>EdgeCorrectionScreen(pages:_pages,draftKey:widget.draftKey)));
      if(!mounted)return;
      if(paths!=null){Navigator.pop(context,paths);return;}
      if(!widget.multiple){_pages.clear();_shots.clear();await ScanDraft.clear(key:widget.draftKey);}
      setState(() { _finishing=false; _busy=false; });
      await _c?.startImageStream(_frame);
    } catch (_) {
      if(mounted){setState(() { _finishing=false; _busy=false; });toast(context,'Could not open correction. Your pages are kept.');}
    }
  }

  Future<bool> _confirmDiscard() async {
    if (_shots.isEmpty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Discard ${_shots.length} scanned page(s)?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep scanning')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard')),
        ],
      ),
    );
    if(ok==true){await _preparation;await ScanDraft.clear(key:widget.draftKey);}
    return ok == true;
  }

  Widget _shutter() => Semantics(
        button: true,
        label: 'Take photo',
        child: GestureDetector(
          onTap: (_busy || _finishing) ? null : _shoot,
          child: Container(
            width: 76,
            height: 76,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _busy ? Colors.white54 : Colors.white,
              ),
              child: (_busy && !widget.multiple)
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : null,
            ),
          ),
        ),
      );

  Widget _lastThumb() {
    if (_shots.isEmpty) return const SizedBox(width: 56, height: 56);
    final withPath = _shots.where((s) => s.path != null);
    final last = withPath.isEmpty ? null : withPath.last.path;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 56,
            height: 56,
            child: last == null
                ? const ColoredBox(
                    color: Colors.white24,
                    child: Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  )
                : Image.file(File(last), fit: BoxFit.cover, cacheWidth: 160),
          ),
        ),
        Positioned(
          right: -6,
          top: -6,
          child: CircleAvatar(
            radius: 11,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text('${_shots.length}',
                style: const TextStyle(fontSize: 12, color: Colors.white)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return PopScope(
      canPop: _shots.isEmpty && !_finishing && !_busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _finishing || _busy) return;
        if (await _confirmDiscard() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center),
                  ),
                )
              : c == null
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: 'Close',
                                icon: const Icon(Icons.close,
                                    color: Colors.white),
                                onPressed: _finishing || _busy
                                    ? null
                                    : () async {
                                        if (await _confirmDiscard() &&
                                            context.mounted) {
                                          Navigator.pop(context);
                                        }
                                      },
                              ),
                              const Spacer(),
                              Text(
                                widget.prompt ?? (widget.multiple
                                    ? 'Page ${widget.startAt + _shots.length + 1}'
                                    : 'Single page'),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: 'Torch',
                                icon: Icon(
                                  _torch ? Icons.flash_on : Icons.flash_off,
                                  color: Colors.white,
                                ),
                                onPressed: _toggleTorch,
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: AspectRatio(
                                aspectRatio: 1 / c.value.aspectRatio,
                                child: Stack(fit:StackFit.expand,children:[CameraPreview(c),
                                  if(widget.guideAspect!=null)Center(child:FractionallySizedBox(widthFactor:.85,
                                    child:AspectRatio(aspectRatio:widget.guideAspect!,child:DecoratedBox(
                                      decoration:BoxDecoration(border:Border.all(color:Colors.white70,width:2),borderRadius:BorderRadius.circular(12)))))),
                                  IgnorePointer(child:LayoutBuilder(builder:(context,box)=>CustomPaint(
                                    painter:PageOutline([for(final p in _tracker.corners ?? <Offset>[]) Offset(p.dx*box.maxWidth,p.dy*box.maxHeight)]))))]),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _lastThumb(),
                              _shutter(),
                              widget.multiple
                                  ? FilledButton(
                                      onPressed: _shots.isEmpty ||
                                              _busy ||
                                              _finishing
                                          ? null
                                          : _done,
                                      child: _finishing
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child:
                                                  CircularProgressIndicator(
                                                      strokeWidth: 2))
                                          : Text('Done (${_shots.length})'),
                                    )
                                  : const SizedBox(width: 56),
                            ],
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}
```

## `desktop/lib/core/document_edges.dart`

```dart
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
```

## `desktop/lib/core/document_geometry.dart`

```dart
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
```
