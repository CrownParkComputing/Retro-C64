import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../data/category.dart';
import '../data/custom_button.dart';
import '../data/emulator_ui_state.dart';
import '../data/media_entry.dart';
import '../ffi/vice_bindings.dart';
import '../ffi/vice_core.dart';
import '../ffi/vice_native_paths.dart';
import '../services/app_log.dart';
import '../services/app_prefs.dart';
import '../services/gamepad_service.dart';
import '../services/library_scanner.dart';
import '../services/media_folder.dart';
import '../services/music_library.dart';
import '../services/permissions_service.dart';
import '../services/platform_info.dart';
import '../services/save_state_service.dart';
import '../services/service_locator.dart';
import '../services/storage_access.dart';
import '../services/vsid_service.dart';
import '../screens/setup_wizard_screen.dart' show kGamesImportSubdir;

class WorkbenchViewModel extends ChangeNotifier {
  final ViceCore core;
  final GamepadService gamepad = getIt<GamepadService>();
  final EmulatorUiState emulatorUi = EmulatorUiState();

  WorkbenchCategory _category = WorkbenchCategory.games;
  List<MediaEntry> _library = [];
  int _unreadableCount = 0;
  bool _inEmulator = false;
  bool _chromeVisible = true;
  bool _sidebarHidden = false;
  bool _screensaverActive = false;
  bool _driveRomInstalled = true;
  bool _isLibraryLoading = false;

  Timer? _chromeTimer;
  Timer? _idleTimer;
  static const _backdropIdleDelay = Duration(milliseconds: 30000);

  MediaEntry? _currentEntry;
  String _emulatorLabel = '';
  String _lastMediaName = '';

  bool _leftHanded = false;
  OnScreenPadMode _padMode = OnScreenPadMode.auto;
  int _joystickPort = 2;
  List<CustomButton> _customButtons = const [];

  WorkbenchViewModel({required this.core}) {
    _init();
  }

  Future<void> _init() async {
    await _refreshDriveRomState();
    await _loadInputPrefs();
    // The library does NOT wait for the music.
    //
    // These were awaited in sequence, which made the games list hostage to
    // the audio stack: anything slow or unavailable there -- a device still
    // opening its audio device, a test with no audio plugin -- left the
    // library spinning forever, because scanLibrary() never got to run. They
    // are unrelated jobs and there is no reason for one to gate the other.
    unawaited(_startWorkbenchMusic());
    await scanLibrary();
    scheduleIdle();
    gamepad.start();
  }

  // Getters
  WorkbenchCategory get category => _category;
  List<MediaEntry> get library => _library;
  int get unreadableCount => _unreadableCount;
  bool get inEmulator => _inEmulator;
  bool get chromeVisible => _chromeVisible;
  bool get sidebarHidden => _sidebarHidden;
  bool get screensaverActive => _screensaverActive;
  bool get driveRomInstalled => _driveRomInstalled;
  bool get isLibraryLoading => _isLibraryLoading;
  bool get leftHanded => _leftHanded;
  OnScreenPadMode get padMode => _padMode;
  int get joystickPort => _joystickPort;
  List<CustomButton> get customButtons => _customButtons;
  MediaEntry? get currentEntry => _currentEntry;
  String get lastMediaName => _lastMediaName;
  String get emulatorLabel => _emulatorLabel;

  bool get hideChrome => _inEmulator && _category == WorkbenchCategory.resume && !_chromeVisible;

  // Actions
  void setCategory(WorkbenchCategory next) {
    if (_inEmulator && next != WorkbenchCategory.resume) {
      backToLibrary();
    }
    _category = next;
    notifyListeners();
  }

  void toggleSidebar() {
    _sidebarHidden = !_sidebarHidden;
    notifyListeners();
  }

  void wakeChrome() {
    _chromeTimer?.cancel();
    _chromeTimer = Timer(const Duration(seconds: 3), () {
      if (_inEmulator) {
        _chromeVisible = false;
        notifyListeners();
      }
    });
    if (!_chromeVisible) {
      _chromeVisible = true;
      notifyListeners();
    }
  }

  void scheduleIdle() {
    _idleTimer?.cancel();
    if (_screensaverActive) {
      _screensaverActive = false;
      notifyListeners();
    }
    if (!_inEmulator) {
      _idleTimer = Timer(_backdropIdleDelay, () {
        if (!_inEmulator) {
          _screensaverActive = true;
          notifyListeners();
        }
      });
    }
  }

  Future<void> _loadInputPrefs() async {
    _leftHanded = await AppPrefs.getLeftHandedInput();
    _padMode = await AppPrefs.getOnScreenPadMode();
    _joystickPort = await AppPrefs.getJoystickPort();
    _customButtons = await AppPrefs.getCustomButtons();
    notifyListeners();
  }

  Future<void> _refreshDriveRomState() async {
    try {
      _driveRomInstalled = await ViceNativePaths.driveRomInstalled();
    } catch (_) {
      _driveRomInstalled = true;
    }
    notifyListeners();
  }

  Future<void> scanLibrary() async {
    _isLibraryLoading = true;
    notifyListeners();

    await _refreshDriveRomState();
    final scanDir = await libraryScanRoot();

    LibraryScanResult result;
    if (Platform.isAndroid && await MediaFolder.hasFolder()) {
      final imported = await StorageAccess.instance.scanFolder(scanDir ?? '');
      result = LibraryScanResult(
        entries: [
          for (final f in imported)
            MediaEntry(
              displayName: f.displayName,
              path: f.path,
              mediaType: MediaEntry.filterForExtension(f.displayName.split('.').last),
            ),
        ],
        unreadableCount: 0,
      );
    } else {
      result = scanDir == null
          ? LibraryScanResult.empty
          : await LibraryScanner.scan(scanDir);
    }

    _library = result.entries;
    _unreadableCount = result.unreadableCount;
    _isLibraryLoading = false;
    notifyListeners();
  }

  Future<void> launch(MediaEntry entry, BuildContext context) async {
    _silenceWorkbenchMusic();

    if (SafPath.isSaf(entry.path)) {
      final real = await MediaCache.materialise(FolderEntry(
        documentId: SafPath.documentIdOf(entry.path),
        name: entry.displayName,
        directory: '',
        size: 0,
      ));
      if (real == null) {
        _showLaunchError(context, 'Cannot read ${entry.displayName}.',
            detail: 'The file could not be read out of the folder you chose.');
        return;
      }
      entry = MediaEntry(displayName: entry.displayName, path: real, mediaType: entry.mediaType);
    }

    final file = File(entry.path);
    if (entry.mediaType != MediaFormatFilter.none && !LibraryScanner.isReadable(file)) {
      _showLaunchError(context, 'Cannot read ${entry.displayName}.',
          detail: PermissionsService.isRelevant ? 'Android is blocking access.' : 'The file exists but could not be opened.',
          offerPermission: PermissionsService.isRelevant);
      return;
    }

    if (entry.mediaType == MediaFormatFilter.disk && !_driveRomInstalled) {
      _showLaunchError(context, 'Disk images need the 1541 drive ROM.',
          detail: 'Without dos1541 the drive reports ?DEVICE NOT PRESENT.');
      return;
    }

    core.setPaused(false);
    final result = core.start(
      mediaType: switch (entry.mediaType) {
        MediaFormatFilter.disk => ViceMedia.disk,
        MediaFormatFilter.tape => ViceMedia.tape,
        MediaFormatFilter.prg => ViceMedia.prg,
        _ => ViceMedia.none,
      },
      mediaPath: entry.mediaType == MediaFormatFilter.none ? null : entry.path,
    );

    if (result != 0) {
      _showLaunchError(context, 'Failed to start ${entry.displayName}.', detail: 'Error $result');
      return;
    }

    _inEmulator = true;
    _chromeVisible = true;
    _category = WorkbenchCategory.resume;
    _emulatorLabel = entry.displayName;
    _lastMediaName = entry.displayName;
    _currentEntry = entry;
    _idleTimer?.cancel();
    notifyListeners();
  }

  void resumeCurrent() {
    if (_currentEntry == null) return;
    _silenceWorkbenchMusic();
    core.setPaused(false);
    _inEmulator = true;
    _chromeVisible = true;
    _category = WorkbenchCategory.resume;
    _idleTimer?.cancel();
    notifyListeners();
  }

  Future<void> resumeSaved(SaveStateEntry entry, BuildContext context) async {
    final mediaEntry = MediaEntry(
      displayName: entry.title,
      path: entry.mediaPath,
      mediaType: entry.mediaType,
    );

    _silenceWorkbenchMusic();

    if (!entry.canResume) {
      launch(mediaEntry, context);
      return;
    }

    core.setPaused(false);
    if (!core.isRunning) {
      core.start(mediaType: ViceMedia.none, mediaPath: null);
      if (!await _waitForFirstFrame()) {
        _showLaunchError(context, 'Could not restore ${entry.title}.', detail: 'Core failed to start.');
        return;
      }
    }

    final result = core.loadSnapshot(entry.snapshotPath!);
    if (result != 0) {
      _showLaunchError(context, 'Could not restore ${entry.title}.', detail: 'Error $result');
      launch(mediaEntry, context);
      return;
    }

    _inEmulator = true;
    _chromeVisible = true;
    _sidebarHidden = true;
    _emulatorLabel = entry.title;
    _lastMediaName = entry.title;
    _currentEntry = mediaEntry;
    _idleTimer?.cancel();
    notifyListeners();
  }

  Future<bool> _waitForFirstFrame() async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      if (core.isRunning && core.getFramebuffer() != null) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  Future<void> backToLibrary() async {
    emulatorUi.reset();
    _chromeTimer?.cancel();
    _inEmulator = false;
    _chromeVisible = true;
    scheduleIdle();
    // Back at the workbench, the tune may play again.
    _musicSuppressed = false;
    unawaited(_startWorkbenchMusic());
    await _captureSaveState(_currentEntry);
    core.setPaused(true);
    notifyListeners();
  }

  Future<void> _captureSaveState(MediaEntry? entry) async {
    if (entry == null || !core.isRunning) return;
    try {
      await SaveStateService.capture(
        core: core,
        title: entry.displayName,
        mediaPath: entry.path,
        mediaType: entry.mediaType,
      );
    } catch (e) {
      // Errors can be handled by the UI listening to a stream or similar,
      // but for now we'll just log it.
      AppLog.log('Could not save session: $e');
    }
  }

  Future<void> requestStorageAccess() async {
    await PermissionsService.requestStorageAccess();
    await scanLibrary();
  }

  /// True while a game owns the audio. The workbench tune must not play over
  /// it, and pausing the player is not enough on its own: the starter below
  /// reaches play() only after several awaits -- reading a pref, searching
  /// directories, loading the vsid core -- so a launch during that window
  /// paused a player that had not started yet, and the tune then began
  /// underneath the game. A flag the starter re-checks just before it plays
  /// closes that window; a pause call cannot.
  bool _musicSuppressed = false;

  /// Silences the workbench tune for a game, and keeps it silenced against a
  /// start that is still in flight.
  void _silenceWorkbenchMusic() {
    _musicSuppressed = true;
    VsidService.instance.pause();
  }

  Future<void> _startWorkbenchMusic() async {
    if (!await AppPrefs.getWorkbenchMusic()) return;
    final vsid = VsidService.instance;
    if (vsid.currentPath != null) {
      if (_musicSuppressed) return;
      if (vsid.isPaused) vsid.togglePause();
      return;
    }
    final dirs = await MusicLibrary.searchDirs();
    final pick = MusicLibrary.firstAvailable(dirs);
    if (pick == null) return;
    if (!await vsid.ensureLoaded()) return;
    // Re-checked here, after every await, rather than only on entry: this is
    // the point at which sound would actually start coming out.
    if (_musicSuppressed) return;
    vsid.play(pick.$2);
  }

  void setLeftHanded(bool v) {
    _leftHanded = v;
    AppPrefs.setLeftHandedInput(v);
    notifyListeners();
  }

  void setPadMode(OnScreenPadMode mode) {
    _padMode = mode;
    AppPrefs.setOnScreenPadMode(mode);
    notifyListeners();
  }

  void setJoystickPort(int port) {
    if (_joystickPort != port && core.isRunning) {
      core.joystick(_joystickPort, 0);
    }
    _joystickPort = port;
    AppPrefs.setJoystickPort(port);
    notifyListeners();
  }

  void setCustomButtons(List<CustomButton> buttons) {
    _customButtons = buttons;
    AppPrefs.setCustomButtons(buttons);
    notifyListeners();
  }

  void _showLaunchError(BuildContext context, String message, {required String detail, bool offerPermission = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF3A1D1D),
        duration: const Duration(seconds: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            Text(detail, style: const TextStyle(color: Colors.white70)),
          ],
        ),
        action: offerPermission
            ? SnackBarAction(
                label: 'GRANT',
                textColor: const Color(0xFF00FFCC),
                onPressed: requestStorageAccess,
              )
            : null,
      ),
    );
  }

  String backdropInfoText() => buildBackdropInfoText(
        platform: platformName(),
        loadedMediaName: _lastMediaName,
        libraryCount: _library.length,
        fps: core.isRunning ? core.fps : 0,
      );

  @override
  void dispose() {
    _idleTimer?.cancel();
    _chromeTimer?.cancel();
    gamepad.dispose();
    super.dispose();
  }
}

/// The screensaver's scrolling status line, as a pure function of what it
/// reports.
///
/// Kept separate from the view model on purpose. It reports live state --
/// what is loaded, how many titles, the frame rate -- and it must not be able
/// to lie: it once shipped a hardcoded "VICE ANDROID" that survived the
/// rename and went on claiming Android on a Linux desktop. That is only
/// testable while the text can be built from arguments rather than read out
/// of a view model's private fields.
String buildBackdropInfoText({
  required String platform,
  required String loadedMediaName,
  required int libraryCount,
  int fps = 0,
}) {
  final buf = StringBuffer(
      'VICE ON ${platform.toUpperCase()}   *   MACHINE C64 (X64SC)');
  if (loadedMediaName.isNotEmpty) {
    buf.write('   *   LOADED ${loadedMediaName.toUpperCase()}');
  } else {
    buf.write('   *   NO MEDIA LOADED');
  }
  buf.write('   *   $libraryCount TITLES IN LIBRARY');
  if (fps > 0) buf.write('   *   $fps FPS');
  return buf.toString();
}
