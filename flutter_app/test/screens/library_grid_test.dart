// The games library is browsed by TITLE: one shelf in alphabetical order
// with an A-Z row over it. The old per-format tabs are gone -- which file
// format a title is stored in is not how anyone looks for a game -- so what
// these tests pin is the letter row: it only offers letters some title
// actually starts with, '#' collects everything non-alphabetic, and the
// selected letter and the search box compose.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_c64/data/category.dart';
import 'package:retro_c64/data/media_entry.dart';
import 'package:retro_c64/screens/library_grid.dart';

void main() {
  MediaEntry entry(String name) => MediaEntry(
        displayName: name,
        path: '/games/$name',
        mediaType: MediaEntry.filterForExtension(name.split('.').last),
      );

  final library = [
    entry('Boulder Dash.d64'),
    entry('Uridium.d64'),
    entry('Wizball.g64'),
    entry('IK+.t64'),
    entry('Rambo.tap'),
    entry('International Karate.crt'),
    entry('hello world.prg'),
    entry('1942.prg'),
  ];

  Future<List<MediaEntry>> pumpLibrary(
    WidgetTester tester, {
    List<MediaEntry>? entries,
  }) async {
    final launched = <MediaEntry>[];
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LibraryGrid(
          allEntries: entries ?? library,
          onLaunch: launched.add,
        ),
      ),
    ));
    return launched;
  }

  testWidgets('opens on the whole shelf, no format tabs', (tester) async {
    await pumpLibrary(tester);

    expect(find.text('Game Library'), findsOneWidget);
    expect(find.text('8 of 8 files'), findsOneWidget);
    // The format tabs this view used to open on are gone for good -- the
    // enum itself went with them.
    // 'PRG' is excluded: it appears on media-card kind badges.
    for (final label in ['All', 'Disks', 'Tapes', 'Carts']) {
      expect(find.text(label), findsNothing);
    }
    // Every title is on screen at once.
    expect(find.text('Boulder Dash'), findsOneWidget);
    expect(find.text('hello world'), findsOneWidget);
  });

  testWidgets('the A-Z row offers only letters in use, plus # for the rest',
      (tester) async {
    await pumpLibrary(tester);

    // Present: 1942 -> '#', Boulder Dash, hello world, IK+, International
    // Karate, Rambo, Uridium, Wizball.
    for (final l in ['#', 'B', 'H', 'I', 'R', 'U', 'W']) {
      expect(find.widgetWithText(Container, l), findsOneWidget,
          reason: 'letter $l should have a tile');
    }
    for (final l in ['A', 'C', 'Z']) {
      expect(find.widgetWithText(Container, l), findsNothing,
          reason: 'no title starts with $l');
    }
  });

  testWidgets('picking a letter shows only titles starting with it',
      (tester) async {
    await pumpLibrary(tester);

    await tester.tap(find.widgetWithText(Container, 'I'));
    await tester.pumpAndSettle();

    expect(find.text('IK+'), findsOneWidget);
    expect(find.text('International Karate'), findsOneWidget);
    expect(find.text('Boulder Dash'), findsNothing);
    expect(find.text('2 of 8 files'),
        findsOneWidget);

    // Tapping the same letter again clears it -- the row is a filter, not a
    // mode you have to find your way out of.
    await tester.tap(find.widgetWithText(Container, 'I'));
    await tester.pumpAndSettle();
    expect(find.text('Boulder Dash'), findsOneWidget);
  });

  testWidgets('# collects the titles that do not start with a letter',
      (tester) async {
    await pumpLibrary(tester);

    await tester.tap(find.widgetWithText(Container, '#'));
    await tester.pumpAndSettle();

    expect(find.text('1942'), findsOneWidget);
    expect(find.text('Boulder Dash'), findsNothing);
  });

  testWidgets('the search box composes with the selected letter',
      (tester) async {
    await pumpLibrary(tester);
    await tester.tap(find.widgetWithText(Container, 'I'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'karate');
    // Search debounces 150 ms.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    // Case-insensitive, and it narrows within the letter rather than
    // replacing it: IK+ starts with I but does not match "karate".
    expect(find.text('International Karate'), findsOneWidget);
    expect(find.text('IK+'), findsNothing);
    expect(find.text('1 of 8 files'),
        findsOneWidget);
  });

  testWidgets('a letter with nothing left after a search says so',
      (tester) async {
    await pumpLibrary(tester);
    await tester.enterText(find.byType(TextField), 'nothing matches this');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('No media in this category.'), findsOneWidget);
  });

  testWidgets('an empty library explains which formats are supported',
      (tester) async {
    await pumpLibrary(tester, entries: []);
    expect(
      find.text('No C64 media found. Supported: PRG, P00, D64, G64, D71, '
          'D81, TAP, T64, CRT.'),
      findsOneWidget,
    );
  });

  testWidgets('tapping a tile launches that exact entry', (tester) async {
    final launched = await pumpLibrary(tester);
    await tester.tap(find.text('Uridium'));
    await tester.pumpAndSettle();

    expect(launched.single.path, '/games/Uridium.d64');
    expect(launched.single.mediaType, MediaFormatFilter.disk);
  });
}
