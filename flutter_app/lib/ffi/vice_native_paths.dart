// Dev-time path resolution for the native VICE core library and its ROM
// directory.
//
// TODO(bundling): this is a hardcoded relative-path lookup that only works
// when the app is launched via `flutter run -d linux` from inside a full
// ViceMultiplatform checkout (the repo's native/ tree sits next to
// flutter_app/). Real packaging should instead:
//   - Linux: ship libvicecore.so next to the produced executable (CMake
//     install step / bundle 'lib' dir), loaded via a path derived from
//     Platform.resolvedExecutable.
//   - Android: put libvicecore.so under android/app/src/main/jniLibs/<abi>/
//     and load it by bare name ("libvicecore.so") -- the OS loader finds it.
//     DONE: libvicecore.so / libvicecore_vsid.so now ship in jniLibs/
//     arm64-v8a/ (built by native/vice_core/android/build.sh) and are
//     loaded by bare name -- see gameCoreLibraryPath/vsidCoreLibraryPath
//     below, which return null on Android on purpose.
//   - iOS/macOS: build it into an .xcframework and link statically or via
//     DynamicLibrary.process().
import 'dart:io';

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ViceNativePaths {
  ViceNativePaths._();

  /// The app's application-support directory.
  ///
  /// Everything that needs a writable per-app directory must come through
  /// here rather than calling path_provider itself -- on iOS that plugin
  /// throws (see below), and each call site that forgot produced its own
  /// silent failure. Save states were the last one: capture() threw here,
  /// _backToLibrary swallowed it as "this title cannot snapshot", and no
  /// session was ever recorded.
  ///
  /// Application-support directory to extract the bundled ROMs into.
  ///
  /// Goes through path_provider everywhere except iOS. There, path_provider
  /// 2.6's Apple implementation depends on package:objective_c, whose native
  /// asset fails to load in the Linux-built iOS app:
  ///
  ///   dlopen(objective_c.dylib): symbol not found in flat namespace
  ///   '_Dart_PostInteger_DL'
  ///
  /// which surfaced as "Failed to load libvicecore" -- the ROM lookup threw
  /// before the core was ever opened. iOS sets HOME to the app's data
  /// container, so the same directory is reachable without any plugin. The
  /// plugin is still tried first, so this stops being used the moment the
  /// native-asset problem is fixed upstream.
  static Future<String> supportDirPath() async {
    if (Platform.isIOS) {
      return _iosContainerSubdir(p.join('Library', 'Application Support'));
    }
    return (await getApplicationSupportDirectory()).path;
  }

  /// The app's Documents directory on iOS, without going through
  /// path_provider. This is where imported .d64/.tap files live -- see
  /// StorageAccess's iOS strategy.
  static Future<String> iosDocumentsDirPath() =>
      _iosContainerSubdir('Documents');

  /// Resolves [relative] inside the iOS app data container, creating it.
  ///
  /// Both routes here find the container without a plugin. HOME is the
  /// documented one, but it comes back empty in this build, so the real
  /// workhorse is systemTemp: on iOS that is NSTemporaryDirectory
  /// (`<container>/tmp`), whose parent is the container root.
  static Future<String> _iosContainerSubdir(String relative) async {
    final home = Platform.environment['HOME'];
    final container = (home != null && home.isNotEmpty)
        ? Directory(home)
        : Directory.systemTemp.parent;
    final dir = Directory(p.join(container.path, relative));
    await dir.create(recursive: true);
    return dir.path;
  }

  /// The C64 ROM set the emulator needs: kernal, BASIC and chargen, plus the
  /// 1541 DOS ROM for disk images.
  ///
  /// These are NOT bundled -- they are Commodore's, still in copyright, and
  /// not ours to redistribute (see pubspec.yaml). The user supplies them, and
  /// they live under the app's support directory:
  ///
  ///   `<support>/vice/C64/`     kernal, basic, chargen
  ///   `<support>/vice/DRIVES/`  dos1541 (needed or D64 autostart fails with
  ///                           ?DEVICE NOT PRESENT)
  ///
  /// Returns the root of that tree whether or not it is populated; use
  /// [romsInstalled] to find out if the core can actually start.
  static Future<String> romDir() async =>
      p.join(await supportDirPath(), 'vice');

  /// The three files without which the C64 cannot boot at all.
  static const List<String> requiredRomNames = [
    'kernal-901227-03.bin',
    'basic-901226-01.bin',
    'chargen-901225-01.bin',
  ];

  /// The 1541 drive ROM, which is a SEPARATE requirement from the three
  /// above and fails in a completely different way.
  ///
  /// The machine boots fine without it -- you get a READY prompt and every
  /// cartridge, tape and .prg works -- so nothing looks wrong until you load
  /// a disk image and the drive answers `?DEVICE NOT PRESENT`. Because .d64
  /// is most of the C64 library, "ROMs installed" must not be reported as
  /// true on the strength of the machine ROMs alone; see [driveRomInstalled].
  static const List<String> driveRomNames = [
    'dos1541-325302-01+901229-05.bin',
  ];

  /// Whether a usable ROM set is present.
  ///
  /// Deliberately checks for the files rather than just the directory: an
  /// empty vice/C64 folder left over from a failed import would otherwise
  /// read as "installed" and the core would fail later, further from the
  /// cause.
  static Future<bool> romsInstalled() async =>
      romsInstalledIn(Directory(p.join(await romDir(), 'C64')));

  /// The detection itself, split out so it can be tested against a real
  /// directory without needing a device or an app container.
  ///
  /// Any kernal/basic/chargen trio will do: users bring their own dumps and
  /// the filenames vary by machine revision (kernal-901227-03, kernal-251104-04
  /// and so on), so this matches on prefix rather than the exact names in
  /// [requiredRomNames].
  static bool romsInstalledIn(Directory c64Dir) {
    if (!c64Dir.existsSync()) return false;
    final names = c64Dir
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path).toLowerCase())
        .toList();
    bool hasPrefix(String prefix) => names.any((n) => n.startsWith(prefix));
    return hasPrefix('kernal') && hasPrefix('basic') && hasPrefix('chargen');
  }

  /// Whether the 1541 drive ROM is present, i.e. whether disk images will
  /// work. Independent of [romsInstalled] -- see [driveRomNames].
  static Future<bool> driveRomInstalled() async =>
      driveRomInstalledIn(Directory(p.join(await romDir(), 'DRIVES')));

  /// Any `dos1541*` will do: VICE has shipped it as a bare `dos1541`, as
  /// `dos1541.bin`, and (since 3.5) under its part numbers as
  /// `dos1541-325302-01+901229-05.bin`. All three are the same ROM and all
  /// three are what a user copying from their own VICE install will have.
  static bool driveRomInstalledIn(Directory drivesDir) {
    if (!drivesDir.existsSync()) return false;
    return drivesDir
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path).toLowerCase())
        .any((n) => n.startsWith('dos1541'));
  }

  /// Where the user's imported SID tunes live.
  static Future<String> sidDir() async =>
      p.join(await supportDirPath(), 'sids');

  /// Marker for the bundled-SID extraction. Unlike a plain "did I run yet"
  /// flag this one has CONTENT: the sorted list of asset names it was
  /// written for. The playlist grows over time, and an already-installed app
  /// would otherwise skip extraction forever and never see the new tunes.
  static const String _sidMarkerName = '.extracted';

  /// Extracts the bundled SID tunes (assets/sids/, declared in pubspec.yaml)
  /// into a real directory, once, and returns it.
  ///
  /// The SID player reads these by path via vice_vsid_launch(), so they
  /// genuinely have to be files on disk -- an asset-bundle handle is not
  /// something the native core can open.
  ///
  /// Imported tunes live elsewhere and are found separately; see
  /// music_screen.dart, which searches both.
  static Future<String> extractBundledSidDir() async {
    final sidRoot = await sidDir();
    final marker = File(p.join(sidRoot, _sidMarkerName));

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest
        .listAssets()
        .where((path) => path.startsWith('assets/sids/'))
        .toList()
      ..sort();
    final expected = assets.join('\n');

    if (marker.existsSync() && marker.readAsStringSync() == expected) {
      return sidRoot;
    }

    for (final assetPath in assets) {
      final relative = assetPath.substring('assets/sids/'.length);
      if (relative.isEmpty) continue;
      final outFile = File(p.join(sidRoot, relative));
      await outFile.parent.create(recursive: true);
      final bytes = await rootBundle.load(assetPath);
      await outFile.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
    }

    await marker.create(recursive: true);
    await marker.writeAsString(expected, flush: true);
    return sidRoot;
  }

  /// Walks up from the current working directory (and from the script's own
  /// directory, for `flutter run`'s working-directory quirks) looking for a
  /// ViceMultiplatform checkout root (a directory containing `native/`).
  static Directory? _findRepoRoot() {
    final candidates = <Directory>[
      Directory.current,
      Directory(p.dirname(Platform.script.toFilePath())),
    ];
    for (final start in candidates) {
      Directory dir = start;
      for (int i = 0; i < 8; i++) {
        if (Directory(p.join(dir.path, 'native', 'vice_core')).existsSync()) {
          return dir;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }
    return null;
  }

  /// Absolute path to libvicecore.so built by native/vice_core/linux, or
  /// null if it can't be found (falls back to bare-name loading, which
  /// works if the .so happens to be on LD_LIBRARY_PATH). Always null on
  /// Android: the .so ships in jniLibs/arm64-v8a/ and is loaded by bare
  /// name ("libvicecore.so") via the OS loader, same as the reference
  /// VICEAndroid app -- there is no repo-relative dev path to find on a
  /// real device. (_findRepoRoot() would also naturally fail to find
  /// native/vice_core under the app sandbox, but this is explicit.)
  static String? get gameCoreLibraryPath {
    if (Platform.isAndroid) return null;
    if (Platform.isIOS) return _iosFrameworkLibrary('libvicecore.dylib');
    final root = _findRepoRoot();
    if (root == null) return null;
    final path = p.join(root.path, 'native', 'vice_core', 'linux', 'build',
        'libvicecore.so');
    return File(path).existsSync() ? path : null;
  }

  static String? get vsidCoreLibraryPath {
    if (Platform.isAndroid) return null;
    if (Platform.isIOS) return _iosFrameworkLibrary('libvicecore_vsid.dylib');
    final root = _findRepoRoot();
    if (root == null) return null;
    final path = p.join(root.path, 'native', 'vice_core', 'linux', 'build',
        'libvicecore_vsid.so');
    return File(path).existsSync() ? path : null;
  }

  /// Absolute path to a dylib shipped inside the iOS app bundle's Frameworks
  /// directory, which sits next to the executable
  /// (Runner.app/Runner and Runner.app/Frameworks/).
  ///
  /// Loaded by explicit path rather than through [DynamicLibrary.process] --
  /// the dylib is bundled, not linked into the Runner binary, so its symbols
  /// are not in the global namespace until something dlopens it. Nothing else
  /// references it, so nothing else will.
  static String? _iosFrameworkLibrary(String name) {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final path = p.join(exeDir, 'Frameworks', name);
    return File(path).existsSync() ? path : null;
  }

  /// Async ROM-dir resolver that works on every platform this app targets:
  /// Android extracts bundled assets to a real filesystem dir (once) and
  /// returns that; everywhere else it's just [devRomDir] wrapped in a
  /// completed Future. Use this from app startup instead of [devRomDir]
  /// directly so the same call site works on both.
  static Future<String?> resolveRomDir() async {
    // A dev checkout keeps working off the repo's test fixtures; everywhere
    // else it is whatever ROM set the user installed.
    final dev = devRomDir;
    if (dev != null) return dev;
    return await romsInstalled() ? await romDir() : null;
  }

  /// ROM directory (contains a C64/ subdir with kernal/basic/chargen) used
  /// for development. Points at the native test fixtures, which are
  /// checked into the repo for exactly this purpose.
  static String? get devRomDir {
    final root = _findRepoRoot();
    if (root == null) return null;
    final path = p.join(
        root.path, 'native', 'vice_core', 'linux', 'test', 'testdata');
    return Directory(p.join(path, 'C64')).existsSync() ? path : null;
  }
}
