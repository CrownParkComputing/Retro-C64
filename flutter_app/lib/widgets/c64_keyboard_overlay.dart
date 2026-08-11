import 'package:flutter/material.dart';

import '../ffi/vice_core.dart';

/// One key on the overlay: either a direct C64 keyboard-matrix key
/// (row/column non-null, matching vice_bridge.h's vice_core_matrix_key_event
/// row/column semantics) or a one-shot action (TYPE RUN / LIST / CLOSE).
/// A null row/column with no action (RESTORE) renders as a disabled key --
/// RESTORE is a hardware NMI line in the real C64, and the native bridge in
/// this repo (vice_bridge.h) doesn't expose a hook for it, so it's shown for
/// layout fidelity with the Android keyboard but is a no-op here.
class _KeySpec {
  final String label;
  final int? row;
  final int? column;
  final double weight;
  final VoidCallback? action;
  const _KeySpec(this.label, this.row, this.column, {this.weight = 1.0, this.action});
}

/// Port of MainActivity.createKeyboardOverlay: a full 5-row C64 keyboard
/// overlay, each regular key driving `vice_core_matrix_key_event` directly
/// (same row/column values as the Android original, which are themselves
/// the real C64 8x8 keyboard matrix coordinates). TYPE RUN / LIST are
/// implemented here as a scripted sequence of matrix key taps (there's no
/// native "feed a string" entry point in this repo's bridge, unlike
/// Android's C64Native.feedKeyboard) -- see [_typeString].
class C64KeyboardOverlay extends StatelessWidget {
  final ViceCore core;
  final VoidCallback onClose;

  const C64KeyboardOverlay({super.key, required this.core, required this.onClose});

  // Row/column for each character this overlay can "type" via TYPE RUN /
  // LIST, taken from the same matrix coordinates as the on-screen keys
  // below (digits, letters, and RETURN).
  static const Map<String, (int, int)> _charMatrix = {
    '0': (4, 3), '1': (7, 0), '2': (7, 3), '3': (1, 0), '4': (1, 3),
    '5': (2, 0), '6': (2, 3), '7': (3, 0), '8': (3, 3), '9': (4, 0),
    'A': (1, 2), 'B': (3, 4), 'C': (2, 4), 'D': (2, 2), 'E': (1, 6),
    'F': (2, 5), 'G': (3, 2), 'H': (3, 5), 'I': (4, 1), 'J': (4, 2),
    'K': (4, 5), 'L': (5, 2), 'M': (4, 4), 'N': (4, 7), 'O': (4, 6),
    'P': (5, 1), 'Q': (7, 6), 'R': (2, 1), 'S': (1, 5), 'T': (2, 6),
    'U': (3, 6), 'V': (3, 7), 'W': (1, 1), 'X': (2, 7), 'Y': (3, 1),
    'Z': (1, 4), '\r': (0, 1), ' ': (7, 4),
  };

  Future<void> _typeString(String text) async {
    for (final ch in text.split('')) {
      final pos = _charMatrix[ch.toUpperCase()];
      if (pos == null) continue;
      core.matrixKeyEvent(pos.$1, pos.$2, true);
      await Future.delayed(const Duration(milliseconds: 45));
      core.matrixKeyEvent(pos.$1, pos.$2, false);
      await Future.delayed(const Duration(milliseconds: 35));
    }
  }

  List<List<_KeySpec>> get _rows => [
        [
          _KeySpec('←', 7, 1), _KeySpec('1', 7, 0), _KeySpec('2', 7, 3),
          _KeySpec('3', 1, 0), _KeySpec('4', 1, 3), _KeySpec('5', 2, 0),
          _KeySpec('6', 2, 3), _KeySpec('7', 3, 0), _KeySpec('8', 3, 3),
          _KeySpec('9', 4, 0), _KeySpec('0', 4, 3), _KeySpec('+', 5, 0),
          _KeySpec('-', 5, 3), _KeySpec('£', 6, 0), _KeySpec('DEL', 0, 0),
          _KeySpec('F1', 0, 4),
        ],
        [
          _KeySpec('CTRL', 7, 2, weight: 1.35), _KeySpec('Q', 7, 6),
          _KeySpec('W', 1, 1), _KeySpec('E', 1, 6), _KeySpec('R', 2, 1),
          _KeySpec('T', 2, 6), _KeySpec('Y', 3, 1), _KeySpec('U', 3, 6),
          _KeySpec('I', 4, 1), _KeySpec('O', 4, 6), _KeySpec('P', 5, 1),
          _KeySpec('@', 5, 6), _KeySpec('*', 6, 1), _KeySpec('↑', 6, 6),
          _KeySpec('RESTORE', null, null, weight: 1.65),
          _KeySpec('F3', 0, 5),
        ],
        [
          _KeySpec('RUN/STOP', 7, 7, weight: 1.8), _KeySpec('A', 1, 2),
          _KeySpec('S', 1, 5), _KeySpec('D', 2, 2), _KeySpec('F', 2, 5),
          _KeySpec('G', 3, 2), _KeySpec('H', 3, 5), _KeySpec('J', 4, 2),
          _KeySpec('K', 4, 5), _KeySpec('L', 5, 2), _KeySpec(':', 5, 5),
          _KeySpec(';', 6, 2), _KeySpec('=', 6, 5),
          _KeySpec('RETURN', 0, 1, weight: 1.8), _KeySpec('F5', 0, 6),
        ],
        [
          _KeySpec('C=', 7, 5, weight: 1.25), _KeySpec('SHIFT', 1, 7, weight: 1.45),
          _KeySpec('Z', 1, 4), _KeySpec('X', 2, 7), _KeySpec('C', 2, 4),
          _KeySpec('V', 3, 7), _KeySpec('B', 3, 4), _KeySpec('N', 4, 7),
          _KeySpec('M', 4, 4), _KeySpec(',', 5, 7), _KeySpec('.', 5, 4),
          _KeySpec('/', 6, 7), _KeySpec('SHIFT', 6, 4, weight: 1.45),
          _KeySpec('CRSR ↕', 0, 7, weight: 1.45),
          _KeySpec('CRSR ↔', 0, 2, weight: 1.45), _KeySpec('F7', 0, 3),
        ],
        [
          _KeySpec('SPACE', 7, 4, weight: 6.0),
          _KeySpec('TYPE RUN', null, null, weight: 1.8, action: () => _typeString('RUN\r')),
          _KeySpec('LIST', null, null, weight: 1.4, action: () => _typeString('LIST\r')),
          _KeySpec('CLOSE', null, null, weight: 1.4, action: onClose),
        ],
      ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xEE0B0D10),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final row in _rows) _KeyboardRow(core: core, keys: row)],
      ),
    );
  }
}

class _KeyboardRow extends StatelessWidget {
  final ViceCore core;
  final List<_KeySpec> keys;
  const _KeyboardRow({required this.core, required this.keys});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          for (final spec in keys)
            Expanded(
              flex: (spec.weight * 20).round(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: spec.action != null
                    ? _ActionKey(spec: spec)
                    : _MatrixKey(core: core, spec: spec),
              ),
            ),
        ],
      ),
    );
  }
}

class _MatrixKey extends StatefulWidget {
  final ViceCore core;
  final _KeySpec spec;
  const _MatrixKey({required this.core, required this.spec});

  @override
  State<_MatrixKey> createState() => _MatrixKeyState();
}

class _MatrixKeyState extends State<_MatrixKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final enabled = spec.row != null && spec.column != null;
    return GestureDetector(
      onTapDown: enabled
          ? (_) {
              setState(() => _pressed = true);
              widget.core.matrixKeyEvent(spec.row!, spec.column!, true);
            }
          : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.core.matrixKeyEvent(spec.row!, spec.column!, false);
            }
          : null,
      onTapCancel: enabled
          ? () {
              setState(() => _pressed = false);
              widget.core.matrixKeyEvent(spec.row!, spec.column!, false);
            }
          : null,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: !enabled
              ? const Color(0x33303844)
              : (_pressed ? const Color(0xFF34D9C4) : const Color(0xFF22272E)),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFF3D4652)),
        ),
        child: Text(
          spec.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: enabled ? Colors.white : Colors.white38,
            fontSize: spec.label.length > 5 ? 9 : 11,
          ),
        ),
      ),
    );
  }
}

class _ActionKey extends StatelessWidget {
  final _KeySpec spec;
  const _ActionKey({required this.spec});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: spec.action,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF22272E),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFF3D4652)),
        ),
        child: Text(spec.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 10)),
      ),
    );
  }
}
