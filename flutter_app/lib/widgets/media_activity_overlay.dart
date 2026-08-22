import 'dart:async';

import 'package:flutter/material.dart';

import 'package:retro_c64/ffi/vice_core.dart';

/// Loading feedback for the emulator screen, drawn in the letterbox space
/// around the C64 picture.
///
/// A real C64 gives you something to watch while a program loads -- the
/// datasette counter creeping up, the drive light on, the loader's own
/// border stripes. Emulated, a tape load is minutes of apparently nothing,
/// so this surfaces what the core is actually doing: the datasette counter
/// and motor for .tap, the head's track and drive LED for .d64.
///
/// The numbers come from VICE's own status-bar callbacks (see the
/// ui_display_* wrappers in vice_bridge.c), which only fire while media is
/// being read -- so "no activity" here genuinely means the drive and tape
/// are idle, not that the indicator is broken.
///
/// When nothing is loading the same space carries the Retro Recompilation
/// logo, which is otherwise only seen on the screensaver.
class MediaActivityOverlay extends StatefulWidget {
  final ViceCore core;

  /// Aspect ratio of the emulated picture, used to work out where the
  /// letterbox bands are. The C64's visible area is ~4:3.
  final double pictureAspect;

  const MediaActivityOverlay({
    super.key,
    required this.core,
    this.pictureAspect = 4 / 3,
  });

  @override
  State<MediaActivityOverlay> createState() => _MediaActivityOverlayState();
}

class _MediaActivityOverlayState extends State<MediaActivityOverlay> {
  /// Four times a second: the counter ticks slowly enough that anything
  /// faster is wasted work, and slow enough that it still reads as live.
  static const Duration _pollInterval = Duration(milliseconds: 250);

  Timer? _timer;
  MediaActivity _activity = MediaActivity.idle;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _poll() {
    if (!mounted) return;
    final next = widget.core.mediaActivity;
    // Only rebuild when something actually moved -- this runs behind a
    // game at 250ms forever, and a setState per tick for an unchanged
    // counter is pure churn.
    if (next.tapeCounter != _activity.tapeCounter ||
        next.tapeMotorOn != _activity.tapeMotorOn ||
        next.driveTrack != _activity.driveTrack ||
        next.driveActive != _activity.driveActive) {
      setState(() => _activity = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenAspect = constraints.maxWidth / constraints.maxHeight;
        // Slack below the picture (portrait/tall screens) is the roomiest
        // place to put chrome; on wide screens the band is at the side.
        final tallSlack = screenAspect < widget.pictureAspect;
        final pictureHeight = tallSlack
            ? constraints.maxWidth / widget.pictureAspect
            : constraints.maxHeight;
        final bandHeight = (constraints.maxHeight - pictureHeight) / 2;

        // Too cramped to draw into without covering the picture.
        if (bandHeight < 44) return const SizedBox.shrink();

        return Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: bandHeight,
            child: Center(
              child: _activity.isLoading
                  ? _LoadingIndicator(activity: _activity)
                  : const _Logo(),
            ),
          ),
        );
      },
    );
  }
}

class _LoadingIndicator extends StatelessWidget {
  final MediaActivity activity;

  const _LoadingIndicator({required this.activity});

  @override
  Widget build(BuildContext context) {
    final tape = activity.tapeMotorOn;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Spinner(active: true),
        const SizedBox(width: 10),
        Text(
          tape
              // The three-digit counter is exactly what the real deck shows,
              // padded so it does not jiggle as it climbs.
              ? 'TAPE  ${activity.tapeCounter.toString().padLeft(3, '0')}'
              : 'DISK  TRACK ${activity.driveTrack.toString().padLeft(2, '0')}',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            fontSize: 14,
            letterSpacing: 1.5,
            color: Color(0xFFC7C7FF),
          ),
        ),
        const SizedBox(width: 10),
        // The drive LED, as a light rather than a number -- it is the thing
        // people already know how to read.
        if (!tape)
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: activity.driveActive
                  ? const Color(0xFF55A049)
                  : const Color(0xFF2A2A2A),
            ),
          ),
      ],
    );
  }
}

/// A slowly rotating tape reel. Deliberately not a Material spinner: this
/// sits under a C64 picture.
class _Spinner extends StatefulWidget {
  final bool active;
  const _Spinner({required this.active});

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: const Icon(Icons.album, size: 18, color: Color(0xFFC7C7FF)),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    // Understated: this is idle-state chrome sharing a screen with a game,
    // not a splash.
    return Opacity(
      opacity: 0.45,
      child: Image.asset(
        'assets/images/retro_recomp_logo.png',
        height: 28,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}
