import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'about_screen.dart';
import '../data/c64_keys.dart';
import '../data/category.dart';
import '../data/media_entry.dart';
import '../ffi/vice_bindings.dart';
import '../ffi/vice_core.dart';
import '../ffi/vice_native_paths.dart';
import '../theme/vice_theme.dart';
import '../widgets/c64_background.dart';
import '../widgets/sidebar.dart';
import 'emulator_screen.dart';
import 'input_settings_screen.dart';
import 'library_grid.dart';
import 'music_screen.dart';
import 'paths_settings_screen.dart';
import 'resume_screen.dart';
import 'settings_placeholder.dart';
import 'video_settings_screen.dart';
import '../services/app_prefs.dart';
import '../services/gamepad_service.dart';
import '../services/library_scanner.dart';
import '../services/permissions_service.dart';
import '../services/platform_info.dart';
import '../services/save_state_service.dart';
import '../services/vsid_service.dart';

/// Port of LauncherLayoutHelper.createLauncher's overall structure: a
/// FrameLayout stack (animated background behind), a horizontal row of
/// sidebar + content, 12dp root padding, 12dp gap before the content panel.
class WorkbenchScreen extends StatefulWidget {
  final ViceCore core;

  const WorkbenchScreen({super.key, required this.core});

  @override
  State<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends State<WorkbenchScreen> {
  WorkbenchCategory _category = WorkbenchCategory.games;
  List<MediaEntry> _library = [];

  /// Files that matched a supported extension but whose bytes could not be
  /// read (Android scoped storage). Surfaced as a banner with a way to fix
  /// it rather than silently hidden.
  int _unreadableCount = 0;
  bool _inEmulator = false;
  String _emulatorLabel = '';
  String _lastMediaName = '';

  /// The media currently loaded in the core, kept so the Resume screen can
  /// describe the live session and so leaving the emulator can write a save
  /// state tagged with the right title/path. Null when nothing has been
  /// launched this run.
  MediaEntry? _currentEntry;

  // Persisted via AppPrefs (shared_preferences). Loaded async in
  // initState -- starts false so the joystick doesn't jump sides once the
  // real value comes back if it happens to be true.
  bool _leftHanded = false;
  OnScreenPadMode _padMode = OnScreenPadMode.auto;
  int _joystickPort = 2;
  List<C64Key> _customButtons = const [];

  // External gamepad support (see gamepad_service.dart) -- created once at
  // the workbench level so it's already listening (and its `connected`
  // status already up to date) by the time a game is launched, and so the
  // Input Settings tab can show live connection status too.
  final GamepadService _gamepad = GamepadService();

  // --- Workbench backdrop screensaver -----------------------------------
  //
  // Port of MainActivity's scheduleBackdropVisualiser: the equaliser/demo
  // comes up only after the workbench has gone untouched for
  // BACKDROP_IDLE_DELAY_MS, and never while a game is on screen (the
  // emulator screen replaces this whole widget, but the timer is also
  // cancelled explicitly so a stray callback can't fire late and flip
  // _screensaverActive under a game).
  static const _backdropIdleDelay = Duration(milliseconds: 30000);
  Timer? _idleTimer;
  bool _screensaverActive = false;

  @override
  void initState() {
    super.initState();
    _scanLibrary();
    _scheduleIdle();
    _loadInputPrefs();
    _gamepad.start();
  }

  Future<void> _loadInputPrefs() async {
    final leftHanded = await AppPrefs.getLeftHandedInput();
    final padMode = await AppPrefs.getOnScreenPadMode();
    final port = await AppPrefs.getJoystickPort();
    final customButtons = await AppPrefs.getCustomButtons();
    if (!mounted) return;
    setState(() {
      _leftHanded = leftHanded;
      _padMode = padMode;
      _joystickPort = port;
      _customButtons = customButtons;
    });
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _gamepad.dispose();
    super.dispose();
  }

  /// Restarts the idle countdown, and takes the equaliser down if it was
  /// up. Called on every pointer interaction and whenever the workbench
  /// (re)appears.
  void _scheduleIdle() {
    _idleTimer?.cancel();
    if (_screensaverActive) setState(() => _screensaverActive = false);
    if (!_inEmulator) {
      _idleTimer = Timer(_backdropIdleDelay, () {
        if (mounted && !_inEmulator) {
          setState(() => _screensaverActive = true);
        }
      });
    }
  }

  /// What the scroller says, read fresh each time the screensaver comes up
  /// -- a scroller that claims a game is loaded when none is would be
  /// worse than no scroller. Mirrors MainActivity.backdropInfoText().
  String _backdropInfoText() => backdropInfoText(
        platform: platformName(),
        loadedMediaName: _lastMediaName,
        libraryCount: _library.length,
        fps: widget.core.isRunning ? widget.core.fps : 0,
      );

  /// Scans the real, wizard-configured Games folder (AppPrefs.
  /// getGamesFolderPath(), set by SetupWizardScreen's real folder picker)
  /// for C64 game media. Falls back to the native test fixtures dir only
  /// when no real folder has been configured yet (e.g. mid-development,
  /// before setup has run) so the grid still has something to show.
  ///
  /// SID files are intentionally NOT included here -- they're the Music
  /// tab's job (see music_screen.dart), which resolves its own Music/
  /// folder and plays them for real via the vsid core.
  Future<void> _scanLibrary() async {
    final configured = await AppPrefs.getGamesFolderPath();
    final scanDir = (configured != null && Directory(configured).existsSync())
        ? configured
        : ViceNativePaths.devRomDir;

    final result = scanDir == null
        ? LibraryScanResult.empty
        : LibraryScanner.scan(scanDir);
    if (!mounted) return;
    setState(() {
      _library = result.entries;
      _unreadableCount = result.unreadableCount;
    });
  }

  /// Sends the user to the system "All files access" toggle and rescans
  /// when they come back.
  Future<void> _requestStorageAccess() async {
    await PermissionsService.requestStorageAccess();
    await _scanLibrary();
  }

  void _launch(MediaEntry entry) {
    // Mirrors the original Android app's documented behavior: "Stop SID
    // music when launching a game" (ViceVsid.setPaused(true) in loadMedia()
    // before C64Native.launch()). Unconditional pause (not toggle) so this
    // reliably silences music regardless of whether it was already
    // paused/stopped/never started.
    VsidService.instance.pause();
    // Fail loudly rather than dropping the user on a blank emulator screen:
    // if the bytes can't be read (scoped storage, removed media, bad
    // permissions) there is nothing for the core to boot.
    final file = File(entry.path);
    if (entry.mediaType != MediaFormatFilter.none && !LibraryScanner.isReadable(file)) {
      _showLaunchError(
        'Cannot read ${entry.displayName}.',
        detail: PermissionsService.isRelevant
            ? 'Android is blocking access to this file. Grant "All files '
                'access" in system settings, then try again.'
            : 'The file exists but could not be opened.',
        offerPermission: PermissionsService.isRelevant,
      );
      return;
    }
    // Un-pause BEFORE handing the core any work. Leaving the emulator
    // screen parks the core in its pause gate (see _backToLibrary), and a
    // media swap is applied by the core's OWN thread -- so a swap queued
    // while it is still paused would sit there until the user happened to
    // resume. The native side does service its mailboxes from inside the
    // gate as a safety net, but the game also has to actually run once
    // loaded, so resuming here is the correct order either way.
    widget.core.setPaused(false);

    // vice_core_start() now covers BOTH cases: first start, and swapping a
    // different title into an already-running core (queued for the core
    // thread, which detaches the old media, attaches the new one, autostarts
    // it and resets the machine -- see apply_pending_media_if_any in
    // native/vice_core/bridge/vice_bridge.c). It used to return -1 outright
    // on the second call, which is why picking a second game did nothing.
    final result = widget.core.start(
      mediaType: switch (entry.mediaType) {
        MediaFormatFilter.disk => ViceMedia.disk,
        MediaFormatFilter.tape => ViceMedia.tape,
        MediaFormatFilter.prg => ViceMedia.prg,
        _ => ViceMedia.none,
      },
      mediaPath: entry.mediaType == MediaFormatFilter.none ? null : entry.path,
    );
    if (result != 0) {
      _showLaunchError('Failed to start ${entry.displayName}.',
          detail: 'The emulator core refused the media (error $result).');
      return;
    }
    setState(() {
      _inEmulator = true;
      _emulatorLabel = entry.displayName;
      _lastMediaName = entry.displayName;
      _currentEntry = entry;
    });
    // Leaving the workbench for the emulator screen -- cancel the idle
    // countdown outright, matching cancelBackdropVisualiser().
    _idleTimer?.cancel();
  }

  /// Back into the emulator screen with whatever is already loaded, e.g.
  /// from the Resume destination. Unpausing is the whole point: the core
  /// was parked on the way out, so without this the user gets a frozen
  /// picture and concludes the emulator crashed.
  void _resumeCurrent() {
    if (_currentEntry == null) return;
    widget.core.setPaused(false);
    setState(() => _inEmulator = true);
    _idleTimer?.cancel();
  }

  /// Restores a saved session.
  ///
  /// The media is deliberately NOT re-launched first. A VICE snapshot is a
  /// complete machine -- RAM, CPU, VIC/SID/CIA, the drives, and (because the
  /// core saves with save_disks=1) the disk image itself -- so attaching and
  /// autostarting the title beforehand adds nothing and actively destroys the
  /// restore: autostart resets the machine, and that reset lands seconds
  /// later, wiping whatever the snapshot just put there. The old code paired
  /// a start() with a fixed 1500ms delay, which is far less than a C64
  /// autostart takes, so the reset routinely arrived after the restore.
  ///
  /// The only thing that must be true is that a machine is RUNNING to restore
  /// into. On a cold app start there isn't one, so bring one up with no media
  /// (nothing to autostart, nothing to reset later) and restore into that.
  Future<void> _resumeSaved(SaveStateEntry entry) async {
    final mediaEntry = MediaEntry(
      displayName: entry.title,
      path: entry.mediaPath,
      mediaType: entry.mediaType,
    );

    // No usable snapshot: this is a Restart, and the Resume screen already
    // told the user so. Launch it the ordinary way rather than pretending.
    if (!entry.canResume) {
      _launch(mediaEntry);
      return;
    }

    widget.core.setPaused(false);

    if (!widget.core.isRunning) {
      widget.core.start(mediaType: ViceMedia.none, mediaPath: null);
      if (!await _waitForFirstFrame()) {
        if (!mounted) return;
        _showLaunchError(
          'Could not restore your saved ${entry.title} session.',
          detail: 'The emulator core did not finish starting up. '
              'Launch ${entry.title} from Games to play it from the beginning.',
        );
        return;
      }
    }

    final result = widget.core.loadSnapshot(entry.snapshotPath!);
    if (!mounted) return;
    if (result != 0) {
      // Honest failure, and it does NOT silently become a restart: say what
      // happened and start the title properly from the beginning so the user
      // ends up somewhere real either way.
      _showLaunchError(
        'Could not restore your saved ${entry.title} session.',
        detail: result == ViceSnapshotResult.timeout
            ? 'The emulator core did not respond in time. Starting '
                '${entry.title} from the beginning instead.'
            : 'The save state could not be read (error $result). Starting '
                '${entry.title} from the beginning instead.',
      );
      _launch(mediaEntry);
      return;
    }

    setState(() {
      _inEmulator = true;
      _emulatorLabel = entry.title;
      _lastMediaName = entry.title;
      _currentEntry = mediaEntry;
    });
    _idleTimer?.cancel();
  }

  /// Waits for a freshly started core to actually be drawing.
  ///
  /// isRunning alone is not enough: the native side flips it as the core
  /// thread starts, before VICE has finished its own startup, and a snapshot
  /// restored into a machine that is still booting gets trampled by the
  /// power-on reset. A frame in the framebuffer means the machine is past
  /// that and executing.
  Future<bool> _waitForFirstFrame({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (widget.core.isRunning && widget.core.getFramebuffer() != null) {
        // A little settle time so the restore does not race the tail of
        // VICE's own boot.
        await Future<void>.delayed(const Duration(milliseconds: 500));
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  /// A real, visible failure. The bug this replaces was a silent one: the
  /// app switched to the emulator screen and simply showed black.
  void _showLaunchError(String message,
      {required String detail, bool offerPermission = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF3A1D1D),
        duration: const Duration(seconds: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            Text(detail, style: const TextStyle(color: Colors.white70)),
          ],
        ),
        action: offerPermission
            ? SnackBarAction(
                label: 'GRANT',
                textColor: ViceColors.accentTeal,
                onPressed: _requestStorageAccess,
              )
            : null,
      ),
    );
  }

  /// Leaving the emulator screen.
  ///
  /// Two things happen here that did not before:
  ///
  ///  1. A save state is written for the title being left, so it turns up
  ///     in the Resume list. This runs BEFORE the pause, while the core is
  ///     still ticking, because a snapshot is serviced by the core's own
  ///     thread -- and it captures the exact moment the user walked away.
  ///  2. The core is PAUSED. It used to keep running at full speed in the
  ///     background: burning CPU and battery, playing audio over the
  ///     workbench, and letting the game advance (die, time out, lose a
  ///     life) while the user was just browsing.
  Future<void> _backToLibrary() async {
    setState(() => _inEmulator = false);
    // Re-arms the countdown now that the workbench is showing again,
    // matching scheduleBackdropVisualiser() being called from onResume.
    _scheduleIdle();

    final entry = _currentEntry;
    if (entry != null && widget.core.isRunning) {
      // Non-fatal: a title that refuses to snapshot still pauses correctly,
      // it just won't appear in the resume list. Better that than blocking
      // the user's way back to the workbench on it.
      try {
        await SaveStateService.capture(
          core: widget.core,
          title: entry.displayName,
          mediaPath: entry.path,
          mediaType: entry.mediaType,
        );
      } catch (_) {
        // See above.
      }
    }

    widget.core.setPaused(true);
  }

  void _setCustomButtons(List<C64Key> buttons) {
    setState(() => _customButtons = buttons);
    AppPrefs.setCustomButtons(buttons);
  }

  void _setPadMode(OnScreenPadMode mode) {
    setState(() => _padMode = mode);
    AppPrefs.setOnScreenPadMode(mode);
  }

  /// Changing the port mid-game has to release the OLD port first,
  /// otherwise whatever direction was held at the moment of the switch
  /// stays latched on the port nothing is driving any more -- the C64 sees
  /// a joystick permanently pushed in one direction.
  void _setJoystickPort(int port) {
    final previous = _joystickPort;
    if (previous != port && widget.core.isRunning) {
      widget.core.joystick(previous, 0);
    }
    setState(() => _joystickPort = port);
    AppPrefs.setJoystickPort(port);
  }

  @override
  Widget build(BuildContext context) {
    if (_inEmulator) {
      return EmulatorScreen(
        core: widget.core,
        mediaLabel: _emulatorLabel,
        onBackToLibrary: _backToLibrary,
        leftHanded: _leftHanded,
        gamepad: _gamepad,
        padMode: _padMode,
        onPadModeChanged: _setPadMode,
        customButtons: _customButtons,
        joystickPort: _joystickPort,
        onJoystickPortChanged: _setJoystickPort,
      );
    }

    return Scaffold(
      backgroundColor: ViceColors.rootBackground,
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _scheduleIdle(),
        onPointerSignal: (_) => _scheduleIdle(),
        onPointerHover: (_) => _scheduleIdle(),
        child: Stack(
          children: [
            Positioned.fill(
              child: C64Background(
                active: _screensaverActive,
                infoText: _backdropInfoText(),
                audioLevel: () =>
                    widget.core.isRunning ? widget.core.audioLevel : 0,
                onWake: _scheduleIdle,
              ),
            ),
            AnimatedOpacity(
              opacity: _screensaverActive ? 0 : 1,
              duration: Duration(milliseconds: _screensaverActive ? 400 : 150),
              child: IgnorePointer(
                ignoring: _screensaverActive,
                // SafeArea so the top sidebar entry isn't tucked under the
                // device status bar (the backdrop behind deliberately stays
                // edge-to-edge).
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(ViceMetrics.rootPadding),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Sidebar(
                          selected: _category,
                          onSelect: (c) => setState(() => _category = c),
                        ),
                        const SizedBox(width: ViceMetrics.contentLeftMargin),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: ViceColors.panelFill,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: ViceColors.panelStroke),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _content(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    if (isLibraryCategory(_category)) {
      // Media-format filtering lives inside LibraryGrid now (tabs across
      // the top), so there's nothing category-derived left to pass.
      final grid = LibraryGrid(allEntries: _library, onLaunch: _launch);
      if (_unreadableCount == 0) return grid;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _UnreadableBanner(
              count: _unreadableCount, onGrant: _requestStorageAccess),
          Expanded(child: grid),
        ],
      );
    }
    switch (_category) {
      case WorkbenchCategory.resume:
        return ResumeScreen(
          currentTitle: _currentEntry?.displayName,
          onResumeCurrent: _resumeCurrent,
          onResumeSaved: _resumeSaved,
        );
      case WorkbenchCategory.music:
        return const MusicScreen();
      case WorkbenchCategory.paths:
        return PathsSettingsScreen(onLibraryShouldRescan: _scanLibrary);
      case WorkbenchCategory.video:
        return const VideoSettingsScreen();
      case WorkbenchCategory.audio:
        return const SettingsPlaceholder(title: 'Audio & Advanced');
      case WorkbenchCategory.input:
        return InputSettingsScreen(
          leftHanded: _leftHanded,
          onLeftHandedChanged: (v) {
            setState(() => _leftHanded = v);
            AppPrefs.setLeftHandedInput(v);
          },
          padMode: _padMode,
          onPadModeChanged: _setPadMode,
          customButtons: _customButtons,
          onCustomButtonsChanged: _setCustomButtons,
          joystickPort: _joystickPort,
          onJoystickPortChanged: _setJoystickPort,
          gamepadConnected: _gamepad.connected,
        );
      case WorkbenchCategory.about:
        return const AboutScreen();
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Shown above the library when some files matched a supported extension
/// but could not be read. Names the real cause and offers the one action
/// that fixes it, instead of leaving the user with a short list and no
/// explanation.
class _UnreadableBanner extends StatelessWidget {
  final int count;
  final VoidCallback onGrant;

  const _UnreadableBanner({required this.count, required this.onGrant});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF3A2E12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF8A6D2F)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.orangeAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count file${count == 1 ? '' : 's'} hidden: the app can list '
              'them but not read them. Grant "All files access" to use them.',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: onGrant,
            child: const Text('GRANT',
                style: TextStyle(color: ViceColors.accentTeal)),
          ),
        ],
      ),
    );
  }
}

/// The screensaver scroller's text.
///
/// A pure function of the four things it reports, so what it says can be
/// checked without a running core. It says which OS this copy is running on
/// (see services/platform_info.dart) -- it used to be a hardcoded "VICE
/// ANDROID", which stayed behind after the app was renamed and was still
/// claiming Android on a Linux desktop.
String backdropInfoText({
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
  // Only reported while the core is actually producing frames -- a "0 FPS"
  // on the workbench backdrop reads as a fault rather than as "not running".
  if (fps > 0) buf.write('   *   $fps FPS');
  return buf.toString();
}
