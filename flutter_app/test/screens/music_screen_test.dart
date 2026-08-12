// Opening the Music tab has to make a sound.
//
// The tab shipped playing nothing until a card was tapped, and nothing on
// screen said a tap was needed -- with most cards greyed out as "not
// downloaded", the one playable tune could be anywhere in the grid. These
// tests pin the three behaviours that fix costs: it starts something, it
// starts something that actually exists, and it does not restart a tune that
// is already playing when the tab is re-entered.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vice_multiplatform/screens/music_screen.dart';
import 'package:vice_multiplatform/services/vsid_service.dart';

/// Records what the screen asked the core to do. The native core can't be
/// loaded in a test process, so every method the screen touches is faked.
class _FakeVsid extends VsidService {
  _FakeVsid() : super.forTesting();

  final List<String> played = [];
  String? _path;
  bool _paused = false;

  @override
  Future<bool> ensureLoaded() async => true;

  @override
  bool play(String sidPath) {
    played.add(sidPath);
    _path = sidPath;
    _paused = false;
    return true;
  }

  @override
  void togglePause() => _paused = !_paused;

  @override
  String? get currentPath => _path;

  @override
  bool get isRunning => _path != null && !_paused;

  @override
  bool get isPaused => _paused;

  @override
  String? get loadError => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory music;
  late _FakeVsid vsid;
  final realVsid = VsidService.instance;

  setUp(() {
    // The screen looks for a Music/ directory beside the games folder.
    root = Directory.systemTemp.createTempSync('vice_music_test');
    Directory(p.join(root.path, 'Games')).createSync();
    music = Directory(p.join(root.path, 'Music'))..createSync();

    SharedPreferences.setMockInitialValues({
      'setup_completed': true,
      'games_folder_path': p.join(root.path, 'Games'),
    });

    vsid = _FakeVsid();
    VsidService.instance = vsid;
  });

  tearDown(() {
    VsidService.instance = realVsid;
    root.deleteSync(recursive: true);
  });

  Future<void> pumpMusic(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // runAsync, not a pump loop. Resolving the music folders goes through
    // SharedPreferences and a path_provider call that throws
    // MissingPluginException in a test process, and both are real
    // platform-channel round trips: under testWidgets' fake clock they never
    // complete, the screen stays on "Loading...", and every assertion here
    // fails for a reason that has nothing to do with autoplay.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MusicScreen())),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    // Paint the resolved state. pumpAndSettle is unusable -- the screen polls
    // the core on a 300ms timer that never stops.
    await tester.pump();
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  testWidgets('starts a tune on open, without waiting for a tap',
      (tester) async {
    File(p.join(music.path, 'Commando.sid')).writeAsStringSync('PSID');

    await pumpMusic(tester);

    expect(vsid.played, [p.join(music.path, 'Commando.sid')]);
    expect(find.textContaining('PLAYING -- Commando'), findsOneWidget);
  });

  testWidgets('skips playlist entries whose file is not present',
      (tester) async {
    // Commando is first in the playlist but absent; Delta is present. The
    // bug this guards against is autoplay picking playlist[0] blindly and
    // then reporting a failure for a file nobody has.
    File(p.join(music.path, 'Delta.sid')).writeAsStringSync('PSID');

    await pumpMusic(tester);

    expect(vsid.played, [p.join(music.path, 'Delta.sid')]);
  });

  testWidgets('plays nothing, and reports nothing, when no SIDs exist',
      (tester) async {
    await pumpMusic(tester);

    expect(vsid.played, isEmpty);
    // The grid already shows every card as "not downloaded"; an error line
    // on top of that would be noise.
    expect(find.textContaining('unavailable'), findsNothing);
    expect(find.textContaining('Failed'), findsNothing);
    expect(find.text('No track loaded'), findsOneWidget);
  });

  testWidgets('re-entering the tab adopts the playing tune, does not restart',
      (tester) async {
    File(p.join(music.path, 'Commando.sid')).writeAsStringSync('PSID');

    await pumpMusic(tester);
    expect(vsid.played, hasLength(1));

    // Leaving the Music category disposes the widget entirely (WorkbenchScreen
    // rebuilds it from a switch), while the core keeps playing.
    await tester.pumpWidget(const SizedBox());
    await pumpMusic(tester);

    expect(vsid.played, hasLength(1), reason: 'must not restart the tune');
    expect(find.textContaining('PLAYING -- Commando'), findsOneWidget);
  });
}
