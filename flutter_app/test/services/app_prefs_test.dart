// Persisted settings, against shared_preferences' in-memory mock.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vice_multiplatform/data/c64_keys.dart';
import 'package:vice_multiplatform/data/custom_button.dart';
import 'package:vice_multiplatform/services/app_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('defaults on a fresh install', () {
    test('setup has not been completed, so the wizard runs', () async {
      expect(await AppPrefs.isSetupCompleted(), isFalse);
    });

    test('no folders are configured', () async {
      expect(await AppPrefs.getAppFolderPath(), isNull);
      expect(await AppPrefs.getGamesFolderPath(), isNull);
    });

    test('port 2, right-handed, auto pad, no custom buttons, fire on A/B',
        () async {
      // Port 2 is what most commercial C64 games read.
      expect(await AppPrefs.getJoystickPort(), 2);
      expect(await AppPrefs.getLeftHandedInput(), isFalse);
      expect(await AppPrefs.getOnScreenPadMode(), OnScreenPadMode.auto);
      expect(await AppPrefs.getCustomButtons(), isEmpty);
      // null means "joystick fire", not "unset key 0" (which is Space).
      expect(await AppPrefs.getActionButtonKey('a'), isNull);
      expect(await AppPrefs.getActionButtonKey('b'), isNull);
    });
  });

  group('round trips', () {
    test('setup completion, folders and handedness persist', () async {
      await AppPrefs.setSetupCompleted(true);
      await AppPrefs.setAppFolderPath('/home/user/vice');
      await AppPrefs.setGamesFolderPath('/home/user/games');
      await AppPrefs.setLeftHandedInput(true);

      expect(await AppPrefs.isSetupCompleted(), isTrue);
      expect(await AppPrefs.getAppFolderPath(), '/home/user/vice');
      expect(await AppPrefs.getGamesFolderPath(), '/home/user/games');
      expect(await AppPrefs.getLeftHandedInput(), isTrue);
    });

    test('the pad mode survives a restart', () async {
      await AppPrefs.setOnScreenPadMode(OnScreenPadMode.always);
      expect(await AppPrefs.getOnScreenPadMode(), OnScreenPadMode.always);
      await AppPrefs.setOnScreenPadMode(OnScreenPadMode.never);
      expect(await AppPrefs.getOnScreenPadMode(), OnScreenPadMode.never);
    });

    test('a stored pad mode from a future version falls back to auto',
        () async {
      SharedPreferences.setMockInitialValues({'on_screen_pad_mode': 99});
      expect(await AppPrefs.getOnScreenPadMode(), OnScreenPadMode.auto);
    });

    test('the joystick port only ever comes back as 1 or 2', () async {
      await AppPrefs.setJoystickPort(1);
      expect(await AppPrefs.getJoystickPort(), 1);
      // Anything else is clamped on the way in AND on the way out -- a
      // nonsense port means every input silently goes nowhere.
      await AppPrefs.setJoystickPort(7);
      expect(await AppPrefs.getJoystickPort(), 2);
      SharedPreferences.setMockInitialValues({'joystick_port': 0});
      expect(await AppPrefs.getJoystickPort(), 2);
    });

    test('an action button key round-trips, and clears back to fire',
        () async {
      await AppPrefs.setActionButtonKey('a', 1); // Run/Stop
      expect(await AppPrefs.getActionButtonKey('a'), 1);
      // The two buttons are stored separately.
      expect(await AppPrefs.getActionButtonKey('b'), isNull);

      await AppPrefs.setActionButtonKey('a', 0); // Space -- ordinal zero
      expect(await AppPrefs.getActionButtonKey('a'), 0,
          reason: 'ordinal 0 (Space) must not be confused with "unmapped"');

      await AppPrefs.setActionButtonKey('a', null);
      expect(await AppPrefs.getActionButtonKey('a'), isNull);
    });
  });

  group('custom on-screen buttons', () {
    test('keep their keys, and their order, across a restart', () async {
      final buttons = [
        CustomButton.key(C64KeyCatalogue.find(7, 4)!), // SPACE
        CustomButton.key(C64KeyCatalogue.find(7, 7)!), // RUN/STOP
        CustomButton.key(C64KeyCatalogue.find(1, 2)!), // A
      ];
      await AppPrefs.setCustomButtons(buttons);

      final restored = await AppPrefs.getCustomButtons();
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
      final restored = await AppPrefs.getCustomButtons();
      expect(restored.single.label, 'MYSTERY');
      expect(restored.single.key!.row, 6);
      expect(restored.single.key!.column, 3);
    });

    test('a corrupt list costs the buttons, not the app', () async {
      SharedPreferences.setMockInitialValues(
          {'custom_on_screen_buttons': 'not json at all'});
      expect(await AppPrefs.getCustomButtons(), isEmpty);

      SharedPreferences.setMockInitialValues({
        'custom_on_screen_buttons':
            jsonEncode([{'label': 'BAD', 'row': 'one', 'column': null}]),
      });
      expect(await AppPrefs.getCustomButtons(), isEmpty);
    });

    test('joystick directions round-trip alongside keys', () async {
      await AppPrefs.setCustomButtons([
        CustomButton.direction(JoyDirection.up),
        CustomButton.key(C64KeyCatalogue.find(7, 4)!),
      ]);

      final restored = await AppPrefs.getCustomButtons();
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
      final restored = await AppPrefs.getCustomButtons();
      expect(restored.single.isDirection, isFalse);
      expect(restored.single.label, 'SPACE');
    });

    test('an unknown direction name is dropped, not crashed on', () async {
      SharedPreferences.setMockInitialValues({
        'custom_on_screen_buttons': jsonEncode([{'direction': 'sideways'}]),
      });
      expect(await AppPrefs.getCustomButtons(), isEmpty);
    });

    test('clearing the list removes every button', () async {
      await AppPrefs.setCustomButtons(
          [CustomButton.key(C64KeyCatalogue.find(7, 4)!)]);
      await AppPrefs.setCustomButtons([]);
      expect(await AppPrefs.getCustomButtons(), isEmpty);
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
}
