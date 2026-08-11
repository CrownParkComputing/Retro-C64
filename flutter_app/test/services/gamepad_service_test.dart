// Gamepad -> C64 joystick mask.
//
// The stick Y axis shipped inverted, because the convention was guessed
// with no controller plugged in: up and down were swapped on every real
// pad. The convention is now pinned here, where getting it wrong is a
// failing test rather than a device session.
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepads/gamepads.dart';
import 'package:vice_multiplatform/ffi/vice_bindings.dart';
import 'package:vice_multiplatform/services/gamepad_service.dart';

NormalizedGamepadEvent buttonEvent(GamepadButton button, double value) =>
    NormalizedGamepadEvent(
      gamepadId: 'test-pad',
      timestamp: 0,
      value: value,
      button: button,
      rawEvent: GamepadEvent(
        gamepadId: 'test-pad',
        timestamp: 0,
        type: KeyType.button,
        key: button.name,
        value: value,
      ),
    );

NormalizedGamepadEvent axisEvent(GamepadAxis axis, double value) =>
    NormalizedGamepadEvent(
      gamepadId: 'test-pad',
      timestamp: 0,
      value: value,
      axis: axis,
      rawEvent: GamepadEvent(
        gamepadId: 'test-pad',
        timestamp: 0,
        type: KeyType.analog,
        key: axis.name,
        value: value,
      ),
    );

void main() {
  late GamepadService service;
  late List<int> masks;

  setUp(() {
    service = GamepadService();
    masks = [];
    service.maskChanges.listen(masks.add);
  });

  tearDown(() => service.dispose());

  /// The mask after feeding [events], as the emulator screen would see it.
  Future<int> maskAfter(List<NormalizedGamepadEvent> events) async {
    for (final e in events) {
      service.handleEvent(e);
    }
    // The mask is delivered on a broadcast stream, so let it drain.
    await Future<void>.delayed(Duration.zero);
    return masks.isEmpty ? 0 : masks.last;
  }

  group('left stick', () {
    test('pushing UP is a NEGATIVE Y value', () async {
      // SDL / Android MotionEvent.AXIS_Y convention: Y points DOWN the
      // screen. Guessing the other way is what swapped up and down.
      expect(await maskAfter([axisEvent(GamepadAxis.leftStickY, -1.0)]),
          ViceJoyBits.up);
    });

    test('pulling DOWN is a POSITIVE Y value', () async {
      expect(await maskAfter([axisEvent(GamepadAxis.leftStickY, 1.0)]),
          ViceJoyBits.down);
    });

    test('left and right follow X the obvious way round', () async {
      expect(await maskAfter([axisEvent(GamepadAxis.leftStickX, -1.0)]),
          ViceJoyBits.left);
      expect(await maskAfter([axisEvent(GamepadAxis.leftStickX, 1.0)]),
          ViceJoyBits.right);
    });

    test('a resting stick presses nothing (dead zone)', () async {
      // Small idle drift must not press a direction -- and must not even
      // emit a mask, or every stray reading wakes the emulator screen.
      expect(
          await maskAfter([
            axisEvent(GamepadAxis.leftStickX, 0.2),
            axisEvent(GamepadAxis.leftStickY, -0.3),
          ]),
          0);
      expect(masks, isEmpty);
    });

    test('diagonals report both directions at once', () async {
      final mask = await maskAfter([
        axisEvent(GamepadAxis.leftStickX, 1.0),
        axisEvent(GamepadAxis.leftStickY, -1.0),
      ]);
      expect(mask, ViceJoyBits.right | ViceJoyBits.up);
    });

    test('releasing the stick clears the direction again', () async {
      await maskAfter([axisEvent(GamepadAxis.leftStickY, -1.0)]);
      expect(await maskAfter([axisEvent(GamepadAxis.leftStickY, 0.0)]), 0);
    });
  });

  group('buttons', () {
    test('the d-pad drives the four directions', () async {
      expect(await maskAfter([buttonEvent(GamepadButton.dpadUp, 1)]),
          ViceJoyBits.up);
      expect(await maskAfter([buttonEvent(GamepadButton.dpadUp, 0)]), 0);
      expect(await maskAfter([buttonEvent(GamepadButton.dpadDown, 1)]),
          ViceJoyBits.down);
      expect(await maskAfter([buttonEvent(GamepadButton.dpadDown, 0)]), 0);
      expect(await maskAfter([buttonEvent(GamepadButton.dpadLeft, 1)]),
          ViceJoyBits.left);
      expect(await maskAfter([buttonEvent(GamepadButton.dpadLeft, 0)]), 0);
      expect(await maskAfter([buttonEvent(GamepadButton.dpadRight, 1)]),
          ViceJoyBits.right);
    });

    test('A and B are the two fire buttons', () async {
      expect(await maskAfter([buttonEvent(GamepadButton.a, 1)]),
          ViceJoyBits.fire1);
      expect(await maskAfter([buttonEvent(GamepadButton.b, 1)]),
          ViceJoyBits.fire1 | ViceJoyBits.fire2);
    });

    test('an unmapped button changes nothing', () async {
      await maskAfter([buttonEvent(GamepadButton.a, 1)]);
      final before = masks.length;
      await maskAfter([buttonEvent(GamepadButton.start, 1)]);
      // No new mask was emitted at all -- not merely the same value again.
      expect(masks.length, before);
      expect(masks.last, ViceJoyBits.fire1);
    });

    test('the d-pad and a held fire button coexist', () async {
      final mask = await maskAfter([
        buttonEvent(GamepadButton.a, 1),
        buttonEvent(GamepadButton.dpadLeft, 1),
      ]);
      expect(mask, ViceJoyBits.fire1 | ViceJoyBits.left);
    });
  });
}
