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
import 'package:retro_c64/screens/emulator_screen.dart';
import 'package:retro_c64/screens/workbench_screen.dart';
import 'package:retro_c64/widgets/sidebar.dart';
import 'package:retro_c64/services/platform_info.dart';

import 'package:retro_c64/services/vsid_service.dart';

import '../fakes/fake_vice_core.dart';

/// Records what the workbench asked of the SID player.
class _FakeVsid extends VsidService {
  _FakeVsid() : super.forTesting();
  int pauseCalls = 0;
  final String _path = '/music/Commando.sid';
  @override
  Future<bool> ensureLoaded() async => true;
  @override
  void pause() => pauseCalls++;
  @override
  String? get currentPath => _path;
  @override
  bool get isRunning => true;
  @override
  bool get isPaused => false;
}

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
    // No 'Audio': its one control (workbench music) lives on the Music page
    // now, which is where the tunes it governs are.
    for (final label in ['Resume', 'Games', 'Music', 'Paths', 'Video',
      'Input', 'About']) {
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
    // The session renders INSIDE the shell now, not over it: the rail and
    // the status bar survive the launch, and the status bar is the ONE place
    // the loaded title is named.
    expect(find.text('Boulder Dash.d64'), findsOneWidget);
    expect(find.byType(Sidebar), findsOneWidget);
  });

  testWidgets('the in-game strip offers Pause and no Close', (tester) async {
    // There is exactly one way out of a session, and it keeps your place.
    // A close button that dropped the session without a snapshot answered a
    // question the rolling save states already answer.
    await pumpWorkbench(tester, FakeViceCore(isRunning: false));
    await tester.tap(find.text('Boulder Dash'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.byTooltip('Pause and return to the workbench'), findsOneWidget);
    expect(find.byTooltip('Close the game'), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('picking a different title ends the running one', (tester) async {
    final core = FakeViceCore(isRunning: false);
    await pumpWorkbench(tester, core);

    await tester.tap(find.text('Boulder Dash'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(core.startCount, 1);

    // Back to the shelf and straight into a second game. The core is handed
    // the new media, which detaches the old one and resets -- the first game
    // is not left running underneath.
    await tester.tap(find.text('Games'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Uridium'), findsOneWidget, reason: 'back on the shelf');
    await tester.tap(find.text('Uridium'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.textContaining('Disk images need'), findsNothing);
    expect(find.textContaining('Cannot read'), findsNothing);

    expect(core.startCount, 2);
    expect(core.startedPaths.last, endsWith('Uridium.d64'));
    expect(find.text('Uridium.d64'), findsOneWidget);
    expect(find.text('Boulder Dash.d64'), findsNothing);
  });

  testWidgets('launching a game silences the workbench music', (tester) async {
    // Every route into the emulator must stop the tune, not just this one:
    // the workbench resumes its music on the way back, so a route that
    // forgets leaves the SID player audible underneath the game.
    final real = VsidService.instance;
    final vsid = _FakeVsid();
    VsidService.instance = vsid;
    addTearDown(() => VsidService.instance = real);

    await pumpWorkbench(tester, FakeViceCore(isRunning: false));
    await tester.tap(find.text('Boulder Dash'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(vsid.pauseCalls, greaterThan(0),
        reason: 'the SID player should have been paused for the game');
  });
}
