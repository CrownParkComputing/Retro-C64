import 'package:flutter_test/flutter_test.dart';
import 'package:retro_c64/data/category.dart';
import 'package:retro_c64/data/media_entry.dart';

/// The library built from a granted SAF tree has no filesystem path to read an
/// extension from - only the display name the document provider reports. These
/// are the shapes real C64 filenames actually take, including the ones on the
/// test device, because getting this wrong loads a disk as a tape.
void main() {
  MediaFormatFilter typeOf(String displayName) =>
      MediaEntry.filterForExtension(displayName.split('.').last);

  test('a plain uppercase disk image is a disk', () {
    expect(typeOf('FLYINGSH.D64'), MediaFormatFilter.disk);
    expect(typeOf('1942.D64'), MediaFormatFilter.disk);
  });

  test('a scene release with dots and brackets is still a disk', () {
    expect(
      typeOf('Rambo - First Blood Part II (1986)(Ocean Software)'
          '[cr REM][t REM][#012].d64'),
      MediaFormatFilter.disk,
    );
  });

  // The one that matters: a name whose own text mentions another format.
  // Scene names routinely carry [t64], tape or +TAPE tags on a disk release.
  test('a disk whose name mentions tape is not a tape', () {
    expect(typeOf('Turrican (1990)(Rainbow Arts)[t64 crack].d64'),
        MediaFormatFilter.disk);
    expect(typeOf('Some Game +TAPE FIX.d64'), MediaFormatFilter.disk);
  });

  test('real tapes are still tapes', () {
    expect(typeOf('GAME.TAP'), MediaFormatFilter.tape);
    expect(typeOf('GAME.t64'), MediaFormatFilter.tape);
  });

  test('other formats keep their kind', () {
    expect(typeOf('GAME.PRG'), MediaFormatFilter.prg);
    expect(typeOf('GAME.CRT'), MediaFormatFilter.cartridge);
    expect(typeOf('GAME.d81'), MediaFormatFilter.disk);
  });

  // A document provider can report a name with no extension at all.
  test('a name with no extension is not guessed at', () {
    expect(typeOf('README'), MediaFormatFilter.none);
  });
}
