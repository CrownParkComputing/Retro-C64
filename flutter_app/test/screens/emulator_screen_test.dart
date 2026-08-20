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
import 'package:retro_c64/data/c64_keys.dart';
import 'package:retro_c64/data/custom_button.dart';
import 'package:retro_c64/ffi/vice_bindings.dart';
import 'package:retro_c64/screens/emulator_screen.dart';
import 'package:retro_c64/services/app_prefs.dart';
import 'package:retro_c64/services/gamepad_service.dart';
import 'package:retro_c64/widgets/assignable_action_button.dart';
import 'package:retro_c64/widgets/custom_key_button.dart';
import 'package:retro_c64/data/emulator_ui_state.dart';
import 'package:retro_c64/widgets/emulator_control_strip.dart';
import 'package:retro_c64/widgets/framebuffer_view.dart';
import 'package:retro_c64/widgets/wobble_joystick.dart';

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
    VoidCallback? onBackToLibrary,
    ValueChanged<int>? onJoystickPortChanged,
  }) async {
    tester.view.physicalSize = screenSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Mirrors the workbench: the machine's picture, and the control strip as
    // a SIBLING below it rather than a child of it. Sharing one
    // EmulatorUiState is the whole reason that split works.
    final ui = EmulatorUiState();
    addTearDown(ui.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: Column(
          children: [
            Expanded(
              child: EmulatorScreen(
                core: core,
                mediaLabel: 'Boulder Dash.d64',
                onBackToLibrary: onBackToLibrary ?? () {},
                onJoystickPortChanged: onJoystickPortChanged,
                padMode: padMode,
                gamepad: gamepad,
                customButtons: customButtons,
                joystickPort: joystickPort,
                leftHanded: leftHanded,
                ui: ui,
              ),
            ),
            EmulatorControlStrip(
              ui: ui,
              onPause: onBackToLibrary ?? () {},
              padMode: padMode,
              joystickPort: joystickPort,
              onJoystickPortChanged: onJoystickPortChanged,
            ),
          ],
        ),
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

        // The emulator view takes the full width and everything the strip
        // below it does not need -- not the whole window any more, but never
        // the 0x0 this file exists for.
        final body = tester.getSize(find.byType(Scaffold));
        expect(body.width, screenSize.width,
            reason: 'the emulator screen must fill the window in every '
                'joypad-visibility branch');
        expect(body.height, greaterThan(screenSize.height * 0.8));
        expect(body.height, lessThan(screenSize.height));

        // The framebuffer is laid out with real area -- a 0x0 framebuffer is
        // a black screen even when the Scaffold itself is fine.
        final picture = tester.getSize(find.byType(FramebufferView));
        expect(picture.width, greaterThan(0));
        expect(picture.height, greaterThan(0));

        // ...and so is the chrome, which sits UNDER the picture rather than
        // over it. The loaded title is deliberately NOT named here: the
        // workbench's status strip already does that, and the emulator
        // screen printing it again put the same string on screen twice.
        expect(find.text('Boulder Dash.d64'), findsNothing);
        expect(find.byIcon(Icons.pause), findsOneWidget);
        expect(tester.getTopLeft(find.byIcon(Icons.pause)).dy,
            greaterThan(tester.getBottomLeft(find.byType(FramebufferView)).dy),
            reason: 'the control strip belongs below the picture');
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
      expect(tester.getSize(find.byType(Scaffold)).width, screenSize.width);

      final joystick = tester.getCenter(find.byType(WobbleJoystick));
      final fire = tester.getCenter(find.byType(ActionButton).first);
      expect(joystick.dx, greaterThan(fire.dx),
          reason: 'left-handed puts the stick on the right of the fire buttons');
    });
  });

  group('in-game controls', () {
    testWidgets('pause returns to the workbench, with no menu in between',
        (tester) async {
      var back = 0;
      await pumpEmulator(tester,
          core: FakeViceCore(), onBackToLibrary: () => back++);

      // There is no hamburger and no panel. Every row the old Quick Settings
      // held is now either a button in this corner or a settings page, so a
      // menu in front of them was purely an extra tap.
      expect(find.byIcon(Icons.menu), findsNothing);

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pumpAndSettle();
      expect(back, 1);
    });

    testWidgets('the port button shows the port and swaps it', (tester) async {
      int? swapped;
      await pumpEmulator(tester,
          core: FakeViceCore(),
          joystickPort: 1,
          onJoystickPortChanged: (p) => swapped = p);

      // The number IS the label: "nothing moves" is the symptom of the wrong
      // port, and that is not a moment to go hunting through menus.
      expect(find.text('P1'), findsOneWidget);
      await tester.tap(find.text('P1'));
      await tester.pumpAndSettle();
      expect(swapped, 2);
    });

    testWidgets('adding a button lives in the move-controls mode',
        (tester) async {
      await pumpEmulator(tester, core: FakeViceCore());

      expect(find.text('+ ADD BUTTON'), findsNothing);
      await tester.tap(find.byIcon(Icons.open_with));
      await tester.pumpAndSettle();

      // You add a button and then immediately want to put it somewhere,
      // which is exactly what this mode is for.
      expect(find.text('+ ADD BUTTON'), findsOneWidget);
      expect(find.text('RESET'), findsOneWidget);
    });

    testWidgets('the virtual keyboard opens over the picture', (tester) async {
      await pumpEmulator(tester, core: FakeViceCore());

      // Straight from the strip below the picture -- one tap from play,
      // which is why the duplicate panel row was dropped.
      await tester.tap(find.byIcon(Icons.keyboard));
      await tester.pumpAndSettle();

      expect(find.text('RUN/STOP'), findsOneWidget);
      expect(tester.getSize(find.byType(Scaffold)).width, screenSize.width);
    });
  });

  testWidgets('changing port releases the old one so nothing stays latched',
      (tester) async {
    final core = FakeViceCore();
    await pumpEmulator(tester, core: core, joystickPort: 2);

    // Same tree shape as pumpEmulator's, with only the port changed -- a
    // DIFFERENT shape would tear the State down and rebuild it, and
    // didUpdateWidget (the thing under test) would never run.
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: Column(
          children: [
            Expanded(
              child: EmulatorScreen(
                core: core,
                mediaLabel: 'Boulder Dash.d64',
                onBackToLibrary: () {},
                joystickPort: 1,
              ),
            ),
            EmulatorControlStrip(
              ui: EmulatorUiState(),
              onPause: () {},
              padMode: OnScreenPadMode.auto,
              joystickPort: 1,
            ),
          ],
        ),
      ),
    ));
    await tester.pump();

    // Port 2 is cleared before port 1 is driven, or a held direction stays
    // pressed on a port nothing is watching any more.
    expect(core.joystickCalls.first, (port: 2, mask: 0));
    expect(core.joystickCalls.last.port, 1);
  });
}
