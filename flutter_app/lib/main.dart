import 'dart:async';

import 'package:flutter/material.dart';

import 'ffi/vice_bindings.dart';
import 'ffi/vice_native_paths.dart';
import 'screens/setup_wizard_screen.dart';
import 'screens/workbench_screen.dart';
import 'services/app_prefs.dart';
import 'services/artwork_service.dart';
import 'services/app_log.dart';
import 'services/video_settings.dart';
import 'services/vsid_service.dart';

void main() {
  // Persisted video preferences have to be read before the first frame is
  // painted, or the picture comes up with defaults and visibly snaps to the
  // user's settings a moment later. Nothing called this before, which meant
  // the Video settings never survived a restart at all.
  WidgetsFlutterBinding.ensureInitialized();
  // Before anything else that could fail: starting the log redirects the
  // process's stdout, and the emulator core writes there. Started later, the
  // core's own startup -- which is where ROM loading happens, and where the
  // interesting failures are -- would already have been written to a stdout
  // nobody was reading.
  unawaited(AppLog.init());
  unawaited(VideoSettings.instance.load());
  runApp(const ViceMultiplatformApp());
}

class ViceMultiplatformApp extends StatefulWidget {
  const ViceMultiplatformApp({super.key});

  @override
  State<ViceMultiplatformApp> createState() => _ViceMultiplatformAppState();
}

class _ViceMultiplatformAppState extends State<ViceMultiplatformApp>
    with WidgetsBindingObserver {
  ViceCoreBindings? _core;
  String? _loadError;
  bool? _setupCompleted;

  /// Whether the emulator core was already paused before we backgrounded, so
  /// coming back doesn't un-pause something the user had deliberately paused
  /// (e.g. they left a game sitting in the workbench).
  bool _corePausedBeforeBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCore();
    _checkSetup();
    _loadArtworkHost();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Silence everything while the app isn't in the foreground.
  ///
  /// Both audio sources keep running on their own native threads, completely
  /// independently of Flutter, so without this the SID music (and a running
  /// game's sound) carry on playing over the launcher/other apps after the
  /// app is minimised, and the emulator keeps burning CPU and battery in the
  /// background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      // inactive / paused / hidden / detached -- all mean "not on screen".
      _corePausedBeforeBackground = _core?.isPaused ?? false;
      VsidService.instance.pause();
      if (!_corePausedBeforeBackground) _core?.setPaused(true);
    } else {
      // Music deliberately does NOT auto-resume: it's a background track the
      // user chose to start, and silently restarting it on every app switch
      // is more annoying than leaving it stopped. The game core does resume,
      // but only if we were the ones who paused it.
      if (!_corePausedBeforeBackground) _core?.setPaused(false);
    }
  }

  /// Artwork host, read once at startup so the grid can draw box art without
  /// every tile hitting shared_preferences.
  Future<void> _loadArtworkHost() async {
    ArtworkService.baseUrl = await AppPrefs.getArtworkBaseUrl();
  }

  Future<void> _loadCore() async {
    try {
      final libPath = ViceNativePaths.gameCoreLibraryPath;
      // Android's ROM dir isn't known synchronously -- first launch has to
      // extract the bundled assets/vice/{C64,DRIVES} out of the APK into a
      // real filesystem path first (see extractBundledRomDir). This must
      // be awaited before core.init() runs, since VICE needs the ROM files
      // on disk at init time.
      final romDir = await ViceNativePaths.resolveRomDir();
      // Bundled SID tunes are extracted in the background at startup rather
      // than on first tap of the Music tab, so the playlist is ready when
      // the user gets there. Idempotent and non-fatal -- the Music screen
      // awaits the same call itself, and a failure there just means no
      // bundled fallback.
      unawaited(ViceNativePaths.extractBundledSidDir());
      // Recorded because these are the first things to check when a title
      // will not load, and they are invisible from outside the app: which
      // ROM directory the core was handed, and what is actually in it.
      AppLog.log('core lib: ${libPath ?? "(process)"}');
      AppLog.log('rom dir: ${romDir ?? "(none resolved)"}');
      AppLog.log('drive rom: ${await ViceNativePaths.driveRomFile() ?? "MISSING"}'
          ' (DRIVES holds: ${(await ViceNativePaths.driveRomsPresent()).join(", ")})');
      final core = ViceCoreBindings.load(libraryPath: libPath);
      if (romDir != null) {
        core.init(romDir);
        AppLog.log('core.init done');
      }
      if (!mounted) return;
      setState(() => _core = core);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.toString());
    }
  }

  Future<void> _checkSetup() async {
    final completed = await AppPrefs.isSetupCompleted();
    if (!mounted) return;
    setState(() => _setupCompleted = completed);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'C64-Retro Emulator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: _loadError != null
          ? _ErrorScreen(message: _loadError!)
          : (_core == null || _setupCompleted == null)
              ? const _LoadingScreen()
              : (_setupCompleted == false
                  ? SetupWizardScreen(
                      onComplete: () => setState(() => _setupCompleted = true),
                    )
                  : WorkbenchScreen(
                      core: _core!,
                      onRerunSetup: () =>
                          setState(() => _setupCompleted = false),
                    )),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF050607),
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  final String message;
  const _ErrorScreen({required this.message});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050607),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Failed to load libvicecore:\n$message',
            style: const TextStyle(color: Colors.redAccent),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
