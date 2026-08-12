// dart:ffi bindings to native/vice_core/bridge/vice_bridge.h
//
// This binds the plain-C x64sc game core (libvicecore.so). The vsid
// (SID-player) core has an analogous header (vice_vsid_bridge.h) and is not
// wired up yet in this pass -- the Music tab in this Flutter build is UI
// only, matching the Android app visually but not driving real SID audio.
//
// TODO(bundling): for now this loads libvicecore.so via a path computed
// relative to the Flutter project directory (see ViceLibraryPaths below),
// which only works for `flutter run -d linux` from a checkout that has
// native/vice_core/linux/build/libvicecore.so already built. Proper
// packaging (bundling the .so next to the produced Linux binary, and the
// equivalent for Android/iOS via jniLibs / an xcframework) is deferred to a
// later milestone.
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import 'vice_core.dart';

/// Snapshot result codes, mirroring the #defines in vice_bridge.h.
class ViceSnapshotResult {
  static const int ok = 0;

  /// The core did not service the request within its 10s timeout.
  static const int timeout = -2;

  /// The attached media cannot be snapshotted in a way that would restore
  /// (today: T64 tape images, which VICE has no snapshot support for). No
  /// file was written -- offer the user a restart, not a resume.
  static const int unsupportedMedia = -3;
}

/// Media type constants, mirroring the #defines in vice_bridge.h.
class ViceMedia {
  static const int prg = 0;
  static const int disk = 1;
  static const int tape = 2;
  static const int none = -1;
}

// --- Native function signatures (C side) -----------------------------------

typedef _VoidInitNative = Void Function(Pointer<Utf8> romDir);
typedef _VoidInitDart = void Function(Pointer<Utf8> romDir);

typedef _StartNative = Int32 Function(
    Int32 mediaType, Pointer<Utf8> mediaPath, Pointer<Utf8> commandLine);
typedef _StartDart = int Function(
    int mediaType, Pointer<Utf8> mediaPath, Pointer<Utf8> commandLine);

typedef _VoidVoidNative = Void Function();
typedef _VoidVoidDart = void Function();

typedef _Int32VoidNative = Int32 Function();
typedef _Int32VoidDart = int Function();

typedef _SetPausedNative = Void Function(Int32 paused);
typedef _SetPausedDart = void Function(int paused);

typedef _KeyEventNative = Void Function(Int32 key, Int32 pressed);
typedef _KeyEventDart = void Function(int key, int pressed);

typedef _MatrixKeyEventNative = Void Function(
    Int32 row, Int32 column, Int32 pressed);
typedef _MatrixKeyEventDart = void Function(
    int row, int column, int pressed);

typedef _JoystickNative = Void Function(Int32 port, Int32 mask);
typedef _JoystickDart = void Function(int port, int mask);

typedef _AttachNative = Int32 Function(Pointer<Utf8> path);
typedef _AttachDart = int Function(Pointer<Utf8> path);

typedef _SnapshotNative = Int32 Function(Pointer<Utf8> path);
typedef _SnapshotDart = int Function(Pointer<Utf8> path);

typedef _GetFramebufferNative = Pointer<Uint32> Function(
    Pointer<Int32> outWidth, Pointer<Int32> outHeight);
typedef _GetFramebufferDart = Pointer<Uint32> Function(
    Pointer<Int32> outWidth, Pointer<Int32> outHeight);

/// Joystick direction/fire bit masks, matching vice_bridge.h's comment on
/// vice_core_joystick().
class ViceJoyBits {
  static const int up = 0x01;
  static const int down = 0x02;
  static const int left = 0x04;
  static const int right = 0x08;
  static const int fire1 = 0x10;
  static const int fire2 = 0x20;
}

/// Thin, mostly-mechanical wrapper around libvicecore.so's C ABI.
///
/// One instance == one loaded copy of the game core. There is no vsid
/// binding here (see file header) -- add a sibling class for
/// libvicecore_vsid.so, following vice_vsid_bridge.h, when the Music tab
/// needs to actually play audio.
class ViceCoreBindings implements ViceCore {
  final DynamicLibrary _lib;

  late final _VoidInitDart _init;
  late final _StartDart _start;
  late final _VoidVoidDart _stop;
  late final _Int32VoidDart _isRunning;
  late final _SetPausedDart _setPaused;
  late final _KeyEventDart _keyEvent;
  late final _MatrixKeyEventDart _matrixKeyEvent;
  late final _JoystickDart _joystick;
  late final _AttachDart _attachDisk;
  late final _AttachDart _attachTape;
  late final _SnapshotDart _saveSnapshot;
  late final _SnapshotDart _loadSnapshot;
  late final _Int32VoidDart _canSnapshot;
  late final _GetFramebufferDart _getFramebuffer;
  late final _Int32VoidDart _getAudioLevel;
  late final _Int32VoidDart _getFps;
  late final _Int32VoidDart _getTapeCounter;
  late final _Int32VoidDart _getTapeMotor;
  late final _Int32VoidDart _getDriveHalfTrack;
  late final _Int32VoidDart _getDriveLed;

  ViceCoreBindings._(this._lib) {
    _init = _lib
        .lookup<NativeFunction<_VoidInitNative>>('vice_core_init')
        .asFunction();
    _start = _lib
        .lookup<NativeFunction<_StartNative>>('vice_core_start')
        .asFunction();
    _stop = _lib
        .lookup<NativeFunction<_VoidVoidNative>>('vice_core_stop')
        .asFunction();
    _isRunning = _lib
        .lookup<NativeFunction<_Int32VoidNative>>('vice_core_is_running')
        .asFunction();
    _setPaused = _lib
        .lookup<NativeFunction<_SetPausedNative>>('vice_core_set_paused')
        .asFunction();
    _keyEvent = _lib
        .lookup<NativeFunction<_KeyEventNative>>('vice_core_key_event')
        .asFunction();
    _matrixKeyEvent = _lib
        .lookup<NativeFunction<_MatrixKeyEventNative>>(
            'vice_core_matrix_key_event')
        .asFunction();
    _joystick = _lib
        .lookup<NativeFunction<_JoystickNative>>('vice_core_joystick')
        .asFunction();
    _attachDisk = _lib
        .lookup<NativeFunction<_AttachNative>>('vice_core_attach_disk')
        .asFunction();
    _attachTape = _lib
        .lookup<NativeFunction<_AttachNative>>('vice_core_attach_tape')
        .asFunction();
    _saveSnapshot = _lib
        .lookup<NativeFunction<_SnapshotNative>>('vice_core_save_snapshot')
        .asFunction();
    _loadSnapshot = _lib
        .lookup<NativeFunction<_SnapshotNative>>('vice_core_load_snapshot')
        .asFunction();
    _canSnapshot = _lib
        .lookup<NativeFunction<_Int32VoidNative>>('vice_core_can_snapshot')
        .asFunction();
    _getFramebuffer = _lib
        .lookup<NativeFunction<_GetFramebufferNative>>(
            'vice_core_get_framebuffer')
        .asFunction();
    _getAudioLevel = _lib
        .lookup<NativeFunction<_Int32VoidNative>>('vice_core_get_audio_level')
        .asFunction();
    _getTapeCounter = _lib
        .lookup<NativeFunction<_Int32VoidNative>>('vice_core_get_tape_counter')
        .asFunction();
    _getTapeMotor = _lib
        .lookup<NativeFunction<_Int32VoidNative>>('vice_core_get_tape_motor')
        .asFunction();
    _getDriveHalfTrack = _lib
        .lookup<NativeFunction<_Int32VoidNative>>(
            'vice_core_get_drive_half_track')
        .asFunction();
    _getDriveLed = _lib
        .lookup<NativeFunction<_Int32VoidNative>>('vice_core_get_drive_led')
        .asFunction();
    _getFps = _lib
        .lookup<NativeFunction<_Int32VoidNative>>('vice_core_get_fps')
        .asFunction();
  }

  /// Loads libvicecore(.so|.dll|.dylib) from [libraryPath], or by bare name
  /// if [libraryPath] is null (relies on the OS loader / rpath).
  factory ViceCoreBindings.load({String? libraryPath}) {
    final DynamicLibrary lib;
    if (Platform.isLinux) {
      lib = DynamicLibrary.open(libraryPath ?? 'libvicecore.so');
    } else if (Platform.isAndroid) {
      lib = DynamicLibrary.open(libraryPath ?? 'libvicecore.so');
    } else if (Platform.isIOS) {
      // The core ships as libvicecore.dylib inside the app bundle's
      // Frameworks dir (see ViceNativePaths.gameCoreLibraryPath). It is not
      // linked into the Runner executable, so process() would not see it --
      // dlopen it by path. Falls back to process() for a build that does link
      // it statically.
      lib = libraryPath != null
          ? DynamicLibrary.open(libraryPath)
          : DynamicLibrary.process();
    } else if (Platform.isMacOS) {
      lib = DynamicLibrary.process();
    } else if (Platform.isWindows) {
      lib = DynamicLibrary.open(libraryPath ?? 'vicecore.dll');
    } else {
      throw UnsupportedError(
          'ViceCoreBindings.load: unsupported platform ${Platform.operatingSystem}');
    }
    return ViceCoreBindings._(lib);
  }

  @override
  void init(String romDir) {
    final p = romDir.toNativeUtf8();
    try {
      _init(p);
    } finally {
      malloc.free(p);
    }
  }

  /// Returns 0 on success, -1 if the core was already started.
  @override
  int start({required int mediaType, String? mediaPath, String? commandLine}) {
    final pMedia = mediaPath?.toNativeUtf8() ?? nullptr;
    final pCmd = commandLine?.toNativeUtf8() ?? nullptr;
    try {
      return _start(mediaType, pMedia, pCmd);
    } finally {
      if (pMedia != nullptr) malloc.free(pMedia);
      if (pCmd != nullptr) malloc.free(pCmd);
    }
  }

  @override
  void stop() => _stop();

  @override
  bool get isRunning => _isRunning() != 0;

  /// Mirrors the pause flag we've pushed into the core. The native side owns
  /// the real gate but exposes no getter, and callers need to know whether a
  /// pause was already in effect before pausing it themselves -- e.g.
  /// backgrounding the app must not un-pause a game the user had
  /// deliberately left paused in the workbench.
  bool _paused = false;
  @override
  bool get isPaused => _paused;

  @override
  void setPaused(bool paused) {
    _paused = paused;
    _setPaused(paused ? 1 : 0);
  }

  @override
  void keyEvent(int key, bool pressed) => _keyEvent(key, pressed ? 1 : 0);

  @override
  void matrixKeyEvent(int row, int column, bool pressed) =>
      _matrixKeyEvent(row, column, pressed ? 1 : 0);

  /// port: 1 or 2. mask: bitwise-or of ViceJoyBits.
  @override
  void joystick(int port, int mask) => _joystick(port, mask);

  @override
  int attachDisk(String path) {
    final p = path.toNativeUtf8();
    try {
      return _attachDisk(p);
    } finally {
      malloc.free(p);
    }
  }

  @override
  int attachTape(String path) {
    final p = path.toNativeUtf8();
    try {
      return _attachTape(p);
    } finally {
      malloc.free(p);
    }
  }

  /// Writes a full VICE machine snapshot to [path] so the title can later
  /// be resumed at the exact cycle it was left at. Returns 0 on success.
  ///
  /// Blocking: the native side hands the request to the core's own thread
  /// and waits for it (VICE machine state may only be touched there), with
  /// a 10s timeout on the native side so this can never hang forever. In
  /// practice a C64 snapshot is a couple of hundred KB and completes within
  /// a frame or two.
  @override
  int saveSnapshot(String path) {
    final p = path.toNativeUtf8();
    try {
      return _saveSnapshot(p);
    } finally {
      malloc.free(p);
    }
  }

  /// Whether the media attached to the running machine can be snapshotted at
  /// all. False means a later [saveSnapshot] will return
  /// [ViceSnapshotResult.unsupportedMedia], so the UI should offer a restart
  /// rather than a resume. Null when the core is not running (unknown).
  @override
  bool? get canSnapshot => switch (_canSnapshot()) {
        1 => true,
        0 => false,
        _ => null,
      };

  /// Restores a snapshot previously written by [saveSnapshot]. Returns 0 on
  /// success. Same threading/blocking notes as [saveSnapshot].
  ///
  /// On success the native side has already waited for the restored machine
  /// to draw fresh frames, so the framebuffer read straight after this call
  /// shows the restored picture rather than the one from before.
  @override
  int loadSnapshot(String path) {
    final p = path.toNativeUtf8();
    try {
      return _loadSnapshot(p);
    } finally {
      malloc.free(p);
    }
  }

  @override
  int get audioLevel => _getAudioLevel();

  @override
  int get fps => _getFps();

  @override
  MediaActivity get mediaActivity => MediaActivity(
        tapeCounter: _getTapeCounter(),
        tapeMotorOn: _getTapeMotor() != 0,
        // Half-tracks: 36 is track 18. Whole tracks are what a loader screen
        // shows, so halve it.
        driveTrack: _getDriveHalfTrack() ~/ 2,
        // pwm1 is 0..1000 intensity. Anything lit at all means the head is
        // working; a strict ==1000 would miss most of a real load.
        driveActive: _getDriveLed() > 0,
      );

  /// Snapshot of the current RGBA8888 framebuffer, copied into a Dart
  /// Uint32List (safe to keep after this call returns, unlike the raw
  /// pointer). Returns null until the core has rendered at least one frame.
  @override
  FrameSnapshot? getFramebuffer() {
    final outW = malloc<Int32>();
    final outH = malloc<Int32>();
    try {
      final ptr = _getFramebuffer(outW, outH);
      if (ptr == nullptr) return null;
      final w = outW.value;
      final h = outH.value;
      if (w <= 0 || h <= 0) return null;
      // Copy out of native memory: the bridge owns this buffer and mutates
      // it every frame on its own thread, so we must not hand the raw
      // pointer to Flutter's image pipeline.
      final words = ptr.asTypedList(w * h);
      final copy = Uint32List.fromList(words);
      return FrameSnapshot(width: w, height: h, argbAsRgba: copy);
    } finally {
      malloc.free(outW);
      malloc.free(outH);
    }
  }
}

/// A copied RGBA8888 frame, width/height in pixels.
class FrameSnapshot {
  final int width;
  final int height;
  final Uint32List argbAsRgba;
  const FrameSnapshot(
      {required this.width, required this.height, required this.argbAsRgba});
}
