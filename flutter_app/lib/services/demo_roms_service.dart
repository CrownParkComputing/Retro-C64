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

  /// What the demo is called in the library.
  static const String demoTitle = 'Retro-C64 Demo';

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
