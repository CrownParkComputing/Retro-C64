import 'package:flutter_test/flutter_test.dart';
import 'package:vice_multiplatform/services/artwork_service.dart';

void main() {
  group('slugFor', () {
    test('matches the pack names built from the media set', () {
      // Left: the filename in the user's library. Right: the slug
      // tools/build-art-packs.sh derives from the media set's display title.
      // These two are computed independently and must agree, which is the
      // whole reason packs are named by slug rather than display name.
      const cases = {
        'outrun.prg': 'outrun', // media title "Out Run"
        'saint_dragon.d64': 'saintdragon', // "Saint Dragon"
        'thing_on_a_spring.tap': 'thingonaspring', // "Thing on a Spring"
        'stunt_car_racer.prg': 'stuntcarracer', // "Stunt Car Racer"
        'buggy_boy.prg': 'buggyboy', // "Buggy Boy"
        '1942.d64': '1942',
        'delta.tap': 'delta',
        'commando.tap': 'commando',
        'sanxion.d64': 'sanxion',
        'thrust.tap': 'thrust',
        'salamander.d64': 'salamander',
      };

      cases.forEach((filename, expected) {
        expect(ArtworkService.slugFor(filename), expected,
            reason: '$filename should resolve to $expected.zip');
      });
    });

    test('is case- and punctuation-insensitive', () {
      // The same title however it is spelled on disk.
      expect(ArtworkService.slugFor('Out Run.prg'), 'outrun');
      expect(ArtworkService.slugFor('OUT-RUN.PRG'), 'outrun');
      expect(ArtworkService.slugFor("Ghosts 'n Goblins.d64"), 'ghostsngoblins');
    });

    test('a name with nothing usable in it yields an empty slug', () {
      // Guarded by artworkFor, which never requests an empty slug.
      expect(ArtworkService.slugFor('...'), isEmpty);
      expect(ArtworkService.slugFor('---.d64'), isEmpty);
    });
  });
}
