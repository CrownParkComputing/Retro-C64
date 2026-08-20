import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_c64/services/artwork_service.dart';

/// Runs against a REAL pack built by tools/build-art-packs.sh, so the test
/// fails if the builder and the extractor ever disagree about pack layout --
/// which is exactly the kind of drift that shows up on a device as tiles
/// silently staying blank.
void main() {
  final packDir = Directory(
    '/tmp/claude-1000/-home-jon/ef852570-04f0-40a1-9737-d382ecbdf2a1/scratchpad/artpacks',
  );
  final realPack = File(p.join(packDir.path, 'commando.zip'));

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('artwork'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a real pack extracts to the four images the grid reads', () async {
    if (!realPack.existsSync()) {
      markTestSkipped('no built packs available at ${packDir.path}');
      return;
    }

    final dest = Directory(p.join(tmp.path, 'commando'));
    final wrote = await ArtworkService.extractPack(realPack, dest);

    expect(wrote, 4, reason: 'box3d, wheel, title and thumb');
    for (final name in ['box3d', 'wheel', 'title', 'thumb']) {
      final file = File(p.join(dest.path, '$name.webp'));
      expect(file.existsSync(), isTrue, reason: '$name.webp missing');
      expect(file.lengthSync(), greaterThan(0), reason: '$name.webp empty');
    }
  });

  test('a zip that is not an artwork pack is skipped, not thrown on', () async {
    // The scan roots hold plenty of unrelated archives.
    final notAPack = File(p.join(tmp.path, 'random.zip'))
      ..writeAsBytesSync(List<int>.filled(64, 7));
    final dest = Directory(p.join(tmp.path, 'out'));

    expect(await ArtworkService.extractPack(notAPack, dest), 0);
  });

  test('a missing file yields 0 rather than throwing', () async {
    final absent = File(p.join(tmp.path, 'nope.zip'));
    final dest = Directory(p.join(tmp.path, 'out2'));
    expect(await ArtworkService.extractPack(absent, dest), 0);
  });

  test('the slug a pack extracts under matches the game filename', () {
    // The two halves are derived independently and must meet.
    expect(ArtworkService.slugFor('commando.zip'), 'commando');
    expect(ArtworkService.slugFor('commando.tap'), 'commando');
  });
}
