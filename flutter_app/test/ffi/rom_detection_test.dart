import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vice_multiplatform/ffi/vice_native_paths.dart';

/// Covers the check that decides whether the emulator can boot at all.
///
/// Worth testing on its own because when it is wrong the symptom is remote
/// from the cause: resolveRomDir() returns null, main.dart quietly skips
/// core.init(), and it finally surfaces as "SID player unavailable: No ROM
/// directory found" on a completely different screen.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('romcheck'));
  tearDown(() => tmp.deleteSync(recursive: true));

  void write(String name) =>
      File(p.join(tmp.path, name)).writeAsBytesSync([0, 1, 2, 3]);

  test('the real filenames a user installs are detected', () {
    // Exactly the files pushed to the device.
    write('kernal-901227-03.bin');
    write('basic-901226-01.bin');
    write('chargen-901225-01.bin');
    expect(ViceNativePaths.romsInstalledIn(tmp), isTrue);
  });

  test('other machine revisions are detected too', () {
    write('kernal-251104-04.bin');
    write('basic-901226-01.bin');
    write('chargen-906143-02.bin');
    expect(ViceNativePaths.romsInstalledIn(tmp), isTrue);
  });

  test('case does not matter', () {
    write('KERNAL-901227-03.BIN');
    write('BASIC-901226-01.BIN');
    write('CHARGEN-901225-01.BIN');
    expect(ViceNativePaths.romsInstalledIn(tmp), isTrue);
  });

  test('a missing member of the trio fails the check', () {
    write('kernal-901227-03.bin');
    write('basic-901226-01.bin');
    expect(ViceNativePaths.romsInstalledIn(tmp), isFalse,
        reason: 'no chargen means the C64 cannot boot');
  });

  test('an empty or absent directory fails the check', () {
    expect(ViceNativePaths.romsInstalledIn(tmp), isFalse);
    expect(
      ViceNativePaths.romsInstalledIn(Directory(p.join(tmp.path, 'nope'))),
      isFalse,
    );
  });

  test('palette and keymap files are not mistaken for ROMs', () {
    // A C64/ directory copied wholesale from a VICE install is mostly .vpl
    // and .vkm files; those must not satisfy the check on their own.
    write('c64hq.vpl');
    write('sdl_sym.vkm');
    expect(ViceNativePaths.romsInstalledIn(tmp), isFalse);
  });
}
