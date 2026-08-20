// The first screen a new user ever sees, and it had no tests at all.
//
// It is also the screen with the most ways to go quietly wrong: it sweeps
// storage on entry without being asked, and every branch of that sweep
// (found something / found nothing / threw) has to leave the user with a way
// forward. A wizard that dead-ends is an app that cannot be started.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_c64/screens/setup_wizard_screen.dart';
import 'package:retro_c64/services/app_prefs.dart';
import 'package:retro_c64/services/storage_access.dart';

import '../fakes/fake_storage_access.dart';

// Not asserted here: what the typed console SAYS. It does not render its
// lines as Text widgets, so a finder cannot see them -- and a test that
// cannot observe the thing it names is worse than no test. The counts logic
// it displays is exercised through the import behaviour below.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final real = StorageAccess.instance;
  tearDown(() => StorageAccess.instance = real);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpWizard(
    WidgetTester tester, {
    required FakeStorageAccess storage,
    VoidCallback? onComplete,
  }) async {
    StorageAccess.instance = storage;
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: SetupWizardScreen(onComplete: onComplete ?? () {}),
    ));
    // The console types its lines on a timer and the sweep is async; settle
    // by pumping rather than pumpAndSettle, which never returns while the
    // typing animation is running.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  testWidgets('imports what is already reachable, without being asked',
      (tester) async {
    final storage = FakeStorageAccess(
      importable: const [
        ImportedFile(displayName: 'Uridium.d64', path: '/in/Uridium.d64'),
        ImportedFile(displayName: 'Delta.tap', path: '/in/Delta.tap'),
      ],
    );

    await pumpWizard(tester, storage: storage);

    // Files sitting in the container are pulled in on entry: a user who
    // dropped games into the Files app should not also have to find a
    // picker.
    expect(storage.importCalls, 1);
    expect(storage.imported, hasLength(2));
  });

  testWidgets('an empty library still offers a way forward', (tester) async {
    await pumpWizard(tester, storage: FakeStorageAccess());

    // Nothing found is the common first-run case, not an error state. The
    // way forward is the folder plus a rescan - the Files picker is gone.
    expect(find.textContaining('Scan'), findsWidgets);
  });

  testWidgets('a failed sweep does not strand the user', (tester) async {
    // Storage can genuinely fail here -- permissions, a container that is not
    // there yet. The wizard must still finish rather than hang on a spinner.
    await pumpWizard(tester, storage: FakeStorageAccess(throwOnScan: true));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Scan'), findsWidgets);
  });

  testWidgets('finishing marks setup complete and calls back', (tester) async {
    var completed = 0;
    await pumpWizard(
      tester,
      storage: FakeStorageAccess(
        imported: const [
          ImportedFile(displayName: 'Uridium.d64', path: '/g/Uridium.d64'),
        ],
      ),
      onComplete: () => completed++,
    );

    final finish = find.text('Start');
    expect(finish, findsOneWidget,
        reason: 'the wizard must have a way to leave it');
    await tester.tap(finish);
    await tester.pump(const Duration(milliseconds: 100));

    expect(completed, 1);
    // Persisted, or the wizard reappears on the next launch and the user is
    // stuck in a loop.
    expect(await AppPrefs.isSetupCompleted(), isTrue);
  });
}
