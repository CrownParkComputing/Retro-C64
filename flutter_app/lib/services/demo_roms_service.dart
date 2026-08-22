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
/// installed. VICE wants extensionless names in its own C64 directory.
const Map<String, String> _openRomAssets = {
  'assets/vice/OPENROMS/kernal': 'kernal',
  'assets/vice/OPENROMS/basic': 'basic',
  'assets/vice/OPENROMS/chargen': 'chargen',
};

class DemoRomsService {
  /// Copy the Open ROMs into [viceDir]/C64, replacing whatever is there.
  ///
  /// Returns the number installed. Deliberately overwrites: the caller is
  /// switching the machine into demo mode, and half a ROM set is a machine
  /// that boots to a black screen.
  static Future<int> install(Directory viceDir) async {
    final target = Directory('${viceDir.path}/C64');
    await target.create(recursive: true);
    var n = 0;
    for (final entry in _openRomAssets.entries) {
      final data = await rootBundle.load(entry.key);
      final file = File('${target.path}/${entry.value}');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      n++;
    }
    return n;
  }

  /// True when the ROMs currently installed are the Open ones rather than a
  /// user's own. Decided by SIZE and content, not by a flag we wrote down:
  /// a flag goes stale the moment somebody imports their own set over the top.
  static Future<bool> installed(Directory viceDir) async {
    final kernal = File('${viceDir.path}/C64/kernal');
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

  /// The demo itself: a BASIC listing typed at the READY prompt.
  ///
  /// TYPED, not loaded. Loading needs the 1541's own Commodore ROM, which the
  /// app cannot ship either, so a .prg or .d64 demo would fail on exactly the
  /// machine this is meant to prove works.
  static const List<String> demoProgram = <String>[
    '10 POKE 53280,0:POKE 53281,0',
    '20 PRINT CHR\$(147)',
    '30 PRINT "RETRO-C64"',
    '40 PRINT',
    '50 PRINT "THIS IS A REAL C64, RUNNING ON"',
    '60 PRINT "FREE OPEN-SOURCE ROMS."',
    '70 PRINT',
    '80 PRINT "NO COMMODORE ROMS WERE NEEDED"',
    '90 PRINT "TO SHOW YOU THIS."',
    '100 FOR I=0 TO 15:POKE 53280,I',
    '110 FOR J=0 TO 60:NEXT J,I',
    '120 GOTO 100',
    'RUN',
  ];
}
