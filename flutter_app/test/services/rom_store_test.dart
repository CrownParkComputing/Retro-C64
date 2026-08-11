// The user's own ROMs, now that the app ships none.
//
// The rules that matter: VICE opens ROMs by name, so an import has to
// RENAME as it copies; a file of the wrong size under a right-looking name
// is not the ROM it claims to be; and "can this machine boot" is a
// different question from "is every ROM here".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vice_multiplatform/services/rom_store.dart';

void main() {
  late Directory romRoot;
  late Directory incoming;

  setUp(() {
    romRoot = Directory.systemTemp.createTempSync('vice_romroot');
    incoming = Directory.systemTemp.createTempSync('vice_romsrc');
  });

  tearDown(() {
    romRoot.deleteSync(recursive: true);
    incoming.deleteSync(recursive: true);
  });

  /// A stand-in ROM image of exactly the right length.
  String writeRom(String name, int bytes) {
    final path = p.join(incoming.path, name);
    File(path).writeAsBytesSync(List.filled(bytes, 0x42));
    return path;
  }

  test('a fresh install cannot boot and says what is missing', () {
    expect(RomStore.canBoot(romRoot.path), isFalse);
    final described = RomStore.describeMissing(romRoot.path);
    expect(described, contains('KERNAL'));
    expect(described, contains('BASIC'));
    expect(described, contains('Character generator'));
  });

  test('installs a VICE-named set under the names VICE opens', () async {
    final paths = [
      writeRom('kernal-901227-03.bin', 8192),
      writeRom('basic-901226-01.bin', 8192),
      writeRom('chargen-901225-01.bin', 4096),
      writeRom('dos1541-325302-01+901229-05.bin', 16384),
    ];

    final installed = await RomStore.install(paths, romRoot.path);

    expect(installed.length, 4);
    expect(RomStore.canBoot(romRoot.path), isTrue);
    expect(RomStore.missing(romRoot.path), isEmpty);
    expect(
      File(p.join(romRoot.path, 'C64', 'kernal-901227-03.bin')).existsSync(),
      isTrue,
    );
    // The drive ROM goes in its own directory, where VICE looks for it.
    expect(
      File(p.join(romRoot.path, 'DRIVES', 'dos1541-325302-01+901229-05.bin'))
          .existsSync(),
      isTrue,
    );
  });

  test('renames a differently-named set to what VICE expects', () async {
    // A perfectly good ROM set that simply uses shorter names.
    final paths = [
      writeRom('kernal.bin', 8192),
      writeRom('basic.bin', 8192),
      writeRom('chargen.bin', 4096),
    ];

    await RomStore.install(paths, romRoot.path);

    expect(RomStore.canBoot(romRoot.path), isTrue);
    expect(File(p.join(romRoot.path, 'C64', 'basic-901226-01.bin')).existsSync(),
        isTrue);
  });

  test('a right-looking name at the wrong size is not installed', () async {
    // 8K is a kernal; this is not, whatever it calls itself.
    await RomStore.install([writeRom('kernal-truncated.bin', 512)], romRoot.path);

    expect(File(p.join(romRoot.path, 'C64', 'kernal-901227-03.bin')).existsSync(),
        isFalse);
    expect(RomStore.canBoot(romRoot.path), isFalse);
  });

  test('unrelated files in the set are ignored, not fatal', () async {
    final paths = [
      writeRom('kernal.bin', 8192),
      writeRom('basic.bin', 8192),
      writeRom('chargen.bin', 4096),
      // The rest of a typical VICE ROM set: other machines this app does
      // not emulate.
      writeRom('kernal-901246-01.bin', 8192), // a PET/other kernal
      writeRom('readme.txt', 120),
    ];

    final installed = await RomStore.install(paths, romRoot.path);

    expect(installed.length, 3);
    expect(RomStore.canBoot(romRoot.path), isTrue);
  });

  test('the machine boots without the 1541 ROM, which is not required', () async {
    await RomStore.install([
      writeRom('kernal.bin', 8192),
      writeRom('basic.bin', 8192),
      writeRom('chargen.bin', 4096),
    ], romRoot.path);

    expect(RomStore.canBoot(romRoot.path), isTrue);
    // ...but it is still reported, since without it every .d64 fails.
    expect(RomStore.missing(romRoot.path).single.namePrefix, 'dos1541');
    expect(RomStore.describeMissing(romRoot.path), contains('1541'));
  });
}
