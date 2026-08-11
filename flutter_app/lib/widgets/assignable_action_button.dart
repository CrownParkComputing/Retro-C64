import 'package:flutter/material.dart';

/// One of the two on-screen fire buttons (A / B).
///
/// These are plain fire buttons and nothing else. They used to carry a
/// hidden long-press-to-remap gesture, which was the wrong shape for the
/// job: a remap you have to discover by holding a button is invisible, and
/// it also meant the only way to get a keyboard key on screen was to give
/// up one of your two fire buttons. Assigning C64 keys is now an explicit
/// "add a button, choose its key" flow in Input settings that ADDS extra
/// buttons (see widgets/custom_key_button.dart) instead of taking these
/// over.
class ActionButton extends StatefulWidget {
  final String label;

  /// Reports this button's own fire bit going down/up. The emulator screen
  /// ORs it with the other input sources and sends one joystick update.
  final ValueChanged<bool> onFireBitChanged;
  final double size;

  const ActionButton({
    super.key,
    required this.label,
    required this.onFireBitChanged,
    this.size = 64,
  });

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool _pressed = false;

  void _down() {
    setState(() => _pressed = true);
    widget.onFireBitChanged(true);
  }

  void _up() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    widget.onFireBitChanged(false);
  }

  @override
  void dispose() {
    // Never leave fire latched on because the screen went away mid-press.
    if (_pressed) widget.onFireBitChanged(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _down(),
      onTapUp: (_) => _up(),
      onTapCancel: _up,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.3, -0.3),
            colors: _pressed
                ? [const Color(0xFF34D9C4), const Color(0xFF1B8A7D)]
                : [
                    Colors.white.withValues(alpha: 0.35),
                    const Color(0x665F6670),
                  ],
          ),
          border: Border.all(
            color: _pressed ? Colors.white : const Color(0x99D6DADF),
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          widget.label,
          style: const TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
