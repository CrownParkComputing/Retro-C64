import 'package:flutter_test/flutter_test.dart';
import 'package:vice_multiplatform/services/rom_install_service.dart';

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

    test('SID tunes go to the music folder', () {
      expect(RomInstallService.targetFor('Commando.sid'), 'sids');
      expect(RomInstallService.targetFor('/tmp/x/Delta.SID'), 'sids');
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
  });

  group('RomScanResult', () {
    test('summarises what it took', () {
      const r = RomScanResult(machineRoms: 3, driveRoms: 1, sids: 20);
      expect(r.total, 24);
      expect(r.isEmpty, isFalse);
      expect(r.summary, contains('3 C64 ROM(s)'));
      expect(r.summary, contains('1 drive ROM(s)'));
      expect(r.summary, contains('20 SID tune(s)'));
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
      expect(r.summary, isNot(contains('SID')));
    });
  });
}
