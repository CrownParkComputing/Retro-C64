// The key catalogue is coordinates into the real C64 keyboard matrix, and
// the only way to find out that a pair is wrong on a device is to press the
// button and get the wrong character. These checks catch the two mistakes a
// typo actually produces: a coordinate outside the 8x8 matrix (which the
// core silently ignores, so the button does nothing at all), and two keys
// sharing one pair (so one of them presses the other's key).
import 'package:flutter_test/flutter_test.dart';
import 'package:vice_multiplatform/data/c64_keys.dart';

void main() {
  test('every key is inside the 8x8 matrix', () {
    for (final key in C64KeyCatalogue.all) {
      expect(key.row, inInclusiveRange(0, 7), reason: '${key.label} row');
      expect(key.column, inInclusiveRange(0, 7), reason: '${key.label} column');
    }
  });

  test('no two keys share a matrix position', () {
    final seen = <String, String>{};
    for (final key in C64KeyCatalogue.all) {
      final clash = seen[key.id];
      expect(clash, isNull,
          reason: '${key.label} and $clash both sit at ${key.id}');
      seen[key.id] = key.label;
    }
  });

  test('the catalogue covers the whole alphabet and every digit', () {
    final labels = C64KeyCatalogue.all.map((k) => k.label).toSet();
    for (var c = 'A'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++) {
      expect(labels, contains(String.fromCharCode(c)));
    }
    for (var d = 0; d <= 9; d++) {
      expect(labels, contains('$d'));
    }
    expect(labels, containsAll(['SPACE', 'RETURN', 'RUN/STOP', 'F1', 'F7']));
  });

  test('groups between them are exactly the whole catalogue', () {
    final grouped = [
      for (final group in C64KeyCatalogue.groups.values) ...group,
    ];
    expect(grouped.length, C64KeyCatalogue.all.length);
    // Common is listed first: the picker leads with the keys games ask for.
    expect(C64KeyCatalogue.groups.keys.first, 'Common');
  });

  test('find() round-trips every key, and rejects unknown positions', () {
    // This is the persistence path: a stored row/column comes back as the
    // same key, or the custom button loses its label.
    for (final key in C64KeyCatalogue.all) {
      final found = C64KeyCatalogue.find(key.row, key.column);
      expect(found?.label, key.label);
    }
    // 8,8 is off the matrix entirely, so nothing can claim it.
    expect(C64KeyCatalogue.find(8, 8), isNull);
  });
}
