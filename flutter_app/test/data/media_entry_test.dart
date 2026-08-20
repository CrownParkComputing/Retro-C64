// The extension -> media type map decides which files the library even
// offers, so every supported extension is asserted individually rather than
// by looping over the same table the code uses (a loop over the same source
// of truth proves nothing).
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_c64/data/category.dart';
import 'package:retro_c64/data/media_entry.dart';
import 'package:retro_c64/services/storage_access.dart';

void main() {
  group('MediaEntry.filterForExtension', () {
    const expected = <String, MediaFormatFilter>{
      'd64': MediaFormatFilter.disk,
      'd71': MediaFormatFilter.disk,
      'd81': MediaFormatFilter.disk,
      'g64': MediaFormatFilter.disk,
      'tap': MediaFormatFilter.tape,
      't64': MediaFormatFilter.tape,
      'crt': MediaFormatFilter.cartridge,
      'prg': MediaFormatFilter.prg,
      'p00': MediaFormatFilter.prg,
    };

    expected.forEach((ext, filter) {
      test('$ext is ${filter.name}', () {
        expect(MediaEntry.filterForExtension(ext), filter);
      });
    });

    test('is case-insensitive', () {
      // Real C64 archives are full of SHOUTED extensions.
      expect(MediaEntry.filterForExtension('D64'), MediaFormatFilter.disk);
      expect(MediaEntry.filterForExtension('T64'), MediaFormatFilter.tape);
      expect(MediaEntry.filterForExtension('Crt'), MediaFormatFilter.cartridge);
    });

    test('anything else is none, and so never reaches the library', () {
      for (final ext in ['', 'txt', 'zip', 'd64x', 'nes', 'png', 'sid']) {
        expect(MediaEntry.filterForExtension(ext), MediaFormatFilter.none,
            reason: '"$ext" must not be offered as C64 game media');
      }
    });

    test('sid is deliberately not game media -- it is the Music tab\'s', () {
      // Listed in kGameFileExtensions for the wizard's folder scan, but a
      // tune is not a title: it must not appear in the games grid.
      expect(kGameFileExtensions, contains('sid'));
      expect(MediaEntry.filterForExtension('sid'), MediaFormatFilter.none);
    });

    test('every game extension the wizard scans for is one the app can '
        'classify', () {
      // Drift guard: the two lists are maintained separately, and a wizard
      // that imports a format the library then refuses to show is a folder
      // full of games that never appear.
      for (final ext in kGameFileExtensions) {
        if (ext == 'sid') continue;
        expect(MediaEntry.filterForExtension(ext),
            isNot(MediaFormatFilter.none),
            reason: 'wizard scans for "$ext" but the library drops it');
      }
    });
  });

  group('MediaEntry naming', () {
    MediaEntry entry(String name) => MediaEntry(
        displayName: name, path: '/games/$name', mediaType: MediaFormatFilter.disk);

    test('extension label is the upper-cased suffix', () {
      expect(entry('Boulder Dash.d64').extensionLabel, 'D64');
      expect(entry('IK+.t64').extensionLabel, 'T64');
    });

    test('extension label falls back to ? when there is no usable suffix', () {
      expect(entry('README').extensionLabel, '?');
      expect(entry('trailing.').extensionLabel, '?');
    });

    test('base name drops the extension but keeps dotted titles intact', () {
      expect(entry('Boulder Dash.d64').baseName, 'Boulder Dash');
      expect(entry('Wizball v1.2.d64').baseName, 'Wizball v1.2');
      expect(entry('README').baseName, 'README');
    });
  });
}
