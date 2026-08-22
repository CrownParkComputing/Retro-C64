// Persisted settings, against shared_preferences' in-memory mock.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_c64/data/c64_keys.dart';
import 'package:retro_c64/data/custom_button.dart';
import 'package:retro_c64/services/app_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = SharedPrefsImpl(await SharedPreferences.getInstance());
  });

  group('defaults on a fresh install', () {
    test('setup has not been completed, so the wizard runs', () async {
      expect(await prefs.isSetupCompleted(), isFalse);
    });

    test('no folders are configured', () async {
      expect(await prefs.getAppFolderPath(), isNull);
      expect(await prefs.getGamesFolderPath(), isNull);
    });

    test('port 2, right-handed, auto pad, no custom buttons, fire on A/B',
        () async {
      // Port 2 is what most commercial C64 games read.
      expect(await prefs.getJoystickPort(), 2);
      expect(await prefs.getLeftHandedInput(), isFalse);
      expect(await prefs.getOnScreenPadMode(), OnScreenPadMode.auto);
      expect(await prefs.getCustomButtons(), isEmpty);
      // null means "joystick fire", not "unset key 0" (which is Space).
      expect(await prefs.getActionButtonKey('a'), isNull);
      expect(await prefs.getActionButtonKey('b'), isNull);
    });
  });

  group('round trips', () {
    test('setup completion, folders and handedness persist', () async {
      await prefs.setSetupCompleted(true);
      await prefs.setAppFolderPath('/home/user/vice');
      await prefs.setGamesFolderPath('/home/user/games');
      await prefs.setLeftHandedInput(true);

      expect(await prefs.isSetupCompleted(), isTrue);
      expect(await prefs.getAppFolderPath(), '/home/user/vice');
      expect(await prefs.getGamesFolderPath(), '/home/user/games');
      expect(await prefs.getLeftHandedInput(), isTrue);
    });

    test('the pad mode survives a restart', () async {
      await prefs.setOnScreenPadMode(OnScreenPadMode.always);
      expect(await prefs.getOnScreenPadMode(), OnScreenPadMode.always);
      await prefs.setOnScreenPadMode(OnScreenPadMode.never);
      expect(await prefs.getOnScreenPadMode(), OnScreenPadMode.never);
    });

    test('a stored pad mode from a future version falls back to auto',
        () async {
      SharedPreferences.setMockInitialValues({'on_screen_pad_mode': 99});
      prefs = SharedPrefsImpl(await SharedPreferences.getInstance());
      expect(await prefs.getOnScreenPadMode(), OnScreenPadMode.auto);
    });

    test('the joystick port only ever comes back as 1 or 2', () async {
      await prefs.setJoystickPort(1);
      expect(await prefs.getJoystickPort(), 1);
      // Anything else is clamped on the way in AND on the way out -- a
      // nonsense port means every input silently goes nowhere.
      await prefs.setJoystickPort(7);
      expect(await prefs.getJoystickPort(), 2);
      SharedPreferences.setMockInitialValues({'joystick_port': 0});
      prefs = SharedPrefsImpl(await SharedPreferences.getInstance());
      expect(await prefs.getJoystickPort(), 2);
    });

    test('an action button key round-trips, and clears back to fire',
        () async {
      await prefs.setActionButtonKey('a', 1); // Run/Stop
      expect(await prefs.getActionButtonKey('a'), 1);
      // The two buttons are stored separately.
      expect(await prefs.getActionButtonKey('b'), isNull);

      await prefs.setActionButtonKey('a', 0); // Space -- ordinal zero
      expect(await prefs.getActionButtonKey('a'), 0,
          reason: 'ordinal 0 (Space) must not be confused with "unmapped"');

      await prefs.setActionButtonKey('a', null);
      expect(await prefs.getActionButtonKey('a'), isNull);
    });
  });

  group('custom on-screen buttons', () {
    test('keep their keys, and their order, across a restart', () async {
      final buttons = [
        CustomButton.key(C64KeyCatalogue.find(7, 4)!), // SPACE
        CustomButton.key(C64KeyCatalogue.find(7, 7)!), // RUN/STOP
        CustomButton.key(C64KeyCatalogue.find(1, 2)!), // A
      ];
      await prefs.setCustomButtons(buttons);

      final restored = await prefs.getCustomButtons();
      expect(restored.map((k) => k.label).toList(),
          ['SPACE', 'RUN/STOP', 'A']);
      expect(restored.map((k) => k.id).toList(),
          ['key:7:4', 'key:7:7', 'key:1:2']);
    });

    test('a key the catalogue no longer knows keeps its stored label',
        () async {
      // The row/column is what the core is actually sent, so the button must
      // still work even if the catalogue has moved on.
      SharedPreferences.setMockInitialValues({
        'custom_on_screen_buttons':
            jsonEncode([{'label': 'MYSTERY', 'row': 6, 'column': 3}]),
      });
      prefs = SharedPrefsImpl(await SharedPreferences.getInstance());
      final restored = await prefs.getCustomButtons();
      expect(restored.single.label, 'MYSTERY');
      expect(restored.single.key!.row, 6);
      expect(restored.single.key!.column, 3);
    });

    test('a corrupt list costs the buttons, not the app', () async {
      SharedPreferences.setMockInitialValues(
          {'custom_on_screen_buttons': 'not json at all'});
      prefs = SharedPrefsImpl(await SharedPreferences.getInstance());
      expect(await prefs.getCustomButtons(), isEmpty);

      SharedPreferences.setMockInitialValues({
        'custom_on_screen_buttons':
            jsonEncode([{'label': 'BAD', 'row': 'one', 'column': null}]),
      });
      prefs = SharedPrefsImpl(await SharedPreferences.getInstance());
      expect(await prefs.getCustomButtons(), isEmpty);
    });

    test('joystick directions round-trip alongside keys', () async {
      await prefs.setCustomButtons([
        CustomButton.direction(JoyDirection.up),
        CustomButton.key(C64KeyCatalogue.find(7, 4)!),
      ]);

      final restored = await prefs.getCustomButtons();
      expect(restored.map((b) => b.label).toList(), ['Up', 'SPACE']);
      expect(restored.first.isDirection, isTrue);
      expect(restored.first.direction, JoyDirection.up);
      expect(restored.last.isDirection, isFalse);
      // Ids are namespaced so a direction can never collide with a key.
      expect(restored.map((b) => b.id).toList(), ['dir:up', 'key:7:4']);
    });

    test('buttons saved before directions existed still load', () async {
      // The old format had no 'direction' field at all. An upgrade must not
      // silently drop the buttons someone already set up.
      SharedPreferences.setMockInitialValues({
        'custom_on_screen_buttons':
            jsonEncode([{'label': 'SPACE', 'row': 7, 'column': 4}]),
      });
      prefs = SharedPrefsImpl(await SharedPreferences.getInstance());
      final restored = await prefs.getCustomButtons();
      expect(restored.single.isDirection, isFalse);
      expect(restored.single.label, 'SPACE');
    });

    test('an unknown direction name is dropped, not crashed on', () async {
      SharedPreferences.setMockInitialValues({
        'custom_on_screen_buttons': jsonEncode([{'direction': 'sideways'}]),
      });
      prefs = SharedPrefsImpl(await SharedPreferences.getInstance());
      expect(await prefs.getCustomButtons(), isEmpty);
    });

    test('clearing the list removes every button', () async {
      await prefs.setCustomButtons(
          [CustomButton.key(C64KeyCatalogue.find(7, 4)!)]);
      await prefs.setCustomButtons([]);
      expect(await prefs.getCustomButtons(), isEmpty);
    });
  });

  group('OnScreenPadMode', () {
    test('auto hides the touch pad only while a controller is connected', () {
      expect(
          OnScreenPadMode.auto.visibleWith(controllerConnected: false), isTrue);
      expect(
          OnScreenPadMode.auto.visibleWith(controllerConnected: true), isFalse);
    });

    test('always wins over a connected controller', () {
      // The handheld case: the Retroid Flip2\'s built-in pad is permanently
      // connected, so auto-hide alone made touch controls unreachable.
      expect(OnScreenPadMode.always.visibleWith(controllerConnected: true),
          isTrue);
      expect(OnScreenPadMode.always.visibleWith(controllerConnected: false),
          isTrue);
    });

    test('never hides the pad regardless', () {
      expect(OnScreenPadMode.never.visibleWith(controllerConnected: false),
          isFalse);
      expect(OnScreenPadMode.never.visibleWith(controllerConnected: true),
          isFalse);
    });

    test('cycling the Quick Settings row visits all three and comes back', () {
      var mode = OnScreenPadMode.auto;
      final seen = <OnScreenPadMode>[];
      for (var i = 0; i < OnScreenPadMode.values.length; i++) {
        seen.add(mode);
        mode = mode.next;
      }
      expect(seen.toSet().length, OnScreenPadMode.values.length);
      expect(mode, OnScreenPadMode.auto);
    });
  });

  group('on-screen control layout', () {
    test('defaults to the wobble stick and no saved positions', () async {
      expect(await prefs.getJoystickStyle(), JoystickStyle.wobble);
      expect(await prefs.getControlPositions(), isEmpty);
    });

    test('remembers the chosen style', () async {
      await prefs.setJoystickStyle(JoystickStyle.dpad);
      expect(await prefs.getJoystickStyle(), JoystickStyle.dpad);
    });

    test('stores each control independently', () async {
      await prefs.setControlPosition(kControlIdStick, const Offset(0.2, 0.7));
      await prefs.setControlPosition(
          kControlIdButtons, const Offset(0.8, 0.6));

      final positions = await prefs.getControlPositions();
      expect(positions[kControlIdStick], const Offset(0.2, 0.7));
      expect(positions[kControlIdButtons], const Offset(0.8, 0.6));
    });

    test('moving one control does not forget the other', () async {
      await prefs.setControlPosition(kControlIdStick, const Offset(0.2, 0.7));
      await prefs.setControlPosition(
          kControlIdButtons, const Offset(0.8, 0.6));
      await prefs.setControlPosition(kControlIdStick, const Offset(0.3, 0.5));

      final positions = await prefs.getControlPositions();
      expect(positions[kControlIdStick], const Offset(0.3, 0.5));
      expect(positions[kControlIdButtons], const Offset(0.8, 0.6),
          reason: 'the buttons were not touched');
    });

    test('clamps positions that would put a control off screen', () async {
      await prefs.setControlPosition(kControlIdStick, const Offset(-4, 9));
      expect((await prefs.getControlPositions())[kControlIdStick],
          const Offset(0.0, 1.0));
    });

    test('a corrupt layout resets to defaults instead of throwing', () async {
      SharedPreferences.setMockInitialValues(
          {'on_screen_control_positions': 'not json at all'});
      prefs = SharedPrefsImpl(await SharedPreferences.getInstance());
      expect(await prefs.getControlPositions(), isEmpty);
    });

    test('reset clears every stored position', () async {
      await prefs.setControlPosition(kControlIdStick, const Offset(0.2, 0.7));
      await prefs.clearControlPositions();
      expect(await prefs.getControlPositions(), isEmpty);
    });
  });

  group('workbench music', () {
    test('is on by default -- silence is the wrong first impression', () async {
      expect(await prefs.getWorkbenchMusic(), isTrue);
    });

    test('the off switch is remembered', () async {
      await prefs.setWorkbenchMusic(false);
      expect(await prefs.getWorkbenchMusic(), isFalse);
    });
  });
}
