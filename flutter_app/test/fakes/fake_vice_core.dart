// A [ViceCore] with no native library behind it.
//
// `flutter test` runs on the host with no libvicecore.so, no device and no
// ROMs, so ViceCoreBindings cannot be constructed at all -- opening the
// library is the first thing its constructor does. Everything the screens
// need from the core is declared on the ViceCore interface, so the tests
// hand them this instead and get to assert on what the UI ASKED the core to
// do (which port the joystick went to, which key was pressed) as well as
// what it drew.
import 'dart:typed_data';

import 'package:retro_c64/ffi/vice_bindings.dart';
import 'package:retro_c64/ffi/vice_core.dart';

class FakeViceCore implements ViceCore {
  /// Every joystick(port, mask) call, in order.
  final List<({int port, int mask})> joystickCalls = [];

  /// Every matrixKeyEvent(row, column, pressed) call, in order.
  final List<({int row, int column, bool pressed})> matrixKeys = [];

  final List<({int key, bool pressed})> keyEvents = [];

  int startCount = 0;

  /// The mediaPath of every start(), in order -- swapping a second title into
  /// a running core is a start(), not a stop()/start() pair, so the count
  /// alone cannot say WHICH game is loaded.
  final List<String?> startedPaths = [];
  int stopCount = 0;

  @override
  bool isRunning;

  bool _paused = false;

  @override
  int fps;

  /// The frame [getFramebuffer] hands back. Null -- the default -- means
  /// "no frame yet", which is what a real core reports before it has drawn
  /// one, and keeps FramebufferView's decode/repaint loop out of tests that
  /// are not about the picture.
  FrameSnapshot? frame;

  FakeViceCore({this.isRunning = true, this.fps = 50, bool withFrame = false}) {
    if (withFrame) frame = solidFrame();
  }

  /// A tiny opaque-black frame, enough for FramebufferView to decode and
  /// paint something.
  static FrameSnapshot solidFrame({int width = 8, int height = 8}) =>
      FrameSnapshot(
        width: width,
        height: height,
        argbAsRgba: Uint32List(width * height)..fillRange(0, width * height, 0xFF000000),
      );

  @override
  void init(String romDir) {}

  @override
  int start({required int mediaType, String? mediaPath, String? commandLine}) {
    startCount++;
    startedPaths.add(mediaPath);
    isRunning = true;
    return 0;
  }

  /// VICE's resource table, faked as a plain map. Tests that drive the Core
  /// settings screen seed it; everything else gets "no such resource", which
  /// is exactly what a screen must cope with on a machine that lacks an
  /// option.
  final Map<String, int> resourceInts = {};
  final Map<String, String> resourceStrings = {};

  /// Set false to stand in for a core built before the resource API existed.
  bool resourceApiAvailable = true;

  @override
  bool get hasResourceApi => resourceApiAvailable;

  @override
  int? getResourceInt(String name) =>
      resourceApiAvailable ? resourceInts[name] : null;

  @override
  bool setResourceInt(String name, int value) {
    if (!resourceInts.containsKey(name)) return false;
    resourceInts[name] = value;
    return true;
  }

  @override
  String? getResourceString(String name) => resourceStrings[name];

  @override
  bool setResourceString(String name, String value) {
    if (!resourceStrings.containsKey(name)) return false;
    resourceStrings[name] = value;
    return true;
  }

  /// Where a dump would have been written, so a test can assert the screen
  /// asked for one. Writing the file itself is the real core's job.
  String? dumpedTo;

  @override
  bool dumpResources(String path) {
    dumpedTo = path;
    return isRunning;
  }

  @override
  void stop() {
    stopCount++;
    isRunning = false;
  }

  @override
  bool get isPaused => _paused;

  @override
  void setPaused(bool paused) => _paused = paused;

  @override
  void keyEvent(int key, bool pressed) =>
      keyEvents.add((key: key, pressed: pressed));

  @override
  void matrixKeyEvent(int row, int column, bool pressed) =>
      matrixKeys.add((row: row, column: column, pressed: pressed));

  @override
  void joystick(int port, int mask) =>
      joystickCalls.add((port: port, mask: mask));

  @override
  int attachDisk(String path) => 0;

  @override
  int attachTape(String path) => 0;

  @override
  int saveSnapshot(String path) => 0;

  @override
  int loadSnapshot(String path) => 0;

  @override
  bool? get canSnapshot => isRunning ? true : null;

  @override
  int get audioLevel => 0;

  /// Settable so widget tests can drive the loading indicators without a
  /// real core.
  MediaActivity mediaActivityValue = MediaActivity.idle;

  @override
  MediaActivity get mediaActivity => mediaActivityValue;

  @override
  FrameSnapshot? getFramebuffer() => frame;
}
