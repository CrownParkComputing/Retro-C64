// The downloads-scan modal, end to end: open it on a folder, see what it
// found (including inside a zip), import the ticked ones, and have them
// land in the library.
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vice_multiplatform/screens/import_scan_dialog.dart';
import 'package:vice_multiplatform/services/storage_access.dart';

import '../fakes/fake_storage_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory downloads;
  late Directory sandbox;
  late Directory library;

  setUp(() {
    downloads = Directory.systemTemp.createTempSync('vice_dialog_src');
    sandbox = Directory.systemTemp.createTempSync('vice_dialog_dst');
    library = Directory(p.join(sandbox.path, 'games'))..createSync();
    SharedPreferences.setMockInitialValues({});
    StorageAccess.setInstanceForTesting(
        FakeFileImportStorage(importDir: sandbox.path));
  });

  tearDown(() {
    StorageAccess.setInstanceForTesting(null);
    downloads.deleteSync(recursive: true);
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  testWidgets('scans a folder, zips included, and imports what is ticked',
      (tester) async {
    File(p.join(downloads.path, 'Paradroid.d64')).writeAsStringSync('disk');
    final archive = Archive()
      ..addFile(ArchiveFile('tunes/Nemesis.sid', 4, 'psid'.codeUnits));
    File(p.join(downloads.path, 'hubbard.zip'))
        .writeAsBytesSync(ZipEncoder().encode(archive));

    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    int? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showImportScanDialog(context,
                initialDirectory: downloads.path);
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    // The scan itself is real file I/O; let it land, then rebuild.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    // Both are listed, and the zipped one says where it came from.
    expect(find.text('Paradroid.d64'), findsOneWidget);
    expect(find.text('Nemesis.sid'), findsOneWidget);
    expect(find.textContaining('in hubbard.zip'), findsOneWidget);
    // Games and tunes are counted separately, since they land in different
    // halves of the app.
    expect(find.textContaining('1 game(s), 1 tune(s)'), findsOneWidget);

    await tester.tap(find.text('Import 2'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    expect(result, 2);
    expect(
      library.listSync().map((e) => p.basename(e.path)).toList()..sort(),
      ['Nemesis.sid', 'Paradroid.d64'],
    );
  });

  testWidgets('says so when a folder holds nothing playable', (tester) async {
    File(p.join(downloads.path, 'invoice.pdf')).writeAsStringSync('nope');

    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showImportScanDialog(context,
              initialDirectory: downloads.path),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    expect(find.textContaining('Nothing playable found'), findsOneWidget);
    expect(find.text('Import 0'), findsOneWidget);
  });
}
