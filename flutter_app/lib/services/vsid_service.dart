// Lazily-loaded singleton wrapper around ViceVsidBindings, used by
// music_screen.dart to drive real SID playback.
//
// The vsid core is a full second static link of the VICE base objects
// (see vice_vsid_bindings.dart's file header for why it can't share a
// binary with the game core), so this is deliberately NOT loaded at app
// startup the way the game core is in main.dart -- it's loaded the first
// time the Music tab actually tries to play something, via [ensureLoaded].
// If loading or init fails (missing .so, missing ROMs) [loadError] is set
// and every play attempt is a no-op, rather than crashing the app.
import '../ffi/vice_native_paths.dart';
import '../ffi/vice_vsid_bindings.dart';

class VsidService {
  VsidService._();
  static final VsidService instance = VsidService._();

  ViceVsidBindings? _bindings;
  String? _loadError;
  String? _currentPath;
  bool _paused = false;

  String? get loadError => _loadError;
  bool get isAvailable => _bindings != null;
  String? get currentPath => _currentPath;
  bool get isPaused => _paused;

  /// Loads libvicecore_vsid.so and calls vice_vsid_init() exactly once.
  /// Safe to call repeatedly (no-op after the first successful or failed
  /// attempt). Returns true if the vsid core is ready to play.
  ///
  /// Async because ROM-dir resolution is async on Android and iOS (first-run
  /// extraction -- see ViceNativePaths.resolveRomDir); on other platforms
  /// this just awaits an already-completed Future.
  Future<bool> ensureLoaded() async {
    if (_bindings != null) return true;
    if (_loadError != null) return false;
    try {
      final libPath = ViceNativePaths.vsidCoreLibraryPath;
      final romDir = await ViceNativePaths.resolveRomDir();
      final bindings = ViceVsidBindings.load(libraryPath: libPath);
      if (romDir == null) {
        _loadError = 'No ROM directory found (need a C64/ subdir with '
            'kernal/basic/chargen).';
        return false;
      }
      bindings.init(romDir);
      _bindings = bindings;
      return true;
    } catch (e) {
      _loadError = e.toString();
      return false;
    }
  }

  /// Starts (or hot-swaps to) [sidPath]. Returns true on success.
  bool play(String sidPath) {
    final b = _bindings;
    if (b == null) return false;
    final result = b.launch(sidPath);
    if (result != 0) return false;
    _currentPath = sidPath;
    _paused = false;
    b.setPaused(false);
    return true;
  }

  /// Toggles pause on whatever is currently loaded. No-op if nothing has
  /// been played yet.
  void togglePause() {
    final b = _bindings;
    if (b == null || _currentPath == null) return;
    _paused = !_paused;
    b.setPaused(_paused);
  }

  /// Unconditionally pauses SID playback (no-op if nothing is loaded or it's
  /// already paused). Unlike [togglePause], this never turns playback back
  /// ON, so it's safe to call from anywhere that just wants to guarantee
  /// music isn't playing (e.g. right before a game core starts, mirroring
  /// the original Android app's "Stop SID music when launching a game"
  /// behavior: ViceVsid.setPaused(true) in loadMedia() before C64Native.launch).
  void pause() {
    final b = _bindings;
    if (b == null || _currentPath == null) return;
    if (_paused) return;
    _paused = true;
    b.setPaused(true);
  }

  bool get isRunning => _bindings?.isRunning ?? false;

  int get audioLevel => _bindings?.audioLevel ?? 0;
}
