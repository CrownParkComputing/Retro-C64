import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_c64/services/drop_folders.dart';

void main() {
  late Directory docs;

  setUp(() => docs = Directory.systemTemp.createTempSync('drop_folders_test'));
  tearDown(() => docs.deleteSync(recursive: true));

  test('creates every drop folder with a note inside', () async {
    final created = await DropFolders.create(docs.path);

    expect(created, ['ROMs', 'Games', 'Music']);
    for (final folder in DropFolders.folders) {
      final dir = Directory(p.join(docs.path, folder.name));
      expect(dir.existsSync(), isTrue, reason: folder.name);
      final note = File(p.join(dir.path, DropFolders.readmeName));
      expect(note.existsSync(), isTrue, reason: '${folder.name} note');
      expect(note.readAsStringSync(), isNotEmpty);
    }
  });

  test('running again creates nothing new and does not throw', () async {
    await DropFolders.create(docs.path);
    final second = await DropFolders.create(docs.path);

    expect(second, isEmpty);
  });

  test('a stale note is rewritten rather than duplicated', () async {
    await DropFolders.create(docs.path);
    final note = File(p.join(docs.path, 'ROMs', DropFolders.readmeName))
      ..writeAsStringSync('wording from an older version');

    await DropFolders.create(docs.path);

    expect(note.readAsStringSync(), contains('kernal'));
    expect(Directory(p.join(docs.path, 'ROMs')).listSync().length, 1);
  });

  test('files the user already dropped are left alone', () async {
    await DropFolders.create(docs.path);
    final game = File(p.join(docs.path, 'Games', 'Uridium.d64'))
      ..writeAsStringSync('C64');

    await DropFolders.create(docs.path);

    expect(game.existsSync(), isTrue);
  });

  test('reports which folders exist', () async {
    expect(DropFolders.existing(docs.path), isEmpty);
    Directory(p.join(docs.path, 'Music')).createSync();

    expect(DropFolders.existing(docs.path), ['Music']);
  });
}
