// Scanning a real (temporary) folder tree. No device, no game files in the
// repo -- the fixtures are written here and thrown away again.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vice_multiplatform/data/category.dart';
import 'package:vice_multiplatform/services/library_scanner.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('vice_scan_test'));
  tearDown(() => root.deleteSync(recursive: true));

  File write(String relativePath, {String contents = 'C64'}) {
    final file = File(p.join(root.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
    return file;
  }

  List<String> namesOf(LibraryScanResult r) =>
      r.entries.map((e) => e.displayName).toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  test('finds media in subfolders, at any depth', () {
    // The bug this exists for: the scan was non-recursive, so anyone who
    // filed their games in per-publisher folders had an empty library.
    write('top.d64');
    write('Hewson/Uridium.d64');
    write('Hewson/Nebulus/nebulus.prg');
    write('a/b/c/d/deep.t64');

    final result = LibraryScanner.scan(root.path);

    expect(namesOf(result),
        ['deep.t64', 'nebulus.prg', 'top.d64', 'Uridium.d64']);
    expect(result.unreadableCount, 0);
  });

  test('classifies each file by its extension and skips the rest', () {
    write('game.d64');
    write('game.tap');
    write('game.crt');
    write('game.prg');
    write('notes.txt');
    write('cover.png');
    write('tune.sid'); // Music tab's job, not the games library
    write('noextension');

    final result = LibraryScanResult(
      entries: LibraryScanner.scan(root.path).entries.toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName)),
      unreadableCount: 0,
    );

    expect(result.entries.map((e) => e.mediaType).toList(), [
      MediaFormatFilter.cartridge,
      MediaFormatFilter.disk,
      MediaFormatFilter.prg,
      MediaFormatFilter.tape,
    ]);
    expect(result.entries.every((e) => File(e.path).existsSync()), isTrue);
  });

  test('a missing folder scans to an empty library, not a crash', () {
    final result = LibraryScanner.scan(p.join(root.path, 'nope'));
    expect(result.entries, isEmpty);
    expect(result.unreadableCount, 0);
  });

  test('counts, rather than lists, media it cannot read', () {
    // Android scoped storage lists files the app cannot open; each one
    // would otherwise launch into a blank screen.
    write('good.d64');
    write('empty.d64', contents: '');

    final result = LibraryScanner.scan(root.path);

    expect(namesOf(result), ['good.d64']);
    expect(result.unreadableCount, 1);
  });

  test('isReadable is false for a file that is not there', () {
    expect(LibraryScanner.isReadable(File(p.join(root.path, 'gone.d64'))),
        isFalse);
  });
}
