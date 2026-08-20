import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_c64/ffi/vice_native_paths.dart';

/// Covers the check that decides whether the emulator can boot at all.
///
/// Worth testing on its own because when it is wrong the symptom is remote
/// from the cause: resolveRomDir() returns null, main.dart quietly skips
/// core.init(), and it finally surfaces as "SID player unavailable: No ROM
/// directory found" on a completely different screen.
void main() {
  group('1541 drive ROM', driveRomTests);

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

/// The 1541 drive ROM check, which is deliberately separate from the machine
/// ROM check above.
///
/// This is the gap that made .d64 files "not load": the machine ROMs were
/// present, so the app reported an installed ROM set and started happily,
/// and every disk image then failed inside the emulator with ?DEVICE NOT
/// PRESENT -- a symptom that looks like a bad disk image, not a missing ROM.
void driveRomTests() {
  late Directory drives;

  setUp(() => drives = Directory.systemTemp.createTempSync('drivecheck'));
  tearDown(() => drives.deleteSync(recursive: true));

  void write(String name) =>
      File(p.join(drives.path, name)).writeAsBytesSync([0, 1, 2, 3]);

  test('a missing DRIVES directory is not installed', () {
    final gone = Directory(p.join(drives.path, 'nope'));
    expect(ViceNativePaths.driveRomInstalledIn(gone), isFalse);
  });

  test('an empty DRIVES directory is not installed', () {
    expect(ViceNativePaths.driveRomInstalledIn(drives), isFalse);
  });

  test('every name VICE has shipped this ROM under is detected', () {
    for (final name in [
      'dos1541',
      'dos1541.bin',
      'dos1541-325302-01+901229-05.bin',
      'DOS1541',
    ]) {
      final dir = Directory.systemTemp.createTempSync('drive1');
      File(p.join(dir.path, name)).writeAsBytesSync([0]);
      expect(ViceNativePaths.driveRomInstalledIn(dir), isTrue, reason: name);
      dir.deleteSync(recursive: true);
    }
  });

  test('other drive ROMs do not stand in for the 1541', () {
    // A 1571 or 1581 ROM is a real drive ROM and the scan files it here, but
    // it does not make .d64 work -- so it must not read as installed.
    write('dos1571');
    write('dos1581.bin');
    expect(ViceNativePaths.driveRomInstalledIn(drives), isFalse);
  });

  test('dos1541ii is NOT the 1541 ROM', () {
    // The near-miss that actually shipped: dos1541ii shares its first seven
    // characters with dos1541, so a prefix test called it installed, the UI
    // said "disk images can load", and every .d64 died on ?DEVICE NOT
    // PRESENT because the emulated drive is a 1541 and its ROM was absent.
    write('dos1541ii-251968-03.bin');
    expect(ViceNativePaths.driveRomInstalledIn(drives), isFalse);
    expect(ViceNativePaths.driveRomFileIn(drives), isNull);
  });

  test('the real 1541 ROM alongside the 1541-II one is still found', () {
    write('dos1541ii-251968-03.bin');
    write('dos1541-325302-01+901229-05.bin');
    expect(ViceNativePaths.driveRomFileIn(drives),
        'dos1541-325302-01+901229-05.bin');
  });

  test('the accepted file is named, so the UI can show its evidence', () {
    write('dos1541');
    expect(ViceNativePaths.driveRomFileIn(drives), 'dos1541');
  });

  test('machine ROMs sitting in DRIVES do not count', () {
    write('kernal-901227-03.bin');
    expect(ViceNativePaths.driveRomInstalledIn(drives), isFalse);
  });
}
