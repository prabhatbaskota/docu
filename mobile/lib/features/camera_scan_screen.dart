import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/image_tools.dart';
import '../core/pdf_engine.dart' show friendlyError;
import '../core/toast.dart';
import 'crop_screen.dart';

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

  /// Pages already in the batch (so numbering continues when adding more).
  final int startAt;
  const CameraScanScreen({super.key, required this.multiple, this.startAt = 0});

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen> {
  CameraController? _c;
  String? _error;
  bool _busy = false; // taking a photo (single mode: also crop step)
  bool _finishing = false;
  bool _torch = false;
  int _nextId = 0;
  final List<_Shot> _shots = [];
  final Set<Future<void>> _work = {};

  @override
  void initState() {
    super.initState();
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
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await c.initialize();
      await c.setFlashMode(FlashMode.off);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _c = c);
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _error = e.code.contains('Denied')
            ? 'Camera permission is needed to scan. Allow it in the phone settings.'
            : 'Camera error: ${e.description ?? e.code}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
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
      final file = await c.takePicture();
      if (!mounted) return;
      if (widget.multiple) {
        // Ready for the next shot immediately; prepare this one in background.
        final shot = _Shot(_nextId++);
        setState(() {
          _shots.add(shot);
          _busy = false;
        });
        late final Future<void> job;
        job = normalizeImage(file.path).then((n) {
          shot.path = n.$1;
          if (mounted) setState(() {});
        }).catchError((Object e) {
          _shots.remove(shot);
          if (mounted) {
            setState(() {});
            toast(context, friendlyError(e));
          }
        }).whenComplete(() => _work.remove(job));
        _work.add(job);
        return;
      }

      // Single page: normalize, crop, finish.
      final n = await normalizeImage(file.path);
      if (!mounted) return;
      final rect = await Navigator.of(context).push<Rect>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => CropScreen(path: n.$1, imgW: n.$2, imgH: n.$3),
        ),
      );
      if (rect == null) {
        if (mounted) setState(() => _busy = false); // retake
        return;
      }
      final full = rect.width >= n.$2 - 2 && rect.height >= n.$3 - 2;
      final path = full ? n.$1 : await cropImageFile(n.$1, rect);
      if (!mounted) return;
      Navigator.pop(context, <String>[path]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, friendlyError(e));
    }
  }

  Future<void> _done() async {
    setState(() => _finishing = true);
    await Future.wait(_work.toList());
    if (!mounted) return;
    final paths = [
      for (final s in _shots)
        if (s.path != null) s.path!
    ];
    Navigator.pop(context, paths);
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
      canPop: _shots.isEmpty && !_finishing,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _finishing) return;
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
                                onPressed: _finishing
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
                                widget.multiple
                                    ? 'Page ${widget.startAt + _shots.length + 1}'
                                    : 'Single page',
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
                                child: CameraPreview(c),
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
