import 'package:flutter_test/flutter_test.dart';
import 'package:retro_c64/services/rom_install_service.dart';

/// The scan routes files into three directories VICE treats very
/// differently. Getting a drive ROM into C64/ instead of DRIVES/ does not
/// fail here -- it fails later, when a disk image will not load and reports
/// ?DEVICE NOT PRESENT, which points nowhere near this code.
void main() {
  group('targetFor', () {
    test('machine ROMs go to C64/, whatever the revision', () {
      for (final name in [
        'kernal-901227-03.bin',
        'kernal-251104-04.bin',
        'basic-901226-01.bin',
        'chargen-906143-02.bin',
      ]) {
        expect(RomInstallService.targetFor(name), 'C64', reason: name);
      }
    });

    test('drive ROMs go to DRIVES/', () {
      for (final name in [
        'dos1541-325302-01+901229-05.bin',
        'dos1571-310654-05.bin',
        'dos1581-318045-02.bin',
      ]) {
        expect(RomInstallService.targetFor(name), 'DRIVES', reason: name);
      }
    });

    test('SID tunes are NOT the ROM scan\'s job', () {
      // Music is game media and belongs to the games scan. Claiming it here
      // would copy every tune into the BIOS folder.
      expect(RomInstallService.targetFor('Commando.sid'), isNull);
      expect(RomInstallService.targetFor('/tmp/x/Delta.SID'), isNull);
    });

    test('a full path is classified by its filename alone', () {
      expect(
        RomInstallService.targetFor('/home/jon/Downloads/kernal-901227-03.bin'),
        'C64',
      );
    });

    test('everything else is ignored', () {
      // A VICE C64/ directory is mostly palettes and keymaps, and a games
      // folder is full of media the ROM scan must not touch.
      for (final name in [
        'c64hq.vpl',
        'sdl_sym.vkm',
        'Makefile.am',
        '1942.d64',
        'delta.tap',
        'outrun.prg',
        'Commando.sid',
        'notes.txt',
        'romantic.txt', // starts with "rom" but is not a .bin
      ]) {
        expect(RomInstallService.targetFor(name), isNull, reason: name);
      }
    });

    test('case does not matter', () {
      expect(RomInstallService.targetFor('KERNAL-901227-03.BIN'), 'C64');
      expect(RomInstallService.targetFor('DOS1541.BIN'), 'DRIVES');
    });

    test('extensionless VICE ROMs are recognised', () {
      // An existing VICE install -- which the guidance tells people to copy
      // from -- has these with no extension at all. Requiring .bin found
      // nothing there, so the drive ROM in particular never got imported.
      expect(RomInstallService.targetFor('kernal'), 'C64');
      expect(RomInstallService.targetFor('basic'), 'C64');
      expect(RomInstallService.targetFor('chargen'), 'C64');
      expect(RomInstallService.targetFor('/usr/share/vice/DRIVES/dos1541'),
          'DRIVES');
      expect(RomInstallService.targetFor('dos1571'), 'DRIVES');
    });

    test('extensionless files must match a name exactly', () {
      // The scan walks Downloads recursively, so a prefix rule with no
      // extension would import any stray file whose name starts right.
      for (final name in [
        'kernalsomething',
        'basically',
        'dos1541-notes',
        'README',
        'chargenerator',
      ]) {
        expect(RomInstallService.targetFor(name), isNull, reason: name);
      }
    });
  });

  group('what the user is told to supply', () {
    test('names both groups, where they go, and how each one fails', () {
      final reqs = RomInstallService.requirements;
      expect(reqs, hasLength(2));

      final machine = reqs.firstWhere((r) => r.folder == 'C64');
      expect(machine.what, contains('kernal'));
      expect(machine.why, contains('boot'));

      // The drive ROM has to be called out separately: it is the one whose
      // absence leaves a working emulator that cannot read a single .d64.
      final drive = reqs.firstWhere((r) => r.folder == 'DRIVES');
      expect(drive.what, contains('dos1541'));
      expect(drive.why, contains('DEVICE NOT PRESENT'));
    });
  });

  group('RomScanResult', () {
    test('summarises what it took', () {
      const r = RomScanResult(machineRoms: 3, driveRoms: 1);
      expect(r.total, 4);
      expect(r.isEmpty, isFalse);
      expect(r.summary, contains('3 C64 ROM(s)'));
      expect(r.summary, contains('1 drive ROM(s)'));
    });

    test('says so plainly when it found nothing', () {
      const r = RomScanResult();
      expect(r.isEmpty, isTrue);
      expect(r.summary, 'Nothing found to import.');
    });

    test('omits the categories it found none of', () {
      const r = RomScanResult(machineRoms: 3);
      expect(r.summary, contains('3 C64 ROM(s)'));
      expect(r.summary, isNot(contains('drive')));
    });
  });
}
