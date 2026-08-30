// Drives the app through the screens the App Store listing needs and asks the
// host driver to capture each one.
//
// This exists because the screenshots cannot be taken by hand at any useful
// scale: five sibling apps, several screens each, re-taken whenever the UI
// moves, and every image has to be the exact pixel size Apple validates. It
// also turns a screen that fails to build into a failing test rather than a
// screenshot nobody noticed was missing.
//
// Run it with tool/screenshots.sh, which supplies the simulator and fixtures.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:retro_c64/main.dart' as app;

/// Skips the launch-a-title shot. That one starts the real core, which holds
/// the isolate long enough that the driver's connection can drop -- so it is
/// separable from the static screens, which must not be lost with it.
const bool kSkipRunning = bool.fromEnvironment('SKIP_RUNNING');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder byText(String s) => find.textContaining(s, findRichText: true);

  /// Settles, then captures. pumpAndSettle alone is not enough: the library
  /// scans off the main isolate, so the grid arrives after the frame that
  /// "settled" and an immediate capture catches an empty shelf.
  Future<void> shoot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await binding.takeScreenshot(name);
  }

  /// A finder for the BUTTON carrying this label, not merely the text. These
  /// screens instruct as well as offer, and a plain text finder happily takes
  /// the sentence that mentions a control instead of the control.
  Finder button(String label) {
    final text = byText(label);
    for (final type in <Type>[
      ElevatedButton,
      FilledButton,
      OutlinedButton,
      TextButton,
      InkWell,
    ]) {
      final f = find.ancestor(of: text, matching: find.byType(type));
      if (f.evaluate().isNotEmpty) return f;
    }
    return text;
  }

  Future<bool> tapIfPresent(WidgetTester tester, Finder f) async {
    if (f.evaluate().isEmpty) return false;
    await tester.tap(f.first, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    return true;
  }

  /// Names what IS on screen. "The marker did not appear" says nothing about
  /// which screen actually arrived, and that is the only useful fact here.
  void dumpVisibleText() {
    for (final e in find.byType(Text).evaluate()) {
      final t = (e.widget as Text).data;
      if (t != null && t.trim().isNotEmpty && t.length < 60) {
        debugPrint('  on screen| $t');
      }
    }
  }

  /// Opens a rail category and PROVES it opened, by waiting for something only
  /// that screen shows. Without the proof a tap that lands on nothing leaves
  /// the previous panel up, every later capture is the same panel, and the run
  /// reports success with a set of identical screenshots.
  Future<void> openCategory(
      WidgetTester tester, String title, String marker) async {
    final entry = button(title);
    if (entry.evaluate().isEmpty) {
      await binding.takeScreenshot('FAILED-looking-for-$title');
      dumpVisibleText();
      fail('no rail entry titled "$title"');
    }
    await tester.tap(entry.first);
    await tester.pumpAndSettle();
    if (byText(marker).evaluate().isEmpty) {
      await binding.takeScreenshot('FAILED-opening-$title');
      dumpVisibleText();
      fail('tapped "$title" but "$marker" never appeared -- '
          'the panel did not change');
    }
  }

  /// Returns to the workbench when a screen opened as its own route.
  Future<void> backToWorkbench(WidgetTester tester) async {
    try {
      await tester.pageBack();
      await tester.pumpAndSettle();
      return;
    } catch (_) {
      // pageBack fails two ways that both land here: nothing was pushed, or
      // the route's back control is a plain IconButton rather than one of the
      // three widget types it knows about.
    }
    for (final icon in <IconData>[
      Icons.arrow_back_ios,
      Icons.arrow_back_ios_new,
      Icons.arrow_back,
      Icons.chevron_left,
    ]) {
      final f = find.widgetWithIcon(IconButton, icon);
      if (f.evaluate().isNotEmpty) {
        await tester.tap(f.first, warnIfMissed: false);
        await tester.pumpAndSettle();
        return;
      }
    }
  }

  testWidgets('captures the listing screenshots', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Install gave the app an empty container, so it starts with nothing to
    // find. tool/screenshots.sh stages the fixtures from a separate process --
    // it has to, because `flutter drive` installs the app and an install hands
    // it a brand new container. So wait for the files rather than assuming
    // they arrived; an unseeded run otherwise fails much later and much less
    // clearly.
    final docs = await getApplicationDocumentsDirectory();
    final started = DateTime.now();
    var seen = 0;
    while (DateTime.now().difference(started) < const Duration(seconds: 20)) {
      seen = docs.listSync(recursive: true).whereType<File>().length;
      if (seen > 0) break;
      await tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    debugPrint('fixtures: $seen file(s) after '
        '${DateTime.now().difference(started).inMilliseconds}ms');

    // The wizard is what a reviewer meets on a fresh install, so it belongs in
    // the listing. Detected by its own buttons rather than by a title.
    //
    // Getting this wrong was not a missing screenshot but a wrong app state:
    // undetected, the run fell through to the category loop, and the first
    // lookup for "Compliance" matched the wizard's "Store Compliance" button
    // and pressed it. That switches the app to free-ROM mode, which hides
    // Paths, Video, Input, Core, Music and History from the rail -- so every
    // later step then failed to find a rail entry that was never missing.
    // The wizard is THREE phases now -- welcome, primer, console -- and only
    // the console carries the Store Compliance / Start pair. Detecting the
    // wizard by "Store Compliance" alone therefore matched nothing on a fresh
    // container: the whole setup step was skipped without complaint,
    // '02-library' captured the welcome card, and the first rail lookup failed
    // with "no rail entry titled Compliance" several steps later. tapIfPresent
    // is what made it silent, so this asserts instead.
    if (button('I have done this before').evaluate().isNotEmpty) {
      await tester.tap(button('I have done this before'));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(button('Store Compliance'), findsOneWidget,
          reason: 'the welcome phase should lead to the setup console');
    }

    final onWizard = button('Store Compliance').evaluate().isNotEmpty;
    if (onWizard) {
      // The console, not the welcome card: the BASIC screen is the one that
      // looks like a C64 rather than like every other app's first run.
      await shoot(tester, '01-setup-wizard');
      // "Start", NOT "Store Compliance": the latter is a deliberate switch to
      // the bundled free ROMs, not a way past this screen.
      await tapIfPresent(tester, button('Start'));
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }
    await shoot(tester, '02-library');

    // <rail title, screenshot name, a string only that screen shows>
    //
    // Markers must be visible WITHOUT scrolling: these panels are lazy lists,
    // so a string further down is simply not built yet and reads as "the panel
    // did not change" when the panel changed perfectly well.
    for (final entry in <List<String>>[
      <String>['Compliance', '03-store-compliance',
          'App Store / Play Store compliance'],
      <String>['Paths', '04-paths', 'C64 ROMs'],
      <String>['Video', '05-video', 'Screen size'],
      <String>['Input', '06-input', 'Joystick port'],
      <String>['Music', '07-music', 'SID'],
      <String>['History', '08-history', 'The machine'],
      <String>['About', '09-about', 'What this is'],
    ]) {
      await openCategory(tester, entry[0], entry[2]);
      await shoot(tester, entry[1]);
      await backToWorkbench(tester);
    }

    await openCategory(tester, 'Games', 'Search games');
    await shoot(tester, '10-library');

    if (!kSkipRunning && await tapIfPresent(tester, byText('.d64'))) {
      // Emulation needs real time, not pumped frames: the core runs on its own
      // thread, and that thread is not driven by the test clock.
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      await shoot(tester, '11-running');
    }
  });
}
