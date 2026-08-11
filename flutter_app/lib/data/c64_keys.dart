// The real C64 8x8 keyboard matrix, as one shared catalogue.
//
// These row/column pairs are the coordinates `vice_core_matrix_key_event`
// takes (see vice_bridge.h), and they are the same values the full on-screen
// keyboard uses -- that overlay owns its own physical LAYOUT (which key sits
// next to which), but the coordinates themselves live here so the
// "add an on-screen button and assign it a key" flow can offer EVERY key
// rather than a short hardcoded list.
//
// Using the matrix directly is what makes any key assignable. The older
// `vice_core_key_event` path only knows seven fixed ordinals (Space,
// Run/Stop, Return, F1/F3/F5/F7), which is why the extra buttons do not use
// it.

/// One assignable C64 key: what to call it, and where it lives in the matrix.
class C64Key {
  final String label;
  final int row;
  final int column;

  const C64Key(this.label, this.row, this.column);

  /// Stable identity for persistence and de-duplication.
  String get id => '$row:$column';
}

/// Every key the bridge can press, grouped so the picker is navigable
/// rather than a wall of 64 buttons.
class C64KeyCatalogue {
  C64KeyCatalogue._();

  static const List<C64Key> letters = [
    C64Key('A', 1, 2), C64Key('B', 3, 4), C64Key('C', 2, 4),
    C64Key('D', 2, 2), C64Key('E', 1, 6), C64Key('F', 2, 5),
    C64Key('G', 3, 2), C64Key('H', 3, 5), C64Key('I', 4, 1),
    C64Key('J', 4, 2), C64Key('K', 4, 5), C64Key('L', 5, 2),
    C64Key('M', 4, 4), C64Key('N', 4, 7), C64Key('O', 4, 6),
    C64Key('P', 5, 1), C64Key('Q', 7, 6), C64Key('R', 2, 1),
    C64Key('S', 1, 5), C64Key('T', 2, 6), C64Key('U', 3, 6),
    C64Key('V', 3, 7), C64Key('W', 1, 1), C64Key('X', 2, 7),
    C64Key('Y', 3, 1), C64Key('Z', 1, 4),
  ];

  static const List<C64Key> digits = [
    C64Key('0', 4, 3), C64Key('1', 7, 0), C64Key('2', 7, 3),
    C64Key('3', 1, 0), C64Key('4', 1, 3), C64Key('5', 2, 0),
    C64Key('6', 2, 3), C64Key('7', 3, 0), C64Key('8', 3, 3),
    C64Key('9', 4, 0),
  ];

  static const List<C64Key> functionKeys = [
    C64Key('F1', 0, 4), C64Key('F3', 0, 5),
    C64Key('F5', 0, 6), C64Key('F7', 0, 3),
  ];

  /// The keys games actually ask for -- listed first in the picker because
  /// "press SPACE to start" and "RUN/STOP to abort" are most of the reason
  /// anyone adds a button at all.
  static const List<C64Key> common = [
    C64Key('SPACE', 7, 4),
    C64Key('RETURN', 0, 1),
    C64Key('RUN/STOP', 7, 7),
    C64Key('SHIFT', 1, 7),
    C64Key('CTRL', 7, 2),
    C64Key('C=', 7, 5),
    C64Key('CRSR ↕', 0, 7),
    C64Key('CRSR ↔', 0, 2),
    C64Key('DEL', 0, 0),
  ];

  static const List<C64Key> symbols = [
    C64Key('+', 5, 0), C64Key('-', 5, 3), C64Key('£', 6, 0),
    C64Key('@', 5, 6), C64Key('*', 6, 1), C64Key('↑', 6, 6),
    C64Key('←', 7, 1), C64Key(':', 5, 5), C64Key(';', 6, 2),
    C64Key('=', 6, 5), C64Key(',', 5, 7), C64Key('.', 5, 4),
    C64Key('/', 6, 7),
  ];

  /// Picker sections, in the order they are offered.
  static const Map<String, List<C64Key>> groups = {
    'Common': common,
    'Letters': letters,
    'Numbers': digits,
    'Function keys': functionKeys,
    'Symbols': symbols,
  };

  static List<C64Key> get all => [
        for (final group in groups.values) ...group,
      ];

  /// Looks a key back up from its persisted row/column, or null if the
  /// stored pair is not one this catalogue knows.
  static C64Key? find(int row, int column) {
    for (final key in all) {
      if (key.row == row && key.column == column) return key;
    }
    return null;
  }
}
