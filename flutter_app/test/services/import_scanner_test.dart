// The downloads scan, against a real temp directory with real zips.
//
// The zip half is the reason this feature exists: C64 files essentially
// always arrive compressed, and until now nothing in the app could see
// inside one.
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vice_multiplatform/services/import_scanner.dart';

void main() {
  late Directory downloads;
  late Directory library;

  setUp(() {
    downloads = Directory.systemTemp.createTempSync('vice_scan_src');
    library = Directory.systemTemp.createTempSync('vice_scan_dst');
  });

  tearDown(() {
    downloads.deleteSync(recursive: true);
    library.deleteSync(recursive: true);
  });

  void writeFile(String relative, String contents) {
    final file = File(p.join(downloads.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  /// A real zip, so the decoder is genuinely exercised.
  void writeZip(String name, Map<String, String> entries) {
    final archive = Archive();
    entries.forEach((path, contents) {
      final bytes = contents.codeUnits;
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    });
    File(p.join(downloads.path, name))
        .writeAsBytesSync(ZipEncoder().encode(archive));
  }

  test('finds loose media, at any depth, and ignores everything else', () async {
    writeFile('Paradroid.d64', 'disk');
    writeFile('tunes/Commando.sid', 'psid');
    writeFile('notes.txt', 'not a game');
    writeFile('cover.jpg', 'not a game');

    final found = await ImportScanner.scanDirectory(downloads.path);

    expect(found.map((c) => c.name), ['Commando.sid', 'Paradroid.d64']);
    expect(found.every((c) => !c.isInArchive), isTrue);
  });

  test('looks inside zips, which is how these files actually arrive',
      () async {
    writeZip('hewson.zip', {
      'Uridium.d64': 'disk',
      'docs/readme.txt': 'not a game',
      'music/Nemesis.sid': 'psid',
    });

    final found = await ImportScanner.scanDirectory(downloads.path);

    expect(found.map((c) => c.name), ['Nemesis.sid', 'Uridium.d64']);
    expect(found.every((c) => c.isInArchive), isTrue);
    expect(found.first.sourceLabel, 'in hewson.zip');
  });

  test('a corrupt zip costs that zip, not the scan', () async {
    writeFile('broken.zip', 'this is not a zip at all');
    writeFile('Paradroid.d64', 'disk');

    final found = await ImportScanner.scanDirectory(downloads.path);

    expect(found.map((c) => c.name), ['Paradroid.d64']);
  });

  test('imports loose files and zip entries alike into the library',
      () async {
    writeFile('Paradroid.d64', 'disk-bytes');
    writeZip('hewson.zip', {'sub/Uridium.d64': 'zipped-bytes'});

    final found = await ImportScanner.scanDirectory(downloads.path);
    final imported = await ImportScanner.importAll(found, library.path);

    expect(imported.length, 2);
    expect(
      library.listSync().map((e) => p.basename(e.path)).toList()..sort(),
      ['Paradroid.d64', 'Uridium.d64'],
    );
    // Extracted, not just referenced -- the zip may be deleted afterwards.
    expect(File(p.join(library.path, 'Uridium.d64')).readAsStringSync(),
        'zipped-bytes');
    // Flattened: the zip's own folders are not recreated in the library.
    expect(Directory(p.join(library.path, 'sub')).existsSync(), isFalse);
  });

  test('an import never overwrites a title already in the library', () async {
    File(p.join(library.path, 'Paradroid.d64')).writeAsStringSync('the one I had');
    writeFile('Paradroid.d64', 'the new one');

    final found = await ImportScanner.scanDirectory(downloads.path);
    await ImportScanner.importAll(found, library.path);

    expect(File(p.join(library.path, 'Paradroid.d64')).readAsStringSync(),
        'the one I had');
    expect(File(p.join(library.path, 'Paradroid (2).d64')).readAsStringSync(),
        'the new one');
  });

  test('a missing folder scans to nothing rather than throwing', () async {
    final found =
        await ImportScanner.scanDirectory(p.join(downloads.path, 'nope'));
    expect(found, isEmpty);
  });
}
