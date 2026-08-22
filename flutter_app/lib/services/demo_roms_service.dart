// Installs the OPEN ROMs so the app can show a working C64 with nothing
// supplied by the user.
//
// WHY THIS EXISTS. Until now the app could do nothing at all until somebody
// found three Commodore ROM files: a first run ended at a prompt asking for
// them, which is a poor way to meet a program and gives a reviewer nothing to
// look at. The Open ROMs (MEGA65's clean-room BASIC/KERNAL/charset, GPL) boot
// a real C64 to READY, so the emulator can be SHOWN working and the question
// of the real ROMs becomes a later, optional one.
//
// WHAT THEY ARE NOT. Open ROMs is an ongoing project and does not implement
// every KERNAL routine. Two consequences the UI must be honest about:
//
//   * commercial software written against the original ROMs may not run;
//   * anything that LOADS from disk is doubly out of reach, because the 1541
//     also needs Commodore's drive ROM, which is equally not ours to ship.
//     A demo has to be typed or injected, not loaded -- which is why the demo
//     here is a BASIC listing rather than the .prg/.d64 pair.
//
// Verified on the desktop with the real VICE: these three boot to
// "OPEN ROMS GENERIC BUILD ... READY." and accept keyboard input.
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import '../ffi/vice_native_paths.dart';

/// Where the Open ROMs live in the bundle, and what each is called once
/// installed.
///
/// The installed names are VICE's OWN DEFAULTS, not descriptive ones. The
/// bridge starts the core without -kernal/-basic/-chargen, so VICE looks up
/// its built-in resource defaults inside the C64 directory; a file called
/// plain "kernal" is never opened and the core dies at
/// "Couldn't load kernal ROM `kernal-901227-03.bin'". These are the same
/// names ViceNativePaths.requiredRoms expects of a user's own dump, so demo
/// ROMs and real ROMs occupy the same slots and the later one wins.
const Map<String, String> _openRomAssets = {
  'assets/vice/OPENROMS/kernal': 'kernal-901227-03.bin',
  'assets/vice/OPENROMS/basic': 'basic-901226-01.bin',
  'assets/vice/OPENROMS/chargen': 'chargen-901225-01.bin',
};

class DemoRomsService {
  /// The demo's OWN ROM directory, beside the user's rather than inside it.
  ///
  /// This is what keeps the two worlds apart. The Open ROMs have to be called
  /// what VICE calls its ROMs, so putting them in the user's directory means
  /// standing on top of that user's own dump -- fine on a first run with an
  /// empty folder, not fine for something you can now start at any time. The
  /// core takes its ROM directory as an argument (vice_core_init) and reads
  /// it when a machine starts, so the demo simply points the core somewhere
  /// else for as long as it runs, and points it back afterwards. Nothing of
  /// the user's is moved, copied or overwritten.
  /// It is also a VISIBLE directory, not a private one. A store review team
  /// has to be able to look at what the app claims to ship -- the free ROMs,
  /// their licence text and the demo program -- and "trust us, they are in
  /// there somewhere" is not an answer. On iOS this is the Documents folder
  /// the Files app shows; elsewhere it is the app's own media folder, which
  /// is reachable over USB. The compliance page prints the full path and
  /// lists what is in it.
  static Future<Directory> demoRomDir() async {
    final root = Platform.isIOS
        ? await ViceNativePaths.iosDocumentsDirPath()
        : await ViceNativePaths.mediaDirPath();
    return Directory('$root/FreeRomDemo');
  }

  /// Everything the demo directory holds, for display. Names only -- the
  /// point is that a reviewer can see the list and go and open the files.
  static Future<List<String>> demoFiles({Directory? from}) async {
    final dir = from ?? await demoRomDir();
    if (!dir.existsSync()) return const [];
    final names = <String>[];
    for (final e in dir.listSync(recursive: true)) {
      if (e is File) {
        names.add(e.path.substring(dir.path.length + 1));
      }
    }
    names.sort();
    return names;
  }

  /// Lays out the demo's own world: its ROMs and its program. Idempotent.
  ///
  /// Returns the .prg to start. The program lives here too, not in the user's
  /// games folder, because it belongs to the demo rather than to their
  /// library -- see [installDemoProgram] for the case where they do want a
  /// copy of it among their own files.
  ///
  /// [into] overrides the location, which is how this is tested without a
  /// platform channel: resolving the real directory needs path_provider, and
  /// a service that can only be exercised on a device is one whose promises
  /// go unchecked.
  static Future<String> prepareDemoEnvironment({Directory? into}) async {
    final root = into ?? await demoRomDir();
    await install(root);
    // Clear out any earlier demo before writing this one.
    //
    // The name has changed once already -- it was the display name, spaces
    // and all, until the emulated machine turned out to be the thing reading
    // it -- and the old file simply stayed behind, so the library listed two
    // demos where there is one. Anything ending in .prg here belongs to the
    // demo and is ours to replace; nothing of the user's is ever written to
    // this folder.
    if (root.existsSync()) {
      for (final f in root.listSync()) {
        if (f is File &&
            f.path.toLowerCase().endsWith('.prg') &&
            f.uri.pathSegments.last != demoFileName) {
          f.deleteSync();
        }
      }
    }

    final prg = File('${root.path}/$demoFileName');
    final data = await rootBundle.load(_demoAsset);
    await prg.writeAsBytes(data.buffer.asUint8List(), flush: true);

    // The licence text goes next to the ROMs it covers, so that anyone
    // looking at the files can see the terms without leaving the folder.
    // The LGPL is written as an additional permission on top of the GPL, so
    // both texts are needed to state it correctly.
    for (final name in const [
      'README.txt',
      'COPYING',
      'COPYING.LESSER',
      'LICENSE.txt',
    ]) {
      final bytes = await rootBundle.load('assets/vice/OPENROMS/$name');
      await File('${root.path}/$name')
          .writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    }
    return prg.path;
  }

  /// Suffix for a user ROM moved aside so a demo ROM can take its name.
  static const String _backupSuffix = '.user-rom';

  /// Copy the Open ROMs into [viceDir]/C64, moving any of the user's own
  /// ROMs aside first.
  ///
  /// Returns the number installed.
  ///
  /// The Open ROMs have to occupy VICE's default filenames, which are the
  /// same names a user's own dump occupies -- so installing them on a machine
  /// that already has real ROMs would overwrite them. That was harmless while
  /// this only ran on a first launch with an empty ROM directory. It stopped
  /// being harmless the moment the demo became something you can run again at
  /// any time, from Paths or by re-running setup: it would have destroyed a
  /// ROM set the user may have no other copy of.
  ///
  /// So anything that is not already one of ours is renamed rather than
  /// overwritten, and [restoreUserRoms] puts it back.
  static Future<int> install(Directory viceDir) async {
    final target = Directory('${viceDir.path}/C64');
    await target.create(recursive: true);
    var n = 0;
    for (final entry in _openRomAssets.entries) {
      final data = await rootBundle.load(entry.key);
      final bytes = data.buffer.asUint8List();
      final file = File('${target.path}/${entry.value}');

      if (await file.exists() && !await _sameBytes(file, bytes)) {
        final backup = File('${file.path}$_backupSuffix');
        // Never clobber an existing backup: that would be the user's real ROM
        // being replaced by a previous demo's copy of itself.
        if (!await backup.exists()) await file.rename(backup.path);
      }

      await file.writeAsBytes(bytes, flush: true);
      n++;
    }
    return n;
  }

  /// Whether a user ROM is waiting to be put back, i.e. whether the machine
  /// is in demo mode over the top of somebody's own set.
  static Future<bool> hasUserRomBackup(Directory viceDir) async {
    for (final name in _openRomAssets.values) {
      if (await File('${viceDir.path}/C64/$name$_backupSuffix').exists()) {
        return true;
      }
    }
    return false;
  }

  /// Puts the user's own ROMs back, undoing [install]. Returns how many were
  /// restored.
  static Future<int> restoreUserRoms(Directory viceDir) async {
    var n = 0;
    for (final name in _openRomAssets.values) {
      final backup = File('${viceDir.path}/C64/$name$_backupSuffix');
      if (!await backup.exists()) continue;
      await backup.rename('${viceDir.path}/C64/$name');
      n++;
    }
    return n;
  }

  static Future<bool> _sameBytes(File file, List<int> other) async {
    final there = await file.readAsBytes();
    if (there.length != other.length) return false;
    for (var i = 0; i < other.length; i++) {
      if (there[i] != other[i]) return false;
    }
    return true;
  }

  /// True when the ROMs currently installed are the Open ones rather than a
  /// user's own. Decided by SIZE and content, not by a flag we wrote down:
  /// a flag goes stale the moment somebody imports their own set over the top.
  static Future<bool> installed(Directory viceDir) async {
    final kernal = File('${viceDir.path}/C64/${_openRomAssets.values.first}');
    if (!await kernal.exists()) return false;
    final ours = (await rootBundle.load('assets/vice/OPENROMS/kernal'))
        .buffer
        .asUint8List();
    final there = await kernal.readAsBytes();
    if (there.length != ours.length) return false;
    for (var i = 0; i < ours.length; i++) {
      if (there[i] != ours[i]) return false;
    }
    return true;
  }

  /// What the demo is called in the library, where the app's own scanner
  /// reads it and spaces are harmless.
  static const String demoTitle = 'Retro-C64 Demo';

  /// What the demo file is called inside the demo's own directory.
  ///
  /// Short, upper case, no spaces, 8.3. This one is not read by the app but
  /// by the emulated machine, whose filesystem device speaks PETSCII and
  /// whose LOAD syntax has to survive being typed and echoed on a 40-column
  /// screen -- "Retro-C64 Demo.prg" does not, and produced a load that
  /// failed with the wrong name on screen.
  static const String demoFileName = 'DEMO.PRG';

  /// Puts the demo .prg in the user's media folder, so it appears in Games
  /// alongside anything else they have and is started the same way.
  ///
  /// The user drives it. Nothing is autoplayed and no keys are pressed for
  /// them: setup says the demo is there, and they pick it.
  ///
  /// Returns the installed path. Overwrites, so a newer build of the app
  /// replaces an older demo rather than leaving a stale one; nothing else is
  /// called this, and it is ours to replace.
  static Future<String> installDemoProgram(Directory mediaDir) async {
    await mediaDir.create(recursive: true);
    final file = File('${mediaDir.path}/$demoTitle.prg');
    final data = await rootBundle.load(_demoAsset);
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return file.path;
  }

  static const String _demoAsset = 'assets/demo/demo.prg';


}
