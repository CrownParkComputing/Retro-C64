import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';

/// Full port of C64BackgroundView.java: the workbench backdrop that turns
/// into a demo (raster bars, the Retro Recompilation logo, a sine scroller,
/// an audio-reactive equaliser) once the workbench has been left alone.
///
/// Faithful to the Java source in:
///  - palette (the exact ARGB values `RASTER_COLOURS` uses)
///  - per-frame deltas (phase += 0.09, scroll -= textSize*0.16, EQ rise/fall
///    ballistics of 0.55 / 0.12, peak decay of 0.006 per frame)
///  - trigger/reset semantics (`active` flips levels/peaks/scrollX back to
///    "nothing" the same way `setVisualiserActive(false)` does, and the
///    ticker does zero work while inactive)
///
/// The Java view drove all of this straight off `invalidate()`, i.e. once per
/// displayed frame at 60Hz. This port uses a raw [Ticker] callback, which also
/// fires once per displayed frame -- but a displayed frame is not a fixed unit
/// of time. Applying the constants once per tick tied the whole demo to the
/// refresh rate, and on a 120Hz ProMotion iPad it ran at literally double
/// speed. [_onTick] therefore scales every delta by how long the frame
/// actually took, relative to a 60Hz frame, so the pacing matches the Java
/// original on any display.
class C64Background extends StatefulWidget {
  /// Whether the screensaver (raster bars/logo/scroller/EQ) should be
  /// running. When false only the idle C64 screen frame (border + inner
  /// "screen" rect) is drawn, matching the Java view's `visualiserActive`.
  final bool active;

  /// The emulator details the scroller carries, e.g. build/machine/media/
  /// library count/FPS -- set by whoever knows them (the workbench), same
  /// division of responsibility as `setInfoText`.
  final String infoText;

  /// 0..100 loudness sample, matching `ViceVsid.getAudioLevel()` /
  /// `ViceNative.getAudioLevel()`. Defaults to a silent line.
  final int Function()? audioLevel;

  /// Fired on tap while [active] is true -- the wake gesture. The Java view
  /// makes itself `setClickable(active)` for the same reason: while it is
  /// showing, the workbench underneath is hidden, so wake taps must land
  /// here rather than falling through to the emulation surface.
  final VoidCallback? onWake;

  const C64Background({
    super.key,
    this.active = false,
    this.infoText = '',
    this.audioLevel,
    this.onWake,
  });

  @override
  State<C64Background> createState() => _C64BackgroundState();
}

/// Scroller step per 60Hz frame, as a fraction of the text size.
const double _scrollStepPerFrame = 0.08;

class _C64BackgroundState extends State<C64Background>
    with SingleTickerProviderStateMixin {
  static const int _barCount = 24;

  // The C64's own colours -- everything draws from this and nothing else.
  static const int _c64Black = 0xFF000000;
  static const int _c64Red = 0xFF883932;
  static const int _c64Cyan = 0xFF67B6BD;
  static const int _c64Purple = 0xFF8B3F96;
  static const int _c64Green = 0xFF55A049;
  static const int _c64Yellow = 0xFFBFCE72;
  static const int _c64Orange = 0xFF8B5429;
  static const int _c64LightRed = 0xFFB86962;
  static const int _c64LightGreen = 0xFF94E089;
  static const int _c64LightBlue = 0xFF7869C4;

  static const List<int> _rasterColours = [
    _c64Red, _c64Orange, _c64Yellow, _c64LightGreen, _c64Green,
    _c64Cyan, _c64LightBlue, _c64Purple, _c64LightRed, //
  ];

  static const int _screenBlue = 0xFF6060FF;
  static const int _borderBlue = 0xFF4040E0;

  late final Ticker _ticker;

  final List<double> _levels = List.filled(_barCount, 0.0);
  final List<double> _peaks = List.filled(_barCount, 0.0);
  double _phase = 0;
  double _scrollX = double.nan;
  /// Microsecond timestamp of the previous tick, for frame-rate-independent
  /// pacing (see _onTick).
  int? _lastTickMicros;
  /// One frame at the 60Hz the original per-frame constants were tuned for.
  static const double _frameMicros = 1000000 / 60;
  // Set by _onTick, consumed (and cleared) by the painter: the scroller's
  // per-frame step depends on the layout size (textSize derives from
  // innerRect.height), which is only known at paint time, but the step
  // itself must only ever apply once per real animation frame -- a stray
  // rebuild (e.g. a sidebar tap while the screensaver is up) must not also
  // nudge the scroller.
  double _pendingScrollFrames = 0;
  String _scrollerText = '';

  ui.Image? _logo;

  @override
  void initState() {
    super.initState();
    _updateScrollerText();
    _ticker = createTicker(_onTick)..start();
    _loadLogo();
  }

  @override
  void didUpdateWidget(covariant C64Background old) {
    super.didUpdateWidget(old);
    if (old.infoText != widget.infoText) _updateScrollerText();
    if (old.active != widget.active && !widget.active) {
      // Drop everything to the floor, mirroring setVisualiserActive(false):
      // the next appearance starts from nothing rather than resuming
      // mid-beat.
      for (var i = 0; i < _barCount; i++) {
        _levels[i] = 0;
        _peaks[i] = 0;
      }
      _scrollX = double.nan;
      _lastTickMicros = null;
      _pendingScrollFrames = 0;
    }
  }

  void _updateScrollerText() {
    // Padded either side so the message leaves the screen entirely before
    // it comes round again, which is what makes it read as a loop.
    _scrollerText =
        '          *** RETRO-C64 EMULATOR - COMMODORE 64 WORKSTATION ***          '
        '${widget.infoText.isEmpty ? '' : '${widget.infoText}          '}'
        'PRESS ANYWHERE TO WAKE          ';
  }

  Future<void> _loadLogo() async {
    try {
      final data = await rootBundle.load('assets/images/retro_recomp_logo.png');
      final codec =
          await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (mounted) setState(() => _logo = frame.image);
    } catch (_) {
      // A missing asset must not take the screensaver down with it.
    }
  }

  void _onTick(Duration elapsed) {
    // Does no work at all while not showing: an animation that redraws
    // itself forever behind a running game is a flat drain on the battery
    // for something nobody can see.
    if (!widget.active) return;

    // Per-frame deltas, scaled to how long the frame actually took.
    //
    // The constants below are the Java view's per-invalidate steps, and that
    // view ran at 60Hz. Applying them once per displayed frame made the whole
    // demo run at the display's refresh rate -- on a 120Hz ProMotion iPad
    // every part of it (bars, scroller, EQ) moved at exactly double speed.
    // Scaling by elapsed/16.67ms keeps the original 60Hz pacing on any
    // display. The first tick has no previous timestamp, so it takes one
    // nominal frame rather than the whole time since the ticker started.
    final micros = elapsed.inMicroseconds;
    final deltaMicros =
        _lastTickMicros == null ? _frameMicros : micros - _lastTickMicros!;
    _lastTickMicros = micros;
    // Clamped so a dropped frame or a spell in the background cannot make
    // the demo lurch forward by a visible jump.
    final frames = (deltaMicros / _frameMicros).clamp(0.0, 3.0);

    _phase += 0.09 * frames;
    _pendingScrollFrames += frames;

    final level = (widget.audioLevel?.call() ?? 0).clamp(0, 100);
    final loudness = level / 100.0;

    // EQ ballistics: rise fast, fall slow. The smoothing coefficients are
    // per-60Hz-frame too, so they get the same treatment -- applying an
    // exponential smoother twice as often makes it twice as twitchy.
    for (var i = 0; i < _barCount; i++) {
      final centre =
          1.0 - (((i / (_barCount - 1)) - 0.5).abs() * 1.6);
      final wobble = 0.55 + 0.45 * math.sin(_phase + i * 0.7);
      final target = loudness * math.max(0.05, centre) * wobble;
      final coefficient =
          ((target > _levels[i] ? 0.55 : 0.12) * frames).clamp(0.0, 1.0);
      _levels[i] += coefficient * (target - _levels[i]);
      if (_levels[i] < 0) _levels[i] = 0;
      _peaks[i] = math.max(_peaks[i] - 0.006 * frames, _levels[i]);
    }

    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final painter = _C64Painter(
      active: widget.active,
      phase: _phase,
      levels: _levels,
      peaks: _peaks,
      scrollXRef: this,
      scrollerText: _scrollerText,
      loudness: (widget.audioLevel?.call() ?? 0).clamp(0, 100) / 100.0,
      logo: _logo,
      rasterColours: _rasterColours,
      screenBlue: _screenBlue,
      borderBlue: _borderBlue,
      black: _c64Black,
    );

    final child = CustomPaint(painter: painter, size: Size.infinite);

    if (!widget.active) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onWake,
      child: child,
    );
  }
}

class _C64Painter extends CustomPainter {
  final bool active;
  final double phase;
  final List<double> levels;
  final List<double> peaks;
  final _C64BackgroundState scrollXRef;
  final String scrollerText;
  final double loudness;
  final ui.Image? logo;
  final List<int> rasterColours;
  final int screenBlue;
  final int borderBlue;
  final int black;

  _C64Painter({
    required this.active,
    required this.phase,
    required this.levels,
    required this.peaks,
    required this.scrollXRef,
    required this.scrollerText,
    required this.loudness,
    required this.logo,
    required this.rasterColours,
    required this.screenBlue,
    required this.borderBlue,
    required this.black,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;

    final inset = w / 10;
    final inner = Rect.fromLTRB(inset, inset / 2, w - inset, h - inset / 2);

    // While the screensaver is idle this widget paints NOTHING, so the
    // workbench sits on the plain app background. It used to fill the border
    // blue and then a lighter "screen" rect on top even when inactive, which
    // showed through as a stray square behind the workbench panels.
    // The C64 screen frame belongs to the screensaver itself, not to the
    // workbench's normal state.
    if (!active) return;

    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = Color(borderBlue));
    canvas.drawRect(inner, Paint()..color = Color(screenBlue));

    canvas.save();
    canvas.clipRect(inner);
    _drawRasterBars(canvas, inner);
    _drawLogo(canvas, inner);
    _drawEqualiser(canvas, inner);
    _drawScroller(canvas, inner);
    canvas.restore();
  }

  /// Lifts a C64 colour toward its brighter self, so a bar stands off the
  /// screen-blue background instead of blending into it.
  static Color _pronounced(Color base) {
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withSaturation((hsl.saturation * 1.45).clamp(0.0, 1.0))
        .withLightness((hsl.lightness * 1.25).clamp(0.0, 1.0))
        .toColor();
  }

  /// Moving horizontal colour bars -- the oldest trick the machine has.
  void _drawRasterBars(Canvas canvas, Rect inner) {
    final bandHeight = math.max(6.0, inner.height / 26);
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < rasterColours.length; i++) {
      final t = phase * 0.6 + i * 0.5;
      final centre = inner.top + inner.height * 0.5 +
          math.sin(t) * inner.height * 0.34;
      final thickness = bandHeight * (0.5 + loudness * 0.9);
      // The C64 palette is muted to begin with, and at 70/255 the bars were
      // little more than a tint on the blue. Much heavier alpha plus a
      // brightening pass makes them read as actual raster bars.
      paint.color = _pronounced(Color(rasterColours[i])).withAlpha(165);
      canvas.drawRect(
        Rect.fromLTRB(inner.left, centre - thickness * 0.5, inner.right,
            centre + thickness * 0.5),
        paint,
      );
    }
  }

  /// The Retro Recompilation logo, above the scroller, breathing on the
  /// beat. Sits on the raster bars, gently scaled by the music.
  void _drawLogo(Canvas canvas, Rect inner) {
    final img = logo;
    if (img == null) return;

    final maxWidth = inner.width * 0.62;
    final scale = maxWidth / img.width * (0.96 + loudness * 0.08);
    final lw = img.width * scale;
    final lh = img.height * scale;
    final cx = inner.center.dx;
    final cy = inner.top + inner.height * 0.30;

    final dst = Rect.fromLTRB(cx - lw * 0.5, cy - lh * 0.5, cx + lw * 0.5, cy + lh * 0.5);
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    canvas.drawImageRect(img, src, dst, Paint()..filterQuality = FilterQuality.high);
  }

  void _drawEqualiser(Canvas canvas, Rect inner) {
    final left = inner.left, right = inner.right, bottom = inner.bottom;
    final span = inner.height * 0.34;
    final barCount = levels.length;
    final slot = (right - left) / barCount;
    final barW = slot * 0.62;
    final gap = (slot - barW) * 0.5;

    final capPaint = Paint()..color = const Color(0xFFFFFFFF);

    for (var i = 0; i < barCount; i++) {
      final barH = levels[i] * span;
      final x = left + i * slot + gap;

      if (barH > 1) {
        final rect = Rect.fromLTRB(x, bottom - barH, x + barW, bottom);
        final shader = ui.Gradient.linear(
          Offset(0, bottom),
          Offset(0, bottom - barH),
          const [Color(0xFF00FFCC), Color(0xFF2D8CFF)],
        );
        canvas.drawRect(rect, Paint()..shader = shader);
      }

      // The peak cap, falling on its own. Without it a quiet passage looks
      // like the visualiser has stopped.
      final peakY = bottom - peaks[i] * span;
      if (peaks[i] > 0.01) {
        canvas.drawRect(Rect.fromLTRB(x, peakY - 3, x + barW, peakY), capPaint);
      }
    }
  }

  /// The sine scroller, straight across the middle of the screen. Drawn a
  /// character at a time: each one takes its vertical offset and colour
  /// from its own position along the wave.
  void _drawScroller(Canvas canvas, Rect inner) {
    if (scrollerText.isEmpty) return;

    final textSize = math.max(18.0, inner.height * 0.11);
    final style = TextStyle(
      fontFamily: 'monospace',
      fontWeight: FontWeight.bold,
      fontSize: textSize,
    );
    final baseY = inner.center.dy + textSize * 0.35;
    final amplitude = inner.height * 0.06;

    if (scrollXRef._scrollX.isNaN) scrollXRef._scrollX = inner.right;
    if (scrollXRef._pendingScrollFrames > 0) {
      // 0.08 rather than the Java view's 0.16: the original was tuned for a
      // phone held at arm's length, and at tablet size the same step reads as
      // a blur. This is per-60Hz-frame (see _onTick), so it stays put across
      // refresh rates.
      scrollXRef._scrollX -=
          textSize * _scrollStepPerFrame * scrollXRef._pendingScrollFrames;
      scrollXRef._pendingScrollFrames = 0;
    }

    // Per-character width cache for this frame's text size.
    final charWidths = <double>[];
    var totalWidth = 0.0;
    for (var i = 0; i < scrollerText.length; i++) {
      final tp = TextPainter(
        text: TextSpan(text: scrollerText[i], style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      charWidths.add(tp.width);
      totalWidth += tp.width;
    }

    var x = scrollXRef._scrollX;
    for (var i = 0; i < scrollerText.length; i++) {
      final charW = charWidths[i];
      if (x > inner.right) { x += charW; continue; }
      if (x + charW < inner.left) { x += charW; continue; }

      final wave = phase * 1.4 + x * 0.012;
      final y = baseY + math.sin(wave) * amplitude;

      // Colour cycles along the wave, standing in for a colour-washed
      // scroller's one raster interrupt per line.
      final idx = ((wave * 1.4 / math.pi).floor() % rasterColours.length +
              rasterColours.length) %
          rasterColours.length;
      final colour = rasterColours[idx];

      // A hard black shadow one pixel down, standing in for the outline a
      // real charset had baked into it.
      _drawChar(canvas, scrollerText[i], x + 2, y + 2, style, Color(black));
      _drawChar(canvas, scrollerText[i], x, y, style, Color(colour));
      x += charW;
    }

    // Round the loop once the last character has left on the left.
    if (scrollXRef._scrollX + totalWidth < inner.left) {
      scrollXRef._scrollX = inner.right;
    }
  }

  void _drawChar(Canvas canvas, String ch, double x, double y,
      TextStyle style, Color colour) {
    final tp = TextPainter(
      text: TextSpan(text: ch, style: style.copyWith(color: colour)),
      textDirection: TextDirection.ltr,
    )..layout();
    // Java's drawText(x, y, ...) places the text baseline at y; TextPainter
    // paints from the top-left, so shift up by the font's ascent-ish
    // fraction to land on the same baseline.
    tp.paint(canvas, Offset(x, y - style.fontSize! * 0.8));
  }

  @override
  bool shouldRepaint(covariant _C64Painter oldDelegate) => true;
}
