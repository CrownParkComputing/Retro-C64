// The Resume tab.
//
// It shipped as a `const` placeholder that always said "No game in
// progress", including while a game really was loaded in the background --
// the one case the tab exists for. These tests are about it reporting REAL
// state: the live session, the saved ones, and the difference between a
// session that can be resumed and one that can only be restarted.
//
// The saved sessions are injected rather than read from the application
// support directory: widget tests run on a fake clock, under which real
// filesystem I/O never completes. The on-disk index format is covered by
// test/services/save_state_service_test.dart instead.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_c64/data/category.dart';
import 'package:retro_c64/screens/resume_screen.dart';
import 'package:retro_c64/services/save_state_service.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('vice_resume_test'));
  tearDown(() => temp.deleteSync(recursive: true));

  /// A snapshot file that really exists, so canResume is true.
  String snapshotFile(String name) =>
      (File(p.join(temp.path, name))..writeAsBytesSync([0, 1, 2])).path;

  SaveStateEntry session(
    String title, {
    String? snapshotPath,
    String? unsupportedReason,
    DateTime? savedAt,
  }) =>
      SaveStateEntry(
        title: title,
        mediaPath: '/games/$title',
        mediaType: MediaFormatFilter.disk,
        snapshotPath: snapshotPath,
        unsupportedReason: unsupportedReason,
        savedAt: savedAt ?? DateTime.now(),
      );

  final deleted = <SaveStateEntry>[];
  final resumedSaved = <SaveStateEntry>[];
  var resumedCurrent = 0;

  setUp(() {
    deleted.clear();
    resumedSaved.clear();
    resumedCurrent = 0;
  });

  Future<void> pumpResume(
    WidgetTester tester, {
    String? currentTitle,
    List<SaveStateEntry> saved = const [],
  }) async {
    final entries = [...saved];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ResumeScreen(
          currentTitle: currentTitle,
          onResumeCurrent: () => resumedCurrent++,
          onResumeSaved: (entry) async => resumedSaved.add(entry),
          loadSaved: () async =>
              entries.toList()..sort((a, b) => b.savedAt.compareTo(a.savedAt)),
          deleteSaved: (entry) async {
            deleted.add(entry);
            entries.removeWhere((e) => e.title == entry.title);
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the live session by name, not a fixed string',
      (tester) async {
    await pumpResume(tester, currentTitle: 'Boulder Dash.d64');

    expect(find.text('IN PROGRESS'), findsOneWidget);
    expect(find.text('Boulder Dash.d64'), findsOneWidget);
    expect(find.text('RESUME'), findsOneWidget);
    // The placeholder's line, which used to show unconditionally.
    expect(find.textContaining('No game in progress'), findsNothing);
  });

  testWidgets('says nothing is in progress only when nothing is',
      (tester) async {
    await pumpResume(tester, currentTitle: null);
    expect(find.text('IN PROGRESS'), findsNothing);
    expect(find.textContaining('Nothing saved yet'), findsOneWidget);
  });

  testWidgets('resuming the live session calls straight back', (tester) async {
    await pumpResume(tester, currentTitle: 'Uridium.d64');
    await tester.tap(find.text('Uridium.d64'));
    await tester.pumpAndSettle();
    expect(resumedCurrent, 1);
  });

  testWidgets('lists saved sessions newest first', (tester) async {
    await pumpResume(tester, saved: [
      session('Old.d64',
          snapshotPath: snapshotFile('old.vsf'),
          savedAt: DateTime.now().subtract(const Duration(days: 2))),
      session('New.d64',
          snapshotPath: snapshotFile('new.vsf'),
          savedAt: DateTime.now().subtract(const Duration(minutes: 5))),
    ]);

    expect(tester.getTopLeft(find.text('New.d64')).dy,
        lessThan(tester.getTopLeft(find.text('Old.d64')).dy));
    expect(find.text('Saved 5m ago'), findsOneWidget);
    expect(find.text('Saved 2d ago'), findsOneWidget);
  });

  testWidgets('a session with no snapshot says RESTART, and says why',
      (tester) async {
    await pumpResume(tester, saved: [
      session('Tape Game.t64',
          unsupportedReason: 'Tape images cannot be snapshotted.',
          savedAt: DateTime.now()),
      session('Disk Game.d64',
          snapshotPath: snapshotFile('disk.vsf'),
          savedAt: DateTime.now().subtract(const Duration(hours: 1))),
    ]);

    // The most important pair of words on this screen: tapping a
    // restart-only row really does start the game from the beginning, so it
    // must not promise a resume.
    expect(find.text('RESTART'), findsOneWidget);
    expect(find.text('RESUME'), findsOneWidget);
    expect(find.text('Tape images cannot be snapshotted.'), findsOneWidget);
  });

  testWidgets('a snapshot that has vanished is offered as a RESTART',
      (tester) async {
    // The index still lists it; the file is gone from disk.
    await pumpResume(tester, saved: [
      session('Ghost.d64', snapshotPath: p.join(temp.path, 'gone.vsf')),
    ]);

    expect(find.text('Ghost.d64'), findsOneWidget);
    expect(find.text('RESTART'), findsOneWidget);
    expect(find.text('RESUME'), findsNothing);
  });

  testWidgets('tapping a saved session resumes that one', (tester) async {
    await pumpResume(tester, saved: [
      session('Wizball.d64', snapshotPath: snapshotFile('w.vsf')),
    ]);
    await tester.tap(find.text('Wizball.d64'));
    await tester.pumpAndSettle();
    expect(resumedSaved.single.title, 'Wizball.d64');
  });

  testWidgets('with a live session AND saved ones, both are listed',
      (tester) async {
    await pumpResume(
      tester,
      currentTitle: 'Live.d64',
      saved: [session('Earlier.d64', snapshotPath: snapshotFile('e.vsf'))],
    );
    expect(find.text('IN PROGRESS'), findsOneWidget);
    expect(find.text('Live.d64'), findsOneWidget);
    expect(find.text('SAVED SESSIONS'), findsOneWidget);
    expect(find.text('Earlier.d64'), findsOneWidget);
  });

  testWidgets('deleting a saved session removes it from the list',
      (tester) async {
    await pumpResume(tester, saved: [
      session('Doomed.d64', snapshotPath: snapshotFile('d.vsf')),
    ]);
    expect(find.text('Doomed.d64'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(deleted.single.title, 'Doomed.d64');
    expect(find.text('Doomed.d64'), findsNothing);
  });
}
