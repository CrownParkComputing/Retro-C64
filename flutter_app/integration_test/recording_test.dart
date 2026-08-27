// The flow filmed for App Review.
//
// Separate from screenshots_test.dart because a reviewer wants one continuous
// journey, not a tour of every panel -- and because this one must touch ONLY
// what the app ships with. The screenshot run seeds real disk images to fill
// the library; a recording sent to Apple that booted a commercial title would
// be showing software we have no right to distribute, so this takes the
// free-ROM path and runs the bundled demo instead.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:retro_c64/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder byText(String s) => find.textContaining(s, findRichText: true);

  Finder button(String label) {
    final text = byText(label);
    for (final type in <Type>[
      ElevatedButton, FilledButton, OutlinedButton, TextButton, InkWell,
    ]) {
      final f = find.ancestor(of: text, matching: find.byType(type));
      if (f.evaluate().isNotEmpty) return f;
    }
    return text;
  }

  /// Real time, not pumped frames. The core runs on its own thread and the
  /// camera is recording wall-clock; a settle would race past everything the
  /// viewer is meant to see.
  Future<void> hold(WidgetTester tester, int seconds) async {
    for (var i = 0; i < seconds * 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    if (f.evaluate().isEmpty) return;
    await tester.tap(f.first, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }

  testWidgets('films the reviewer flow', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));
    await hold(tester, 3);                 // the first-run screen, read at speed

    // The reviewer's route: one button, nothing supplied, a working machine.
    await tap(tester, button('Store Compliance'));
    await hold(tester, 4);

    await tap(tester, byText('Games'));
    await hold(tester, 3);                 // the shelf, holding only the demo

    await tap(tester, byText('DEMO'));
    await hold(tester, 20);
    // A still from the middle of the emulated run, so there is proof the
    // machine really booted rather than a video nobody checked.
    await binding.takeScreenshot('proof-emulator-running');
    await hold(tester, 5);

    await tap(tester, byText('Compliance'));
    await hold(tester, 6);                 // what is bundled, and under which licence

    await tap(tester, byText('About'));
    await hold(tester, 4);
  });
}
