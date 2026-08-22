import 'package:flutter/material.dart';

import 'package:retro_c64/data/c64_keys.dart';
import 'package:retro_c64/data/custom_button.dart';
import 'package:retro_c64/ffi/vice_core.dart';
import 'package:retro_c64/theme/vice_theme.dart';

/// An extra on-screen button the user added themselves, bound either to one
/// C64 keyboard key or to a joystick direction.
///
/// Deliberately NOT a remap of an existing control: the joystick stays the
/// joystick and A/B stay fire, and these are added explicitly ("Add button"
/// -> pick a key or direction) from Input settings or the in-game menu.
///
/// Key presses go straight to `vice_core_matrix_key_event`, so any key in
/// [C64KeyCatalogue] works -- including SPACE and RUN/STOP, which is what
/// most games actually ask for. Direction presses do NOT touch the core
/// directly: they report their bit upward so the emulator screen can OR it
/// with the stick and the gamepad, exactly as the A/B buttons do. Driving
/// the core from here would make the last source to move win, so holding
/// this button would cancel the stick.
class CustomKeyButton extends StatefulWidget {
  final CustomButton binding;
  final ViceCore core;
  final double size;

  /// Direction bindings only: reports this button's own direction bit going
  /// down/up. Ignored for key bindings.
  final void Function(JoyDirection direction, bool down)? onDirectionChanged;

  const CustomKeyButton({
    super.key,
    required this.binding,
    required this.core,
    this.onDirectionChanged,
    this.size = 52,
  });

  @override
  State<CustomKeyButton> createState() => _CustomKeyButtonState();
}

class _CustomKeyButtonState extends State<CustomKeyButton> {
  bool _pressed = false;

  void _send(bool down) {
    final binding = widget.binding;
    if (binding.isDirection) {
      widget.onDirectionChanged?.call(binding.direction!, down);
    } else {
      final key = binding.key!;
      widget.core.matrixKeyEvent(key.row, key.column, down);
    }
  }

  void _down() {
    setState(() => _pressed = true);
    _send(true);
  }

  void _up() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    _send(false);
  }

  @override
  void dispose() {
    // A button removed (or a screen left) while held must not leave the key
    // stuck down in the emulated matrix, or the direction bit latched on.
    if (_pressed) _send(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _down(),
      onTapUp: (_) => _up(),
      onTapCancel: _up,
      child: Container(
        constraints: BoxConstraints(minWidth: widget.size),
        height: widget.size,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.size / 2),
          gradient: RadialGradient(
            center: const Alignment(-0.3, -0.3),
            colors: _pressed
                ? [const Color(0xFF34D9C4), const Color(0xFF1B8A7D)]
                : [
                    Colors.white.withValues(alpha: 0.30),
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
          widget.binding.label,
          maxLines: 1,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Modal that lets the user pick what a new button should do: a joystick
/// direction, or any C64 key.
///
/// Directions come first because they are four options against sixty-four,
/// and because "UP to jump" is the single most common reason to add a button
/// at all. Keys stay grouped by [C64KeyCatalogue.groups] so the full 8x8
/// matrix is browsable instead of being one undifferentiated grid.
Future<CustomButton?> showC64KeyPicker(BuildContext context) {
  return showDialog<CustomButton>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: const Color(0xFF141A1F),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Choose what the new button does',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 12, bottom: 6),
                    child: Text(
                      'JOYSTICK DIRECTION',
                      style: TextStyle(
                          color: ViceColors.accentTeal,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final direction in JoyDirection.values)
                        OutlinedButton(
                          onPressed: () => Navigator.of(context)
                              .pop(CustomButton.direction(direction)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0x55FFFFFF)),
                          ),
                          child: Text(direction.label),
                        ),
                    ],
                  ),
                  for (final entry in C64KeyCatalogue.groups.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 6),
                      child: Text(
                        entry.key.toUpperCase(),
                        style: const TextStyle(
                            color: ViceColors.accentTeal,
                            fontSize: 11,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final key in entry.value)
                          OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(CustomButton.key(key)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Color(0xFF3D4652)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              minimumSize: Size.zero,
                            ),
                            child: Text(key.label),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 12, 8),
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel',
                      style: TextStyle(color: Colors.white70)),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
