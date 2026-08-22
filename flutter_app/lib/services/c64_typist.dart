// Types text on the emulated C64 by pressing its keys.
//
// The C64 has no "inject this string" entry point -- the KERNAL reads a
// hardware keyboard matrix -- so typing means holding a key down, waiting long
// enough for the scan to see it, and letting go. That is what this does.
//
// The coordinates are the real 8x8 matrix (row = port A line, column = port B
// line), the same numbering vice_bridge.h's vice_core_matrix_key_event takes.
// Characters that need SHIFT hold left shift around the keypress, which is how
// the machine itself produces them -- there is no separate '"' key to press.
import 'dart:async';

import 'package:retro_c64/ffi/vice_core.dart';

class C64Typist {
  /// Left SHIFT, held for the shifted characters below.
  static const (int, int) _lshift = (1, 7);

  /// The unshifted matrix position of every character we can type.
  static const Map<String, (int, int)> unshifted = {
    '0': (4, 3), '1': (7, 0), '2': (7, 3), '3': (1, 0), '4': (1, 3),
    '5': (2, 0), '6': (2, 3), '7': (3, 0), '8': (3, 3), '9': (4, 0),
    'A': (1, 2), 'B': (3, 4), 'C': (2, 4), 'D': (2, 2), 'E': (1, 6),
    'F': (2, 5), 'G': (3, 2), 'H': (3, 5), 'I': (4, 1), 'J': (4, 2),
    'K': (4, 5), 'L': (5, 2), 'M': (4, 4), 'N': (4, 7), 'O': (4, 6),
    'P': (5, 1), 'Q': (7, 6), 'R': (2, 1), 'S': (1, 5), 'T': (2, 6),
    'U': (3, 6), 'V': (3, 7), 'W': (1, 1), 'X': (2, 7), 'Y': (3, 1),
    'Z': (1, 4),
    ' ': (7, 4), '\r': (0, 1), '\n': (0, 1),
    '+': (5, 0), '-': (5, 3), '*': (6, 1), '/': (6, 7), '=': (6, 5),
    ',': (5, 7), '.': (5, 4), ':': (5, 5), ';': (6, 2), '@': (5, 6),
  };

  /// Characters produced by SHIFT plus another key. The C64's shifted digits
  /// are not the ones on a modern keyboard: SHIFT+2 is '"', not '@'.
  static const Map<String, String> shifted = {
    '!': '1', '"': '2', '#': '3', '\$': '4', '%': '5',
    '&': '6', "'": '7', '(': '8', ')': '9',
    '<': ',', '>': '.', '?': '/', '[': ':', ']': ';',
  };

  /// How long a key is held, and the gap before the next one.
  ///
  /// The KERNAL scans the matrix once per frame (20ms) and debounces, so a
  /// press shorter than a couple of frames can be missed entirely and one
  /// held too long auto-repeats into a doubled character. These two values
  /// straddle that window.
  static const Duration hold = Duration(milliseconds: 45);
  static const Duration gap = Duration(milliseconds: 35);

  /// Type [text] a character at a time. Unknown characters are skipped rather
  /// than approximated: a listing with a wrong character in it is a SYNTAX
  /// ERROR the user has to debug, which is worse than one with a gap.
  static Future<void> type(ViceCore core, String text) async {
    for (final raw in text.split('')) {
      final ch = raw.toUpperCase();
      final shiftFor = shifted[ch];
      final pos = unshifted[shiftFor ?? ch];
      if (pos == null) continue;
      if (shiftFor != null) core.matrixKeyEvent(_lshift.$1, _lshift.$2, true);
      core.matrixKeyEvent(pos.$1, pos.$2, true);
      await Future<void>.delayed(hold);
      core.matrixKeyEvent(pos.$1, pos.$2, false);
      if (shiftFor != null) core.matrixKeyEvent(_lshift.$1, _lshift.$2, false);
      await Future<void>.delayed(gap);
    }
  }

  /// Type a BASIC listing, one line per RETURN.
  static Future<void> typeListing(ViceCore core, List<String> lines) async {
    for (final line in lines) {
      await type(core, '$line\r');
      // BASIC tokenises the line after RETURN; typing into that costs
      // characters off the front of the next line.
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }
}
