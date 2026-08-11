// The SID Workstation's playlist is not just the bundled twenty: anything
// the user has of their own has to show up too. On iOS that is the only way
// a SID can get in at all -- there is no music folder to point at, just the
// import directory the wizard and the Paths tab copy into.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vice_multiplatform/screens/music_screen.dart';
import 'package:vice_multiplatform/services/storage_access.dart';

import '../fakes/fake_storage_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late Directory imports;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('vice_music_test');
    imports = Directory(p.join(sandbox.path, 'games'))..createSync();
    SharedPreferences.setMockInitialValues({});
    StorageAccess.setInstanceForTesting(
        FakeFileImportStorage(importDir: sandbox.path));
  });

  tearDown(() {
    StorageAccess.setInstanceForTesting(null);
    sandbox.deleteSync(recursive: true);
  });

  Future<void> pumpMusic(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MusicScreen())));
    // The track load awaits the bundled-SID extraction, which goes through a
    // platform channel (and fails, no plugins here). A channel reply only
    // arrives under real async, so pump() alone would leave the screen
    // waiting forever on it -- hence runAsync, then a pump to rebuild.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  testWidgets('an imported SID joins the playlist', (tester) async {
    File(p.join(imports.path, 'Ghosts_n_Goblins.sid')).writeAsStringSync('PSID');
    await pumpMusic(tester);

    // Titled from the filename, since that is all an imported SID carries.
    expect(find.text('Ghosts n Goblins'), findsOneWidget);
    expect(find.textContaining('${MusicScreen.playlist.length + 1} tunes'),
        findsOneWidget);
  });

  testWidgets('imported files that are not SIDs stay out of the playlist',
      (tester) async {
    // The import directory holds games as well -- it is the same folder.
    File(p.join(imports.path, 'Paradroid.d64')).writeAsStringSync('C64');
    await pumpMusic(tester);

    expect(find.text('Paradroid'), findsNothing);
    expect(find.textContaining('${MusicScreen.playlist.length} tunes'),
        findsOneWidget);
  });
}
