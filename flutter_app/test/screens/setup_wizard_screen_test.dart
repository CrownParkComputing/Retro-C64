// The setup wizard's way OUT, on the platform where it was once a trap.
//
// On iOS the games step is a file import rather than a folder pick, and
// Finish used to be gated on having imported at least one file. A first
// launch on a device with no C64 files yet therefore had no reachable exit:
// the picker could be cancelled forever, Finish stayed disabled, and the
// app never got past the wizard. That is the bug this file guards.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vice_multiplatform/screens/setup_wizard_screen.dart';
import 'package:vice_multiplatform/services/app_prefs.dart';
import 'package:vice_multiplatform/services/storage_access.dart';

import '../fakes/fake_storage_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory imports;
  late FakeFileImportStorage storage;

  setUp(() {
    imports = Directory.systemTemp.createTempSync('vice_wizard_test');
    storage = FakeFileImportStorage(importDir: imports.path);
    StorageAccess.setInstanceForTesting(storage);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    StorageAccess.setInstanceForTesting(null);
    imports.deleteSync(recursive: true);
  });

  /// Pumps past the character-by-character typing of the current step.
  /// pumpAndSettle is unusable: the console cursor blinks forever.
  Future<void> finishTyping(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('Finish is reachable with nothing imported', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var completed = false;
    await tester.pumpWidget(MaterialApp(
      home: SetupWizardScreen(onComplete: () => completed = true),
    ));
    addTearDown(() => tester.pumpWidget(const SizedBox()));

    // Welcome -> App. The app step is automatic on this strategy.
    await finishTyping(tester);
    await tester.tap(find.text('Next'));
    await finishTyping(tester);

    // App -> Games.
    await tester.tap(find.text('Next'));
    await finishTyping(tester);

    // The games step opens the importer by itself, and here the user picks
    // nothing -- exactly the situation that used to be unescapable.
    expect(storage.pickAndImportCalls, greaterThan(0));
    final finish = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Finish'),
    );
    expect(finish.onPressed, isNotNull,
        reason: 'Finish must work with nothing imported');

    await tester.tap(find.text('Finish'));
    await tester.pump();
    await tester.pump();

    expect(completed, isTrue);
    expect(await AppPrefs.isSetupCompleted(), isTrue,
        reason: 'the wizard must not ask again on the next launch');
  });
}
