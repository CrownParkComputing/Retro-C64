// The games library: the tabs are filters over ONE library, and each one
// has to show exactly the titles of its format -- an empty tab that should
// have had games in it looks identical to a genuinely empty one.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vice_multiplatform/data/category.dart';
import 'package:vice_multiplatform/data/media_entry.dart';
import 'package:vice_multiplatform/screens/library_grid.dart';

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

  testWidgets('opens on All, grouped into a section per format',
      (tester) async {
    await pumpLibrary(tester);

    expect(find.text('Game Library'), findsOneWidget);
    expect(find.text('7 of 7 files | IGDB deferred (placeholder tiles)'),
        findsOneWidget);
    // Section headers, upper-cased by the header widget.
    for (final section in ['DISK IMAGES', 'TAPE IMAGES', 'CARTRIDGES',
      'PROGRAMS']) {
      expect(find.text(section), findsOneWidget);
    }
    // Every title is on screen at once.
    expect(find.text('Boulder Dash'), findsOneWidget);
    expect(find.text('hello world'), findsOneWidget);
  });

  testWidgets('each tab shows only its own format', (tester) async {
    await pumpLibrary(tester);

    Future<void> openTab(String label) async {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await openTab('💾 Disks');
    expect(find.text('Disk Images'), findsOneWidget);
    // d64 AND g64 are both disks.
    expect(find.text('Boulder Dash'), findsOneWidget);
    expect(find.text('Wizball'), findsOneWidget);
    expect(find.text('IK+'), findsNothing);
    expect(find.text('3 of 7 files | IGDB deferred (placeholder tiles)'),
        findsOneWidget);

    await openTab('📼 Tapes');
    expect(find.text('IK+'), findsOneWidget);
    expect(find.text('Rambo'), findsOneWidget);
    expect(find.text('Boulder Dash'), findsNothing);

    await openTab('🕹️ Carts');
    expect(find.text('International Karate'), findsOneWidget);
    expect(find.text('Rambo'), findsNothing);

    await openTab('⌨️ PRG');
    expect(find.text('hello world'), findsOneWidget);
    expect(find.text('International Karate'), findsNothing);
  });

  testWidgets('the search box filters within the selected tab',
      (tester) async {
    await pumpLibrary(tester);
    await tester.tap(find.text('💾 Disks'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'boulder');
    await tester.pumpAndSettle();

    expect(find.text('Boulder Dash'), findsOneWidget);
    expect(find.text('Uridium'), findsNothing);
    // Search is case-insensitive; the count reflects the search, the tab
    // pill count does not.
    expect(find.text('1 of 7 files | IGDB deferred (placeholder tiles)'),
        findsOneWidget);
  });

  testWidgets('an empty tab says so rather than looking broken',
      (tester) async {
    await pumpLibrary(tester, entries: [entry('Boulder Dash.d64')]);
    await tester.tap(find.text('📼 Tapes'));
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
    await tester.tap(find.text('💾 Disks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uridium'));
    await tester.pumpAndSettle();

    expect(launched.single.path, '/games/Uridium.d64');
    expect(launched.single.mediaType, MediaFormatFilter.disk);
  });
}
