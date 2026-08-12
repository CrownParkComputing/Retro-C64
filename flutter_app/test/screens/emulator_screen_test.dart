// The emulator screen's layout, in BOTH gamepad branches.
//
// The bug this file exists for: the on-screen controls were a single
// NON-positioned child of the emulator Stack, and returned SizedBox.shrink()
// whenever they were hidden. A Stack with one non-positioned child
// shrink-wraps it -- so the moment a controller was connected (always, on a
// handheld with a built-in pad) the whole Stack collapsed to 0x0 and the
// screen went black, framebuffer and all. Nothing about that is visible in
// a unit test of any single widget; it needs the screen laid out under real
// constraints, twice.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vice_multiplatform/data/c64_keys.dart';
import 'package:vice_multiplatform/data/custom_button.dart';
import 'package:vice_multiplatform/ffi/vice_bindings.dart';
import 'package:vice_multiplatform/screens/emulator_screen.dart';
import 'package:vice_multiplatform/services/app_prefs.dart';
import 'package:vice_multiplatform/services/gamepad_service.dart';
import 'package:vice_multiplatform/widgets/assignable_action_button.dart';
import 'package:vice_multiplatform/widgets/custom_key_button.dart';
import 'package:vice_multiplatform/widgets/framebuffer_view.dart';
import 'package:vice_multiplatform/widgets/wobble_joystick.dart';

import '../fakes/fake_vice_core.dart';

/// A GamepadService that has never been start()ed, so it polls nothing and
/// opens no platform channel -- its `connected` notifier is driven by hand
/// to stand in for a controller being plugged in or not.
GamepadService fakeGamepad(WidgetTester tester, {required bool connected}) {
  final service = GamepadService()..connected.value = connected;
  addTearDown(service.dispose);
  return service;
}

void main() {
  const screenSize = Size(1280, 720);

  Future<void> pumpEmulator(
    WidgetTester tester, {
    required FakeViceCore core,
    OnScreenPadMode padMode = OnScreenPadMode.auto,
    GamepadService? gamepad,
    List<CustomButton> customButtons = const [],
    int joystickPort = 2,
    bool leftHanded = false,
  }) async {
    tester.view.physicalSize = screenSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: EmulatorScreen(
        core: core,
        mediaLabel: 'Boulder Dash.d64',
        onBackToLibrary: () {},
        padMode: padMode,
        gamepad: gamepad,
        customButtons: customButtons,
        joystickPort: joystickPort,
        leftHanded: leftHanded,
      ),
    ));
    // FramebufferView polls the core on a periodic timer; take the tree down
    // at the end of the test so that timer is cancelled with it.
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  group('layout fills the screen', () {
    // Both gamepad branches, on the default Auto pad mode: connected hides
    // the on-screen controls (the branch that collapsed the Stack to 0x0 on
    // a handheld), disconnected shows them.
    for (final controllerConnected in [true, false]) {
      testWidgets(
          'with a controller ${controllerConnected ? "connected" : "disconnected"}',
          (tester) async {
        await pumpEmulator(
          tester,
          core: FakeViceCore(),
          padMode: OnScreenPadMode.auto,
          gamepad: fakeGamepad(tester, connected: controllerConnected),
        );

        // The controls really are in the state this branch is about.
        expect(find.byType(WobbleJoystick),
            controllerConnected ? findsNothing : findsOneWidget);

        final body = tester.getSize(find.byType(Scaffold));
        expect(body, screenSize,
            reason: 'the emulator screen must fill the window in every '
                'joypad-visibility branch');

        // The framebuffer is laid out with real area -- a 0x0 framebuffer is
        // a black screen even when the Scaffold itself is fine.
        final picture = tester.getSize(find.byType(FramebufferView));
        expect(picture.width, greaterThan(0));
        expect(picture.height, greaterThan(0));

        // ...and so is the chrome that sits over it.
        expect(find.text('Boulder Dash.d64'), findsOneWidget);
        expect(find.byIcon(Icons.menu), findsOneWidget);
      });
    }

    testWidgets('the touch controls appear when the pad is shown',
        (tester) async {
      await pumpEmulator(tester,
          core: FakeViceCore(), padMode: OnScreenPadMode.always);
      expect(find.byType(WobbleJoystick), findsOneWidget);
      expect(find.byType(ActionButton), findsNWidgets(2)); // A and B
    });

    testWidgets('hiding the touch controls hides only the controls',
        (tester) async {
      await pumpEmulator(tester,
          core: FakeViceCore(), padMode: OnScreenPadMode.never);
      expect(find.byType(WobbleJoystick), findsNothing);
      expect(find.byType(ActionButton), findsNothing);
      // The picture stays.
      expect(find.byType(FramebufferView), findsOneWidget);
    });

    testWidgets('user-added key buttons sit alongside, not instead of, fire',
        (tester) async {
      await pumpEmulator(
        tester,
        core: FakeViceCore(),
        padMode: OnScreenPadMode.always,
        customButtons: [
          CustomButton.key(C64KeyCatalogue.find(7, 4)!), // SPACE
        ],
      );
      expect(find.byType(CustomKeyButton), findsOneWidget);
      expect(find.byType(ActionButton), findsNWidgets(2));
    });

    testWidgets('a direction button drives the joystick, not the key matrix',
        (tester) async {
      final core = FakeViceCore();
      await pumpEmulator(
        tester,
        core: core,
        padMode: OnScreenPadMode.always,
        customButtons: [CustomButton.direction(JoyDirection.up)],
      );

      final button = find.byType(CustomKeyButton);
      expect(button, findsOneWidget);

      final gesture =
          await tester.startGesture(tester.getCenter(button));
      await tester.pump();
      // UP arrives as a joystick bit...
      expect(core.joystickCalls.last.mask & ViceJoyBits.up, ViceJoyBits.up);
      // ...and never as a keyboard press.
      expect(core.matrixKeys, isEmpty);

      await gesture.up();
      await tester.pump();
      expect(core.joystickCalls.last.mask & ViceJoyBits.up, 0);
    });

    testWidgets('left-handed mode moves the joystick without breaking layout',
        (tester) async {
      await pumpEmulator(tester,
          core: FakeViceCore(),
          padMode: OnScreenPadMode.always,
          leftHanded: true);
      expect(tester.getSize(find.byType(Scaffold)), screenSize);

      final joystick = tester.getCenter(find.byType(WobbleJoystick));
      final fire = tester.getCenter(find.byType(ActionButton).first);
      expect(joystick.dx, greaterThan(fire.dx),
          reason: 'left-handed puts the stick on the right of the fire buttons');
    });
  });

  group('quick settings', () {
    testWidgets('opens, reports the live state, and closes', (tester) async {
      final core = FakeViceCore();
      await pumpEmulator(tester, core: core, joystickPort: 1);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.text('Quick Settings'), findsOneWidget);
      // The port row shows the port that is actually in use, not a fixed
      // string -- "nothing moves" is the symptom of the wrong port.
      expect(find.text('Port 1 (some games)'), findsOneWidget);

      // The keyboard and on-screen-pad toggles are NOT in here. Each has a
      // permanent button in the corner of the game that shows its own state,
      // and a panel row doing the same job is a second place to look and a
      // second thing to keep in sync rather than a shortcut.
      expect(find.text('Virtual Keyboard'), findsNothing);
      expect(find.text('On-screen Pad'), findsNothing);

      // Reset really does go to the core.
      await tester.tap(find.text('Reset C64'));
      await tester.pumpAndSettle();
      expect(core.stopCount, 1);
      expect(core.startCount, 1);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Quick Settings'), findsNothing);
      // Closing the panel must not take the screen with it.
      expect(tester.getSize(find.byType(Scaffold)), screenSize);
    });

    testWidgets('the virtual keyboard opens over the picture', (tester) async {
      await pumpEmulator(tester, core: FakeViceCore());

      // Straight from the corner button -- one tap from play, which is why
      // the duplicate panel row was dropped.
      await tester.tap(find.byIcon(Icons.keyboard));
      await tester.pumpAndSettle();

      expect(find.text('RUN/STOP'), findsOneWidget);
      expect(tester.getSize(find.byType(Scaffold)), screenSize);
    });
  });

  testWidgets('changing port releases the old one so nothing stays latched',
      (tester) async {
    final core = FakeViceCore();
    await pumpEmulator(tester, core: core, joystickPort: 2);

    await tester.pumpWidget(MaterialApp(
      home: EmulatorScreen(
        core: core,
        mediaLabel: 'Boulder Dash.d64',
        onBackToLibrary: () {},
        joystickPort: 1,
      ),
    ));
    await tester.pump();

    // Port 2 is cleared before port 1 is driven, or a held direction stays
    // pressed on a port nothing is watching any more.
    expect(core.joystickCalls.first, (port: 2, mask: 0));
    expect(core.joystickCalls.last.port, 1);
  });
}
