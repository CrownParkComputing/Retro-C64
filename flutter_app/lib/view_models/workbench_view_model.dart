import 'package:retro_c64/screens/emulator_session_screen.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:retro_c64/data/category.dart';
import 'package:retro_c64/data/custom_button.dart';
import 'package:retro_c64/data/emulator_ui_state.dart';
import 'package:retro_c64/data/media_entry.dart';
import 'package:retro_c64/ffi/vice_bindings.dart';
import 'package:retro_c64/ffi/vice_core.dart';
import 'package:retro_c64/ffi/vice_native_paths.dart';
import 'package:retro_c64/services/app_log.dart';
import 'package:retro_c64/services/app_prefs.dart';
import 'package:retro_c64/services/gamepad_service.dart';
import 'package:retro_c64/services/library_scanner.dart';
import 'package:retro_c64/services/media_folder.dart';
import 'package:retro_c64/services/music_library.dart';
import 'package:retro_c64/services/permissions_service.dart';
import 'package:retro_c64/services/platform_info.dart';
import 'package:retro_c64/services/save_state_service.dart';
import 'package:retro_c64/services/service_locator.dart';
import 'package:retro_c64/services/storage_access.dart';
import 'package:retro_c64/services/demo_roms_service.dart';
import 'package:retro_c64/services/vsid_service.dart';

class WorkbenchViewModel extends ChangeNotifier {
  final ViceCore core;
  final GamepadService gamepad = getIt<GamepadService>();
  final EmulatorUiState emulatorUi = EmulatorUiState();

  WorkbenchCategory _category = WorkbenchCategory.games;
  List<MediaEntry> _library = [];
  int _unreadableCount = 0;

  /// What went wrong on the last scan, surfaced rather than swallowed --
  /// "no games found" and "the scan failed" need different fixes.
  String? _scanError;
  bool _sessionOpen = false;
  bool _sidebarHidden = false;
  bool _screensaverActive = false;
  bool _driveRomInstalled = true;
  bool _isLibraryLoading = false;

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

  /// Whether this run booted the bundled free ROMs instead of the user's.
  ///
  /// It changes what the app IS for the session, not just which ROMs are
  /// loaded. In demo mode the user's media folder is not the one in use and
  /// their tunes are not available, so offering Games and Music would be
  /// offering things that cannot work -- see [visibleCategories].
  bool _demoMode = false;
  bool get demoMode => _demoMode;

  /// The destinations the rail should offer. Demo mode is deliberately
  /// narrow: run the demo, read what the mode means, leave.
  List<WorkbenchCategory> get visibleCategories => _demoMode
      ? const [
          // Games stays, and has to: the demo is a file you open from the
          // library like any other, using the same load the emulator uses
          // for a tape or a disk. Nothing is auto-started or typed in on the
          // user's behalf, so taking the library away would leave no way to
          // start the demo at all.
          WorkbenchCategory.games,
          WorkbenchCategory.resume,
          WorkbenchCategory.compliance,
          WorkbenchCategory.about,
        ]
      : WorkbenchCategory.values;

  /// Re-reads the mode after something has changed it, so the rail and the
  /// music follow immediately rather than at the next launch.
  Future<void> refreshDemoMode() => _loadDemoMode();

  /// Saved sessions, filtered to the machine currently running.
  ///
  /// Compliance mode showed the user's own saved games, which is wrong for
  /// the same reason listing their library was: those sessions were saved on
  /// a machine booted with Commodore's ROMs, and restoring one into a
  /// machine booted on the free ROMs restores a snapshot the ROMs underneath
  /// it do not match. It also put their titles on screen in the mode whose
  /// whole point is that everything shown came with the app.
  Future<List<SaveStateEntry>> savedSessions() async {
    final List<SaveStateEntry> all;
    try {
      all = await SaveStateService.list();
    } catch (e) {
      // Listing needs the application-support directory. A failure there is
      // "no saved sessions", not a screen that throws.
      AppLog.log('saved sessions unavailable: $e');
      return const [];
    }
    if (!_demoMode) return all;
    // Recognised by where the media came from, not by its name: a user is
    // free to have a game called DEMO.PRG, and the folder cannot be faked.
    try {
      final demoDir = (await getIt<DemoRomsService>().demoRomDir()).path;
      return all.where((e) => e.mediaPath.startsWith(demoDir)).toList();
    } catch (_) {
      // If the folder cannot be resolved, show nothing rather than showing
      // the user's own sessions in a mode that must not display them.
      return const [];
    }
  }

  Future<void> _loadDemoMode() async {
    final on = await getIt<AppPrefs>().getDemoRomMode();
    if (on == _demoMode) return;
    _demoMode = on;
    if (!visibleCategories.contains(_category)) {
      _category = WorkbenchCategory.compliance;
    }
    notifyListeners();
  }

  Future<void> _init() async {
    await _loadDemoMode();
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
  String? get scanError => _scanError;
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

  // Actions
  void setCategory(WorkbenchCategory next) {
    _category = next;
    notifyListeners();
  }

  void toggleSidebar() {
    _sidebarHidden = !_sidebarHidden;
    notifyListeners();
  }

  void scheduleIdle() {
    _idleTimer?.cancel();
    if (_screensaverActive) {
      _screensaverActive = false;
      notifyListeners();
    }
    if (!_sessionOpen) {
      _idleTimer = Timer(_backdropIdleDelay, () {
        if (!_sessionOpen) {
          _screensaverActive = true;
          notifyListeners();
        }
      });
    }
  }

  Future<void> _loadInputPrefs() async {
    _leftHanded = await getIt<AppPrefs>().getLeftHandedInput();
    _padMode = await getIt<AppPrefs>().getOnScreenPadMode();
    _joystickPort = await getIt<AppPrefs>().getJoystickPort();
    _customButtons = await getIt<AppPrefs>().getCustomButtons();
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
    // In compliance mode the library IS the demo folder. Listing the user's
    // own games there would offer titles that cannot run -- they were
    // written against Commodore's ROMs, and this machine is not booted on
    // them -- and would blur the one thing the mode exists to show: that
    // everything on screen came with the app.
    String? scanDir;
    try {
      scanDir = _demoMode
          ? (await getIt<DemoRomsService>().demoRomDir()).path
          : await libraryScanRoot();
    } catch (e) {
      // Resolving a directory can fail -- a platform channel that is not
      // there, a container not created yet. An unhandled throw here left
      // _isLibraryLoading true for ever and the grid spinning, which reads
      // as a hang rather than as an empty library.
      AppLog.log('library scan root unavailable: $e');
      scanDir = null;
    }

    LibraryScanResult result;
    // Compliance mode never goes through the SAF path, and must not: on
    // Android _AndroidSafStorage.scanFolder IGNORES the directory it is
    // given and always lists the tree the user granted. Handing it the demo
    // folder therefore changed nothing and the user's own games kept
    // appearing. The demo folder is inside the app's own storage, so it can
    // be read directly with no SAF grant at all.
    //
    // The SCAN itself is guarded like the resolution above: a throw here
    // left _isLibraryLoading true for ever -- an infinite spinner with no
    // message, which reads as a hang rather than as a failure.
    try {
      if (!_demoMode && Platform.isAndroid && await MediaFolder.hasFolder()) {
        final imported = await getIt<StorageAccess>().scanFolder(scanDir ?? '');
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
      _scanError = null;
    } catch (e) {
      AppLog.log('library scan failed: $e');
      _scanError = 'The library scan failed: $e';
      _library = const [];
      _unreadableCount = 0;
      _isLibraryLoading = false;
      notifyListeners();
      return;
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

    _emulatorLabel = entry.displayName;
    _lastMediaName = entry.displayName;
    _currentEntry = entry;
    _idleTimer?.cancel();
    notifyListeners();
    if (!context.mounted) return;
    await _openSession(context);
  }

  Future<void> resumeCurrent(BuildContext context) async {
    if (_currentEntry == null) return;
    _silenceWorkbenchMusic();
    core.setPaused(false);
    _idleTimer?.cancel();
    notifyListeners();
    if (!context.mounted) return;
    await _openSession(context);
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

    _emulatorLabel = entry.title;
    _lastMediaName = entry.title;
    _currentEntry = mediaEntry;
    _idleTimer?.cancel();
    notifyListeners();
    if (!context.mounted) return;
    await _openSession(context);
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

  /// Hands the session its own screen -- the family pattern shared with
  /// Retro-Amiga and Retro-Saturn. Every way into a game funnels through
  /// here, so pausing and closing land back on the workbench in exactly one
  /// place.
  Future<void> _openSession(BuildContext context) async {
    if (_sessionOpen) return;
    _sessionOpen = true;
    final SessionExit? how = await Navigator.of(context).push<SessionExit>(
      MaterialPageRoute<SessionExit>(
        fullscreenDialog: true,
        builder: (BuildContext context) => EmulatorSessionScreen(vm: this),
      ),
    );
    _sessionOpen = false;
    if (how != SessionExit.paused) {
      // Closed (or popped some other way): the workbench forgets the entry.
      _currentEntry = null;
      _emulatorLabel = '';
    }
    scheduleIdle();
    notifyListeners();
  }

  /// Snapshot, silence and pause -- shared by both ways out of a session.
  /// The session screen calls this before it pops.
  Future<void> endSession() async {
    emulatorUi.reset();
    _resumeWorkbenchMusic();
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
    getIt<VsidService>().pause();
  }

  /// Lets the workbench tune play again, and starts it. The counterpart to
  /// [_silenceWorkbenchMusic]: every path that silences has to reach this
  /// one, including the paths where the game never actually started.
  void _resumeWorkbenchMusic() {
    _musicSuppressed = false;
    unawaited(_startWorkbenchMusic());
  }

  Future<void> _startWorkbenchMusic() async {
    // Silent in demo mode. The tunes live in the user's own folders, which
    // this mode deliberately does not use, so there is nothing to play and a
    // failed load would look like a fault rather than a choice.
    if (_demoMode) return;
    if (!await getIt<AppPrefs>().getWorkbenchMusic()) return;
    final vsid = getIt<VsidService>();
    if (vsid.currentPath != null) {
      if (_musicSuppressed) return;
      if (vsid.isPaused) getIt<VsidService>().togglePause();
      return;
    }
    final dirs = await MusicLibrary.searchDirs();
    final pick = MusicLibrary.firstAvailable(dirs);
    if (pick == null) return;
    if (!await vsid.ensureLoaded()) return;
    // Re-checked here, after every await, rather than only on entry: this is
    // the point at which sound would actually start coming out.
    if (_musicSuppressed) return;
    getIt<VsidService>().play(pick.$2);
  }

  void setLeftHanded(bool v) {
    _leftHanded = v;
    getIt<AppPrefs>().setLeftHandedInput(v);
    notifyListeners();
  }

  void setPadMode(OnScreenPadMode mode) {
    _padMode = mode;
    getIt<AppPrefs>().setOnScreenPadMode(mode);
    notifyListeners();
  }

  void setJoystickPort(int port) {
    if (_joystickPort != port && core.isRunning) {
      core.joystick(_joystickPort, 0);
    }
    _joystickPort = port;
    getIt<AppPrefs>().setJoystickPort(port);
    notifyListeners();
  }

  void setCustomButtons(List<CustomButton> buttons) {
    _customButtons = buttons;
    getIt<AppPrefs>().setCustomButtons(buttons);
    notifyListeners();
  }

  void _showLaunchError(BuildContext context, String message, {required String detail, bool offerPermission = false}) {
    // A launch that failed leaves the user at the workbench, so the workbench
    // tune belongs back on. Every failure path in launch() and resumeSaved()
    // exits through here, and each one had already silenced the music on the
    // way in -- without this, one unreadable file or one missing drive ROM
    // left the menu silent for the rest of the session, with nothing to
    // connect the two.
    _resumeWorkbenchMusic();
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
