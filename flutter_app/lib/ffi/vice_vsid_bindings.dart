// dart:ffi bindings to native/vice_core/bridge/vice_vsid_bridge.h -- the
// standalone SID-file player ("vsid") core, built as a SEPARATE shared
// library (libvicecore_vsid.so) from the game core (libvicecore.so, see
// vice_bindings.dart). It is a full independent static link of the VICE
// base objects with a different machine table (VICE_MACHINE_VSID vs
// VICE_MACHINE_C64), so it cannot be linked into the same binary as the
// game core, and (per native/vice_core/linux/viewer/sdl_viewer.c's header
// comment) both .so files export the same global symbol names with
// different definitions.
//
// Whether loading BOTH libvicecore.so and libvicecore_vsid.so into one
// process (as this Flutter app does -- the game core is loaded eagerly at
// startup in main.dart, this vsid binding is loaded lazily the first time
// the Music tab is used) actually works was verified empirically before
// wiring this up: a standalone C harness (dlopen both with plain
// RTLD_NOW|RTLD_LOCAL, i.e. weaker isolation than sdl_viewer.c's
// RTLD_DEEPBIND, which is what dart:ffi's DynamicLibrary.open effectively
// does under the hood) ran vice_core_start(no media) and
// vice_vsid_launch(Commando.sid) CONCURRENTLY -- both mainloops running at
// once, for 5+ seconds -- with no crash, both cores independently reporting
// is_running()==1, and the vsid core producing real (non-zero, varying)
// audio_level() the whole time. So this binding does not attempt to
// serialize game-core and vsid-core activity; both may run at once.
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef _VoidInitNative = Void Function(Pointer<Utf8> romDir);
typedef _VoidInitDart = void Function(Pointer<Utf8> romDir);

typedef _LaunchNative = Int32 Function(
    Pointer<Utf8> mediaPath, Pointer<Utf8> commandLine);
typedef _LaunchDart = int Function(
    Pointer<Utf8> mediaPath, Pointer<Utf8> commandLine);

typedef _SetPausedNative = Void Function(Int32 paused);
typedef _SetPausedDart = void Function(int paused);

typedef _Int32VoidNative = Int32 Function();
typedef _Int32VoidDart = int Function();

/// Thin, mostly-mechanical wrapper around libvicecore_vsid.so's C ABI --
/// sibling of ViceCoreBindings (vice_bindings.dart) for the vsid (SID-file
/// player) core. One instance == one loaded copy of libvicecore_vsid.so.
class ViceVsidBindings {
  final DynamicLibrary _lib;

  late final _VoidInitDart _init;
  late final _LaunchDart _launch;
  late final _SetPausedDart _setPaused;
  late final _Int32VoidDart _isRunning;
  late final _Int32VoidDart _getAudioLevel;
  late final _Int32VoidDart _getFps;

  ViceVsidBindings._(this._lib) {
    _init = _lib
        .lookup<NativeFunction<_VoidInitNative>>('vice_vsid_init')
        .asFunction();
    _launch = _lib
        .lookup<NativeFunction<_LaunchNative>>('vice_vsid_launch')
        .asFunction();
    _setPaused = _lib
        .lookup<NativeFunction<_SetPausedNative>>('vice_vsid_set_paused')
        .asFunction();
    _isRunning = _lib
        .lookup<NativeFunction<_Int32VoidNative>>('vice_vsid_is_running')
        .asFunction();
    _getAudioLevel = _lib
        .lookup<NativeFunction<_Int32VoidNative>>('vice_vsid_get_audio_level')
        .asFunction();
    _getFps = _lib
        .lookup<NativeFunction<_Int32VoidNative>>('vice_vsid_get_fps')
        .asFunction();
  }

  /// Loads libvicecore_vsid(.so|.dll|.dylib) from [libraryPath], or by bare
  /// name if [libraryPath] is null.
  factory ViceVsidBindings.load({String? libraryPath}) {
    final DynamicLibrary lib;
    if (Platform.isLinux) {
      lib = DynamicLibrary.open(libraryPath ?? 'libvicecore_vsid.so');
    } else if (Platform.isAndroid) {
      lib = DynamicLibrary.open(libraryPath ?? 'libvicecore_vsid.so');
    } else if (Platform.isIOS) {
      // Bundled in Runner.app/Frameworks rather than linked into the Runner
      // binary, so it has to be dlopened by path -- same as the game core.
      lib = libraryPath != null
          ? DynamicLibrary.open(libraryPath)
          : DynamicLibrary.process();
    } else if (Platform.isMacOS) {
      lib = DynamicLibrary.process();
    } else if (Platform.isWindows) {
      lib = DynamicLibrary.open(libraryPath ?? 'vicecore_vsid.dll');
    } else {
      throw UnsupportedError(
          'ViceVsidBindings.load: unsupported platform ${Platform.operatingSystem}');
    }
    return ViceVsidBindings._(lib);
  }

  void init(String romDir) {
    final p = romDir.toNativeUtf8();
    try {
      _init(p);
    } finally {
      malloc.free(p);
    }
  }

  /// Starts (or, if already running, hot-swaps) playback of [sidPath].
  /// Returns 0 on success, -1 on failure.
  int launch(String sidPath) {
    final pMedia = sidPath.toNativeUtf8();
    try {
      return _launch(pMedia, nullptr);
    } finally {
      malloc.free(pMedia);
    }
  }

  void setPaused(bool paused) => _setPaused(paused ? 1 : 0);

  bool get isRunning => _isRunning() != 0;

  int get audioLevel => _getAudioLevel();

  int get fps => _getFps();
}
