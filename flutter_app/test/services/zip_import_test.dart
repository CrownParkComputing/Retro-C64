import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vice_multiplatform/services/rom_install_service.dart';
import 'package:vice_multiplatform/services/zip_import.dart';

/// Zips are how ROM sets and games actually arrive, and until they were
/// understood the scans walked past them and reported "nothing found" with the
/// archive sitting in plain sight -- which reads as a broken scan rather than
/// an unsupported format. These tests build real archives rather than mocking
/// a decoder, because the failure being guarded against is a routing one: a
/// drive ROM landing in C64/ still installs "successfully" and only shows up
/// later as ?DEVICE NOT PRESENT.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('zip_import_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Writes a zip containing [entries] (name -> contents).
  File makeZip(String name, Map<String, String> entries) {
    final archive = Archive();
    for (final e in entries.entries) {
      final bytes = e.value.codeUnits;
      archive.addFile(ArchiveFile(e.key, bytes.length, bytes));
    }
    final file = File(p.join(tmp.path, name))
      ..writeAsBytesSync(ZipEncoder().encode(archive));
    return file;
  }

  group('isZip', () {
    test('matches only .zip, case-insensitively', () {
      expect(ZipImport.isZip('roms.zip'), isTrue);
      expect(ZipImport.isZip('/a/b/ROMS.ZIP'), isTrue);
      expect(ZipImport.isZip('Commando.d64'), isFalse);
      expect(ZipImport.isZip('kernal'), isFalse);
    });
  });

  group('memberNames', () {
    test('lists files and skips directories', () {
      final zip = makeZip('games.zip', {
        'Commando.d64': 'x',
        'nested/Delta.tap': 'y',
      });
      expect(ZipImport.memberNames(zip),
          containsAll(<String>['Commando.d64', 'nested/Delta.tap']));
    });

    test('a corrupt archive yields nothing rather than throwing', () {
      final bogus = File(p.join(tmp.path, 'broken.zip'))
        ..writeAsStringSync('this is not a zip');
      expect(ZipImport.memberNames(bogus), isEmpty);
    });
  });

  group('extractWhere routes ROM members the same way loose files are routed',
      () {
    test('a mixed ROM set lands in C64/ and DRIVES/ respectively', () {
      final zip = makeZip('vice-roms.zip', {
        'C64/kernal-901227-03.bin': 'k',
        'C64/basic-901226-01.bin': 'b',
        'C64/chargen-901225-01.bin': 'c',
        'DRIVES/dos1541-325302-01+901229-05.bin': 'd',
        'readme.txt': 'ignore me',
      });
      final c64 = Directory(p.join(tmp.path, 'C64'))..createSync();
      final drives = Directory(p.join(tmp.path, 'DRIVES'))..createSync();

      final written = ZipImport.extractWhere(zip, (name) {
        switch (RomInstallService.targetFor(name)) {
          case 'C64':
            return c64.path;
          case 'DRIVES':
            return drives.path;
          default:
            return null;
        }
      });

      expect(written.where((d) => d == c64.path).length, 3);
      expect(written.where((d) => d == drives.path).length, 1);
      expect(File(p.join(c64.path, 'kernal-901227-03.bin')).existsSync(), isTrue);
      expect(
        File(p.join(drives.path, 'dos1541-325302-01+901229-05.bin'))
            .existsSync(),
        isTrue,
      );
      // The drive ROM must NOT have been filed with the machine ROMs.
      expect(File(p.join(c64.path, 'dos1541-325302-01+901229-05.bin'))
          .existsSync(), isFalse);
      // Nothing unrecognised is installed.
      expect(File(p.join(c64.path, 'readme.txt')).existsSync(), isFalse);
    });

    test('extensionless VICE names are accepted from inside a zip too', () {
      final zip = makeZip('vice-data.zip', {
        'C64/kernal': 'k',
        'DRIVES/dos1541': 'd',
      });
      final c64 = Directory(p.join(tmp.path, 'C64'))..createSync();
      final drives = Directory(p.join(tmp.path, 'DRIVES'))..createSync();

      ZipImport.extractWhere(zip, (name) => switch (
          RomInstallService.targetFor(name)) {
            'C64' => c64.path,
            'DRIVES' => drives.path,
            _ => null,
          });

      expect(File(p.join(c64.path, 'kernal')).existsSync(), isTrue);
      expect(File(p.join(drives.path, 'dos1541')).existsSync(), isTrue);
    });

    test('a member escaping its directory is written by basename only', () {
      // An archive can name a member ../../evil; honouring that would let a
      // download write outside the folder it was imported into.
      final zip = makeZip('nasty.zip', {'../../kernal': 'k'});
      final c64 = Directory(p.join(tmp.path, 'C64'))..createSync();

      ZipImport.extractWhere(
          zip, (name) => RomInstallService.targetFor(name) == 'C64'
              ? c64.path
              : null);

      expect(File(p.join(c64.path, 'kernal')).existsSync(), isTrue);
      expect(File(p.join(tmp.path, '..', '..', 'kernal')).existsSync(), isFalse);
    });

    test('an existing file is not overwritten', () {
      final zip = makeZip('roms.zip', {'kernal': 'from-zip'});
      final c64 = Directory(p.join(tmp.path, 'C64'))..createSync();
      File(p.join(c64.path, 'kernal')).writeAsStringSync('already here');

      ZipImport.extractWhere(
          zip, (name) => RomInstallService.targetFor(name) == 'C64'
              ? c64.path
              : null);

      expect(File(p.join(c64.path, 'kernal')).readAsStringSync(),
          'already here');
    });
  });

  group('extractMember', () {
    test('pulls one named member out to an exact destination', () {
      final zip = makeZip('games.zip', {
        'Commando.d64': 'commando-bytes',
        'Delta.d64': 'delta-bytes',
      });
      final dest = p.join(tmp.path, 'imported', 'Commando.d64');

      expect(ZipImport.extractMember(zip, 'Commando.d64', dest), isTrue);
      expect(File(dest).readAsStringSync(), 'commando-bytes');
    });

    test('a missing member fails without throwing', () {
      final zip = makeZip('games.zip', {'Commando.d64': 'x'});
      expect(
        ZipImport.extractMember(zip, 'Nope.d64', p.join(tmp.path, 'Nope.d64')),
        isFalse,
      );
    });
  });
}
