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

  /// Marker file written after a successful first-run ROM extraction on
  /// Android, so subsequent launches skip re-copying ~1.1MB of asset files
  /// out of the APK on every startup. Named after the last file extraction
  /// writes so a killed-mid-extraction run doesn't leave a false marker.
  static const String _androidRomMarkerName = '.extracted';

  /// Extracts assets/vice/{C64,DRIVES} (declared in pubspec.yaml, sourced
  /// from VICEAndroid's proven-good ROM set) into a real filesystem
  /// directory under the app's support dir, once. Safe to call every
  /// launch -- it's a no-op after the first successful extraction (checked
  /// via a marker file, not just kernal's existence, so a partial/failed
  /// extraction is retried rather than silently left broken).
  ///
  /// Returns the extracted C64/DRIVES root (i.e. the same shape devRomDir
  /// returns on Linux: a directory containing a `C64/` subdir).
  static Future<String> extractAndroidRomDir() async {
    final supportDir = await getApplicationSupportDirectory();
    final romRoot = p.join(supportDir.path, 'vice');
    final marker = File(p.join(romRoot, _androidRomMarkerName));
    if (marker.existsSync()) {
      return romRoot;
    }

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest
        .listAssets()
        .where((path) => path.startsWith('assets/vice/'));

    for (final assetPath in assets) {
      // assetPath looks like "assets/vice/C64/kernal-901227-03.bin" ->
      // strip the "assets/vice/" prefix so it lands at romRoot/C64/....
      final relative = assetPath.substring('assets/vice/'.length);
      final outFile = File(p.join(romRoot, relative));
      await outFile.parent.create(recursive: true);
      final bytes = await rootBundle.load(assetPath);
      await outFile.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
    }

    await marker.create(recursive: true);
    return romRoot;
  }

  /// Marker for the bundled-SID extraction. Unlike the ROM marker this one
  /// has CONTENT: the sorted list of asset names it was written for. The
  /// SID playlist grows over time (it went 10 -> 20 tunes), and an
  /// already-installed app would otherwise skip extraction forever and
  /// never see the new files. Comparing the manifest catches that.
  static const String _sidMarkerName = '.extracted';

  /// Extracts the bundled Top-10 SID tunes (assets/sids/, declared in
  /// pubspec.yaml) into a real filesystem directory under the app's support
  /// dir, once, and returns that directory.
  ///
  /// Unlike [extractAndroidRomDir] this runs on EVERY platform, not just
  /// Android: the point is that the Music tab always has its Top-10
  /// available out of the box. On Linux the Music screen still prefers a
  /// real user Music/ folder if one exists next to the configured Games
  /// folder, and only falls back here.
  ///
  /// The SID player reads these by path via vice_vsid_launch(), so they
  /// genuinely have to be files on disk -- an asset bundle handle is not
  /// something the native core can open.
  static Future<String> extractBundledSidDir() async {
    final supportDir = await getApplicationSupportDirectory();
    final sidRoot = p.join(supportDir.path, 'sids');
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
    final root = _findRepoRoot();
    if (root == null) return null;
    final path = p.join(root.path, 'native', 'vice_core', 'linux', 'build',
        'libvicecore.so');
    return File(path).existsSync() ? path : null;
  }

  static String? get vsidCoreLibraryPath {
    if (Platform.isAndroid) return null;
    final root = _findRepoRoot();
    if (root == null) return null;
    final path = p.join(root.path, 'native', 'vice_core', 'linux', 'build',
        'libvicecore_vsid.so');
    return File(path).existsSync() ? path : null;
  }

  /// Async ROM-dir resolver that works on every platform this app targets:
  /// Android extracts bundled assets to a real filesystem dir (once) and
  /// returns that; everywhere else it's just [devRomDir] wrapped in a
  /// completed Future. Use this from app startup instead of [devRomDir]
  /// directly so the same call site works on both.
  static Future<String?> resolveRomDir() {
    if (Platform.isAndroid) return extractAndroidRomDir();
    return Future.value(devRomDir);
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
