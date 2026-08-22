import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'ffi/vice_bindings.dart';
import 'ffi/vice_native_paths.dart';
import 'screens/setup_wizard_screen.dart';
import 'screens/workbench_screen.dart';
import 'services/app_prefs.dart';
import 'services/artwork_service.dart';
import 'services/startup_import.dart';
import 'services/app_log.dart';
import 'services/demo_roms_service.dart';
import 'services/service_locator.dart';
import 'services/video_settings.dart';
import 'services/vsid_service.dart';

import 'view_models/workbench_view_model.dart';

void main() async {
  // Persisted video preferences have to be read before the first frame is
  // painted, or the picture comes up with defaults and visibly snaps to the
  // user's settings a moment later. Nothing called this before, which meant
  // the Video settings never survived a restart at all.
  WidgetsFlutterBinding.ensureInitialized();

  await setupServiceLocator();

  // Before anything else that could fail: starting the log redirects the
  // process's stdout, and the emulator core writes there. Started later, the
  // core's own startup -- which is where ROM loading happens, and where the
  // interesting failures are -- would already have been written to a stdout
  // nobody was reading.
  unawaited(AppLog.init());
  _logFrameworkErrors();
  unawaited(getIt<VideoSettings>().load());
  runApp(const RetroC64App());
}

/// Writes framework and unhandled async errors into the app's own log.
///
/// Without this a layout failure is invisible from outside. In release there
/// is no red error screen: the widget that threw simply does not paint, so a
/// tester reports "white screen" or "it just shows nothing" and there is
/// nothing to go on -- the exception never leaves the device. That is exactly
/// how a portrait-only overflow on iPhone was reported, and it could not be
/// diagnosed from the report alone.
///
/// The default handler still runs, so debug builds keep their red screen and
/// console output. This only adds a copy to Documents/c64retro-log.txt, which
/// the user can send back from the Files app.
void _logFrameworkErrors() {
  final defaultHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    // Library and context say which subsystem and which widget, which is the
    // part that turns "white screen" into a place to look.
    AppLog.log('FLUTTER ERROR [${details.library}] ${details.exception}');
    if (details.context != null) {
      AppLog.log('  while ${details.context!.toDescription()}');
    }
    final stack = details.stack;
    if (stack != null) {
      // Trimmed: the frames below the app's own code are framework internals
      // and the same for every report.
      AppLog.log(stack.toString().split('\n').take(12).join('\n'));
    }
    defaultHandler?.call(details);
  };

  // Errors outside the widget tree -- a failed await in a timer or an isolate
  // callback -- never reach FlutterError.onError at all.
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.log('UNCAUGHT $error');
    AppLog.log(stack.toString().split('\n').take(12).join('\n'));
    return false;
  };
}

class RetroC64App extends StatefulWidget {
  const RetroC64App({super.key});

  @override
  State<RetroC64App> createState() => _RetroC64AppState();
}

class _RetroC64AppState extends State<RetroC64App>
    with WidgetsBindingObserver {
  ViceCoreBindings? _core;
  String? _loadError;
  bool? _setupCompleted;
  String? _appVersion;

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
      getIt<VsidService>().pause();
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
    ArtworkService.baseUrl = await getIt<AppPrefs>().getArtworkBaseUrl();
  }

  Future<void> _loadCore() async {
    try {
      final libPath = ViceNativePaths.gameCoreLibraryPath;
      // Android's ROM dir isn't known synchronously -- first launch has to
      // extract the bundled assets/vice/{C64,DRIVES} out of the APK into a
      // real filesystem path first (see extractBundledRomDir). This must
      // be awaited before core.init() runs, since VICE needs the ROM files
      // on disk at init time.
      // A ROM zip dropped in the app's folder installs itself. The Files app
      // is the only road files travel on iOS - apps cannot see the system
      // Downloads folder - so "put the zip in the app's folder" has to be the
      // whole job: no browse, no button, the next launch finds it. Runs
      // before resolveRomDir so a first launch with a zip waiting boots the
      // machine rather than reporting no ROMs.
      final imported = await getIt<StartupImport>().run();
      if (imported.tunes > 0 || imported.games > 0 || imported.roms > 0) {
        AppLog.log('startup import: ${imported.roms} ROM(s), '
            '${imported.tunes} tune(s), ${imported.games} game(s)');
      }
      // Which ROMs this run boots on is decided HERE and cannot change
      // later: VICE loads them when the machine starts and the bridge has no
      // supported way to tear that down and re-run it in-process. Demo mode
      // therefore points the whole process at the demo's own directory, and
      // the user's ROM directory is not touched or even read.
      final demoRomMode = await getIt<AppPrefs>().getDemoRomMode();
      String? romDir;
      if (demoRomMode) {
        try {
          await getIt<DemoRomsService>().prepareDemoEnvironment();
          romDir = (await getIt<DemoRomsService>().demoRomDir()).path;
          AppLog.log('free-ROM demo mode: booting from $romDir');
        } catch (e) {
          AppLog.log('free-ROM demo mode failed to prepare ($e); '
              'falling back to the installed ROMs');
          romDir = null;
        }
      }
      romDir ??= await ViceNativePaths.resolveRomDir();
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
        // Match the .prg autostart path to whose ROMs are actually fitted.
        //
        // The usual path patches Commodore KERNAL routines at fixed
        // addresses; the bundled Open ROMs are a clean reimplementation and
        // do not have them, so a .prg autostarted that way never loads and
        // reports "?DEVICE NOT PRESENT". Injecting into RAM needs no KERNAL.
        // It is not used with real ROMs because it can only start what RUN
        // starts -- a machine-code title would sit at READY doing nothing.
        //
        // Against the directory the core was actually handed, not the
        // default one: a dev checkout resolves to the repo's test fixtures,
        // and asking about a folder the core is not using would get the
        // answer wrong in exactly the setup used to develop this.
        // In demo mode this is not a guess: the free ROMs are what booted,
        // and their .prg autostart MUST be RAM injection. The usual path
        // patches Commodore KERNAL routines the free ROMs do not have, and
        // the load then goes out to a drive that is not there -- which is
        // the "?DEVICE NOT PRESENT" the demo was failing with.
        final demoRoms = demoRomMode ||
            await getIt<DemoRomsService>().installed(Directory(romDir));
        core.setPrgInject(demoRoms);
        // Said out loud, because the failure is otherwise invisible: the
        // FFI binding looks this symbol up softly, so a libvicecore built
        // before it existed makes setPrgInject a no-op and the demo then
        // fails to load with "?DEVICE NOT PRESENT" -- with nothing anywhere
        // pointing at a stale native library as the reason. The Android and
        // iOS cores are prebuilt and committed, so exactly this drift has
        // happened once already.
        if (demoRoms && !core.hasPrgInjectApi) {
          AppLog.log('WARNING: libvicecore has no vice_core_set_prg_inject. '
              'It is older than the Dart side, and free ROMs cannot autostart '
              'a .prg without it. Rebuild the native core for this platform.');
        }
        AppLog.log('prg autostart: ${demoRoms ? "RAM injection (Open ROMs)" : "virtual filesystem"}');
      registerCore(core);
      } else {
        // Without a ROM dir the core has no data directory, so VICE cannot
        // create its XDG dirs and aborts during archdep_init. That abort used
        // to call exit() and take the whole app down on the first launch of
        // any title; the bridge now contains it and vice_core_start refuses
        // outright, but the user still deserves to be told why rather than
        // watching a game fail to start.
        AppLog.log('core.init SKIPPED: no ROM directory resolved -- the C64 '
            'and DRIVES ROMs are missing, so no title can be launched');
      }
      if (!mounted) return;
      setState(() => _core = core);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.toString());
    }
  }

  Future<void> _checkSetup() async {
    // Keyed on the running version, so every new build shows the wizard once.
    // What setup says -- what the app ships, what it needs, the Open ROM
    // demo -- changes from build to build, and a tester or a store reviewer
    // installing a fresh one would otherwise never see any of it, because a
    // flag set weeks ago said setup was done.
    String? version;
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (e) {
      // No version available -- a test binding, or a platform where the
      // plugin is missing. Fall back to the plain flag rather than showing
      // the wizard on every single launch, which is what an unknown version
      // compared against a stored one would do.
      AppLog.log('app version unavailable ($e); setup flag is not '
          'version-keyed this run');
    }
    final completed = version == null
        ? await getIt<AppPrefs>().isSetupCompleted()
        : await getIt<AppPrefs>().setupCompletedFor(version);
    if (!mounted) return;
    setState(() {
      _appVersion = version;
      _setupCompleted = completed;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Retro-C64',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_loadError != null) return _ErrorScreen(message: _loadError!);
    if (_core == null || _setupCompleted == null) return const _LoadingScreen();

    return ChangeNotifierProvider(
      create: (_) => WorkbenchViewModel(core: _core!),
      child: _setupCompleted == false
          ? SetupWizardScreen(
              onComplete: () {
                final v = _appVersion;
                if (v != null) unawaited(getIt<AppPrefs>().setSetupCompletedFor(v));
                setState(() => _setupCompleted = true);
              },
            )
          : WorkbenchScreen(
              onRerunSetup: () => setState(() => _setupCompleted = false),
            ),
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
