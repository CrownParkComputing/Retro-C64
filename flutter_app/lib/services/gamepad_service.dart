// External gamepad/joystick support, port of MainActivity's
// SOURCE_JOYSTICK/SOURCE_GAMEPAD/SOURCE_DPAD handling (~line 4047-4210 of
// the Android original). Android reads InputDevice motion/key events
// directly; Flutter has no first-party equivalent, so this uses the
// `gamepads` package (github.com/flame-engine/gamepads), which supports
// Linux desktop, Android, iOS, macOS, Windows, and Web with a normalized
// button/axis model.
//
// Originally written without a controller to test against, which is how the
// stick Y axis ended up inverted (see the axis handling below). Detection and
// button mapping have since been exercised on real hardware: an Xbox
// Wireless Controller on Linux and the Retroid Pocket Flip2's built-in pad on
// Android. Treat any remaining axis/button convention here as verified only
// for those two pads.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gamepads/gamepads.dart';

import '../ffi/vice_bindings.dart';

class GamepadService {
  StreamSubscription<NormalizedGamepadEvent>? _sub;
  Timer? _pollTimer;
  final _maskController = StreamController<int>.broadcast();
  int _mask = 0;
  double _stickX = 0, _stickY = 0;

  /// Whether Gamepads.list() currently reports any connected controller.
  /// Polled (the package doesn't expose a connect/disconnect stream) --
  /// used to auto-hide the on-screen virtual joystick/action buttons when a
  /// real controller is present, matching a reasonable reading of the
  /// Android original's intent (it never shows virtual controls at all,
  /// having no touchscreen assumption baked in the same way).
  final ValueNotifier<bool> connected = ValueNotifier(false);

  /// Port-1 joystick mask contributed by the external gamepad (same
  /// ViceJoyBits shape as the virtual joystick/action buttons). The
  /// listener is responsible for OR-ing this with the other input sources
  /// before calling ViceCoreBindings.joystick -- this service does not call
  /// the core directly so it can't stomp on the virtual controls' state.
  Stream<int> get maskChanges => _maskController.stream;

  void start() {
    _sub = Gamepads.normalizedEvents.listen(handleEvent, onError: (_) {
      // Best-effort: some platforms/sandboxes may not support gamepad
      // enumeration at all (no /dev/input access, no permission, etc).
      // Swallow rather than crash the emulator screen.
    });
    _pollConnection();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollConnection());
  }

  Future<void> _pollConnection() async {
    try {
      final list = await Gamepads.list();
      connected.value = list.isNotEmpty;
    } catch (_) {
      // See start()'s onError comment.
    }
  }

  void _setBit(int bit, bool on) {
    final next = on ? (_mask | bit) : (_mask & ~bit);
    if (next == _mask) return;
    _mask = next;
    _maskController.add(_mask);
  }

  /// Folds one normalized pad event into the joystick mask.
  ///
  /// Public (and directly exercised by test/services/gamepad_service_test.dart)
  /// because the axis convention here is the sort of thing that gets guessed
  /// wrong -- the stick Y axis WAS guessed wrong, and up/down came out
  /// swapped on every real pad until someone plugged one in.
  @visibleForTesting
  void handleEvent(NormalizedGamepadEvent event) {
    final button = event.button;
    if (button != null) {
      final down = event.value != 0;
      switch (button) {
        case GamepadButton.dpadUp:
          _setBit(ViceJoyBits.up, down);
          break;
        case GamepadButton.dpadDown:
          _setBit(ViceJoyBits.down, down);
          break;
        case GamepadButton.dpadLeft:
          _setBit(ViceJoyBits.left, down);
          break;
        case GamepadButton.dpadRight:
          _setBit(ViceJoyBits.right, down);
          break;
        case GamepadButton.a:
          _setBit(ViceJoyBits.fire1, down);
          break;
        case GamepadButton.b:
          _setBit(ViceJoyBits.fire2, down);
          break;
        default:
          break;
      }
      return;
    }

    final axis = event.axis;
    if (axis == GamepadAxis.leftStickX) {
      _stickX = event.value;
    } else if (axis == GamepadAxis.leftStickY) {
      _stickY = event.value;
    } else {
      return;
    }
    const deadZone = 0.35;
    _setBit(ViceJoyBits.left, _stickX < -deadZone);
    _setBit(ViceJoyBits.right, _stickX > deadZone);
    // Stick Y here is Up = POSITIVE.
    //
    // Not the raw Android convention -- these events are NORMALIZED ones. The
    // gamepads package has already flipped the sign for us: android_mapping's
    // normalizeAxis returns -value for leftStickY/rightStickY, commented
    // "Y-axis is inverted on Android (up = negative)". By the time an event
    // reaches this method the inversion has happened, and inverting again
    // puts it back where it started.
    //
    // This file has now been wrong in both directions. It was first written
    // as Up = +1 by guesswork; that was then "corrected" to the raw Android
    // convention, which is right about the hardware and wrong about this API,
    // and swapped up and down on an Xbox pad. The unit test moved with it and
    // kept agreeing, because it fed raw-convention values into
    // raw-convention code -- two halves of the same mistake confirming each
    // other. Verified against the pad the bug was reported on: an Xbox
    // Wireless Controller on a Retroid Pocket Flip2.
    _setBit(ViceJoyBits.up, _stickY > deadZone);
    _setBit(ViceJoyBits.down, _stickY < -deadZone);
  }

  void dispose() {
    _sub?.cancel();
    _pollTimer?.cancel();
    _maskController.close();
    connected.dispose();
  }
}
