// The Core screen edits VICE's own resources on the live machine.
//
// Two things worth pinning: an option the running machine does not have is
// not shown at all (the catalogue has to survive a VICE upgrade and a
// different machine model), and with no core running the screen explains
// itself instead of showing an empty list -- VICE only builds its resource
// table during init_main.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_c64/screens/core_settings_screen.dart';

import '../fakes/fake_vice_core.dart';

/// The screen bounds its resource dump with a 5s timeout so a wedged path
/// lookup cannot leave the list waiting forever. In a test that timer is
/// still armed when the body ends, which the framework reports as a leak --
/// so let it expire.
Future<void> drainDumpTimeout(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 6));

void main() {
  Future<void> pump(WidgetTester tester, FakeViceCore core) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: CoreSettingsScreen(core: core))),
    );
    // The dump is resolved asynchronously; a few frames let it land (or
    // fail, which the curated options must survive).
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  testWidgets('says why there is nothing to show with no machine running',
      (tester) async {
    await pump(tester, FakeViceCore(isRunning: false));

    expect(find.textContaining('No machine is running'), findsOneWidget);
    // And it did not pretend to read one.
    expect(find.text('Warp mode'), findsNothing);
  });

  testWidgets('shows only the options this machine actually has',
      (tester) async {
    final core = FakeViceCore()
      ..resourceInts['WarpMode'] = 0
      ..resourceInts['Drive8TrueEmulation'] = 1;
    await pump(tester, core);

    expect(find.text('Warp mode'), findsOneWidget);
    expect(find.text('True drive emulation (drive 8)'), findsOneWidget);
    // In the catalogue, absent from this machine: not rendered.
    expect(find.text('SID model'), findsNothing);
    expect(find.text('Drive sounds'), findsNothing);
    await drainDumpTimeout(tester);
  });

  testWidgets('says so when the core is older than the app', (tester) async {
    // The three iOS artifacts are built by different toolchains and drift.
    // A core without the resource API must produce an explanation, not an
    // empty machine -- and must not stop the app loading in the first place.
    final core = FakeViceCore()
      ..resourceApiAvailable = false
      ..resourceInts['WarpMode'] = 0;
    await pump(tester, core);

    expect(find.textContaining('no resource access'), findsOneWidget);
    expect(find.text('Warp mode'), findsNothing);
    await drainDumpTimeout(tester);
  });

  testWidgets('a toggle writes the resource to the core', (tester) async {
    final core = FakeViceCore()..resourceInts['WarpMode'] = 0;
    await pump(tester, core);

    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 200));

    expect(core.resourceInts['WarpMode'], 1);
    await drainDumpTimeout(tester);
  });
}
