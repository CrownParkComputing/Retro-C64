// The emulator core as the UI sees it.
//
// Everything above this line is plain Dart: screens, widgets and the save
// state service talk to a `ViceCore`, never to `dart:ffi` directly. The one
// real implementation is ViceCoreBindings (vice_bindings.dart), which opens
// libvicecore.so; that class cannot exist at all without the native library
// on disk, which is why the interface is here rather than the concrete type
// being used everywhere.
//
// The immediate payoff is testability -- `flutter test` runs with no native
// library, no device and no game files, so the widget tests hand the
// screens a fake core (test/fakes/fake_vice_core.dart). It also keeps the
// FFI surface honest: anything the UI needs has to be declared here first.
import 'vice_bindings.dart' show FrameSnapshot;

abstract class ViceCore {
  /// Points the core at the directory holding the C64 ROM images.
  void init(String romDir);

  /// Boots (or swaps media on an already-running) machine. Returns 0 on
  /// success. [mediaType] is one of the ViceMedia constants.
  int start({required int mediaType, String? mediaPath, String? commandLine});

  void stop();

  bool get isRunning;

  /// Whether the UI has asked the core to pause. See
  /// ViceCoreBindings.isPaused for why this is tracked on the Dart side.
  bool get isPaused;

  void setPaused(bool paused);

  /// One of the seven fixed key ordinals the bridge's key_event path knows.
  void keyEvent(int key, bool pressed);

  /// Any key, by its position in the C64's 8x8 keyboard matrix.
  void matrixKeyEvent(int row, int column, bool pressed);

  /// port: 1 or 2. mask: bitwise-or of [ViceJoyBits].
  void joystick(int port, int mask);

  int attachDisk(String path);

  int attachTape(String path);

  int saveSnapshot(String path);

  int loadSnapshot(String path);

  /// Whether the attached media can be snapshotted at all; null when the
  /// core is not running.
  bool? get canSnapshot;

  int get audioLevel;

  int get fps;

  /// The current frame, or null before the core has drawn one.
  FrameSnapshot? getFramebuffer();
}
