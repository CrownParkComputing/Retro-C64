import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../ffi/vice_bindings.dart';
import '../services/video_settings.dart';

/// Live view of the C64 framebuffer.
///
/// Approach used (first pass): a periodic Timer polls
/// vice_core_get_framebuffer(), decodes the copied RGBA8888 bytes into a
/// ui.Image via decodeImageFromPixels, and repaints a CustomPaint with it.
/// This is NOT zero-copy -- every tick allocates a new GPU texture via the
/// image decode pipeline, which is wasteful compared to a true Flutter
/// `Texture` widget backed by an external OpenGL/Vulkan texture the native
/// side writes into directly (the way the SDL3 viewer or a real
/// FlutterTexture registrar would).
///
/// That path exists for embedder-level (platform-channel + native texture
/// registration) integration and was out of scope to stand up correctly in
/// this pass without also writing platform-specific (GL context sharing)
/// code per target OS. decodeImageFromPixels is the simplest thing that
/// proves FFI + rendering end-to-end; swapping it for a real Texture is the
/// next milestone's headline item.
class FramebufferView extends StatefulWidget {
  final ViceCoreBindings core;
  final Duration pollInterval;

  const FramebufferView({
    super.key,
    required this.core,
    this.pollInterval = const Duration(milliseconds: 33), // ~30fps
  });

  @override
  State<FramebufferView> createState() => _FramebufferViewState();
}

class _FramebufferViewState extends State<FramebufferView> {
  ui.Image? _image;
  Timer? _timer;
  bool _decoding = false;
  int _lastW = 0, _lastH = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.pollInterval, (_) => _tick());
  }

  void _tick() {
    if (_decoding) return;
    final frame = widget.core.getFramebuffer();
    if (frame == null) return;
    _decoding = true;
    final bytes = Uint8List.view(
        frame.argbAsRgba.buffer, frame.argbAsRgba.offsetInBytes, frame.argbAsRgba.lengthInBytes);
    ui.decodeImageFromPixels(
      bytes,
      frame.width,
      frame.height,
      ui.PixelFormat.rgba8888,
      (ui.Image img) {
        _decoding = false;
        if (!mounted) {
          img.dispose();
          return;
        }
        final old = _image;
        setState(() {
          _image = img;
          _lastW = frame.width;
          _lastH = frame.height;
        });
        old?.dispose();
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    if (img == null) {
      return const Center(
        child: Text(
          'Waiting for first frame...',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    // Every knob below is a real render-path setting shared with the Video
    // settings tab and the in-game Quick Settings panel (see
    // services/video_settings.dart).
    final settings = VideoSettings.instance;
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        final painter = CustomPaint(
          painter: _FramebufferPainter(
            image: img,
            crt: settings.crt,
            scanlineIntensity: settings.scanlineIntensity,
            smooth: settings.smooth,
          ),
          size: Size(_lastW.toDouble(), _lastH.toDouble()),
        );

        Widget picture;
        switch (settings.aspect) {
          case AspectMode.stretch:
            picture = SizedBox.expand(child: painter);
          case AspectMode.wide:
            picture = AspectRatio(aspectRatio: 16 / 9, child: painter);
          case AspectMode.integer:
            // Largest whole multiple of the emulator's own pixel grid that
            // fits, so every C64 pixel is the same size on screen.
            picture = LayoutBuilder(builder: (context, constraints) {
              final scale = _integerScale(constraints, _lastW, _lastH);
              return Center(
                child: SizedBox(
                  width: _lastW * scale,
                  height: _lastH * scale,
                  child: painter,
                ),
              );
            });
          case AspectMode.authentic:
            picture = AspectRatio(aspectRatio: 4 / 3, child: painter);
        }

        if (settings.bezel) picture = _Bezel(child: picture);
        if (settings.rotationQuarterTurns != 0) {
          picture = RotatedBox(
            quarterTurns: settings.rotationQuarterTurns,
            child: picture,
          );
        }
        return picture;
      },
    );
  }

  /// Whole-number scale factor for integer mode, never below 1 (a window
  /// smaller than one C64 screen still shows the picture, just clipped by
  /// the parent rather than blown up to a fractional size).
  static double _integerScale(BoxConstraints c, int w, int h) {
    if (w <= 0 || h <= 0) return 1;
    final byWidth = (c.maxWidth / w).floorToDouble();
    final byHeight = (c.maxHeight / h).floorToDouble();
    final scale = byWidth < byHeight ? byWidth : byHeight;
    return scale < 1 ? 1 : scale;
  }
}

/// The screen surround drawn when the Bezel setting is on: a dark rounded
/// frame with an inner rim, the way the picture sits inside a monitor's
/// plastic rather than running to the window edge.
class _Bezel extends StatelessWidget {
  final Widget child;
  const _Bezel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF14171B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF3A424D), width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black, blurRadius: 24, spreadRadius: 2),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: child,
      ),
    );
  }
}

class _FramebufferPainter extends CustomPainter {
  final ui.Image image;
  final bool crt;
  final double scanlineIntensity;
  final bool smooth;

  _FramebufferPainter({
    required this.image,
    required this.crt,
    required this.scanlineIntensity,
    required this.smooth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final src =
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..filterQuality = smooth ? FilterQuality.medium : FilterQuality.none;
    canvas.drawImageRect(image, src, dst, paint);
    if (!crt) return;

    // CRT: one dark line per emulated scanline, plus a soft vignette. Drawn
    // over the picture at output resolution, and skipped entirely when the
    // lines would be thinner than a device pixel (below ~2x scale they just
    // turn the whole picture grey).
    final rowHeight = size.height / image.height;
    if (rowHeight >= 2.0) {
      final linePaint = Paint()
        ..color = Colors.black.withValues(alpha: scanlineIntensity)
        ..strokeWidth = rowHeight / 2;
      for (double y = rowHeight / 2; y < size.height; y += rowHeight) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
      }
    }
    final vignette = Paint()
      ..shader = RadialGradient(
        radius: 0.85,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.28 * scanlineIntensity + 0.12),
        ],
        stops: const [0.65, 1.0],
      ).createShader(dst);
    canvas.drawRect(dst, vignette);
  }

  @override
  bool shouldRepaint(covariant _FramebufferPainter old) =>
      old.image != image ||
      old.crt != crt ||
      old.smooth != smooth ||
      old.scanlineIntensity != scanlineIntensity;
}
