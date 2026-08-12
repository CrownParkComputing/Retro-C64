// The workbench shell, over a fake core: the library it scans, the sidebar
// it navigates with, and handing a title to the emulator screen.
//
// This is the closest thing here to an integration test -- it wires the
// real scan, the real grid and the real emulator screen together, with only
// the native core faked.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vice_multiplatform/screens/emulator_screen.dart';
import 'package:vice_multiplatform/screens/workbench_screen.dart';
import 'package:vice_multiplatform/services/platform_info.dart';

import '../fakes/fake_vice_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory games;

  setUp(() {
    games = Directory.systemTemp.createTempSync('vice_workbench_test');
    File(p.join(games.path, 'Boulder Dash.d64')).writeAsStringSync('C64');
    // In a subfolder, which is where the non-recursive scan used to lose it.
    Directory(p.join(games.path, 'Hewson')).createSync();
    File(p.join(games.path, 'Hewson', 'Uridium.d64')).writeAsStringSync('C64');
    File(p.join(games.path, 'notes.txt')).writeAsStringSync('not a game');

    SharedPreferences.setMockInitialValues({
      'setup_completed': true,
      'games_folder_path': games.path,
    });
  });

  tearDown(() => games.deleteSync(recursive: true));

  Future<void> pumpWorkbench(WidgetTester tester, FakeViceCore core) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: WorkbenchScreen(core: core)));
    // The library scan and the input prefs are read asynchronously; a few
    // frames let them land. pumpAndSettle is not usable here -- the animated
    // C64 backdrop never stops.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  testWidgets('lists the configured games folder, subfolders included',
      (tester) async {
    await pumpWorkbench(tester, FakeViceCore());

    expect(find.text('Boulder Dash'), findsOneWidget);
    expect(find.text('Uridium'), findsOneWidget);
    expect(find.text('notes'), findsNothing);
  });

  testWidgets('the sidebar offers every workbench destination',
      (tester) async {
    await pumpWorkbench(tester, FakeViceCore());
    for (final label in ['Resume', 'Games', 'Music', 'Paths', 'Video',
      'Audio', 'Input', 'About']) {
      expect(find.text(label), findsWidgets, reason: '$label sidebar entry');
    }
  });

  testWidgets('About names the platform this copy is running on',
      (tester) async {
    await pumpWorkbench(tester, FakeViceCore());
    await tester.tap(find.text('About'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.textContaining(platformName()), findsWidgets);
  });

  testWidgets('launching a title starts the core and shows the emulator',
      (tester) async {
    final core = FakeViceCore(isRunning: false);
    await pumpWorkbench(tester, core);

    // Boulder Dash is a .d64, so this also covers the drive-ROM guard failing
    // OPEN: the check needs the app support directory, which no test process
    // has, and a guard that blocked on a failed check would stop the launch
    // here. Whether it blocks when the ROM is genuinely absent is covered at
    // the predicate level, in test/ffi/rom_detection_test.dart.
    await tester.tap(find.text('Boulder Dash'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(core.startCount, 1);
    expect(find.byType(EmulatorScreen), findsOneWidget);
    // The title is named on the emulator screen, so it is obvious what is
    // loaded.
    expect(find.text('Boulder Dash.d64'), findsOneWidget);
  });
}
