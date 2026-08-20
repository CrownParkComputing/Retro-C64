// Which tune the app reaches for.
//
// Shared by the Music tab and the workbench backdrop, so the rule has to be
// stable: both must pick the same tune, and the pick must not depend on how
// the filesystem happens to sort a directory.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_c64/services/music_library.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('musiclib'));
  tearDown(() => dir.deleteSync(recursive: true));

  void write(String name) =>
      File(p.join(dir.path, name)).writeAsBytesSync([0x50, 0x53, 0x49, 0x44]);

  test('nothing installed means nothing to play', () {
    expect(MusicLibrary.firstAvailable([dir.path]), isNull);
  });

  test('picks the first PLAYLIST entry present, not the first file found', () {
    // Delta is earlier in the playlist than Warhawk; writing Warhawk first
    // means directory order and playlist order disagree, which is the whole
    // point of the test.
    write('Warhawk.sid');
    write('Delta.sid');

    final pick = MusicLibrary.firstAvailable([dir.path]);
    expect(pick, isNotNull);
    expect(pick!.$1, 'Delta');
    expect(pick.$2, p.join(dir.path, 'Delta.sid'));
  });

  test('the same tune comes back every time', () {
    write('Warhawk.sid');
    write('Delta.sid');
    final a = MusicLibrary.firstAvailable([dir.path]);
    final b = MusicLibrary.firstAvailable([dir.path]);
    expect(a!.$2, b!.$2);
  });

  test('earlier directories win', () {
    final second = Directory.systemTemp.createTempSync('musiclib2');
    addTearDown(() => second.deleteSync(recursive: true));
    File(p.join(dir.path, 'Delta.sid')).writeAsBytesSync([1]);
    File(p.join(second.path, 'Delta.sid')).writeAsBytesSync([2]);

    // A curated Music/ folder is searched before the importer's copy, so the
    // user's own file must be the one that plays.
    expect(MusicLibrary.resolve('Delta.sid', [dir.path, second.path]),
        p.join(dir.path, 'Delta.sid'));
  });

  test('a file not in the playlist is ignored by the picker', () {
    write('SomeRandomTune.sid');
    expect(MusicLibrary.firstAvailable([dir.path]), isNull);
  });

  test('titleForPath maps a file back to its playlist name', () {
    expect(MusicLibrary.titleForPath('/anywhere/Comic_Bakery.sid'),
        'Comic Bakery');
    expect(MusicLibrary.titleForPath('/anywhere/NotAPlaylistTune.sid'), isNull);
  });
}
