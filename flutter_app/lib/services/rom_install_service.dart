import 'dart:io';

import 'package:path/path.dart' as p;

import '../ffi/vice_native_paths.dart';
import 'storage_access.dart';

/// What a scan found and installed.
class RomScanResult {
  /// Machine ROMs installed into vice/C64 (kernal, basic, chargen).
  final int machineRoms;

  /// Drive ROMs installed into vice/DRIVES (dos1541 and friends).
  final int driveRoms;

  const RomScanResult({
    this.machineRoms = 0,
    this.driveRoms = 0,
  });

  int get total => machineRoms + driveRoms;
  bool get isEmpty => total == 0;

  String get summary {
    if (isEmpty) return 'Nothing found to import.';
    final parts = <String>[
      if (machineRoms > 0) '$machineRoms C64 ROM(s)',
      if (driveRoms > 0) '$driveRoms drive ROM(s)',
    ];
    return 'Imported ${parts.join(', ')}.';
  }
}

/// Installs the C64 BIOS ROM set by scanning, not by asking.
///
/// BIOS only. Game media and SID tunes are the games scan's job
/// (StorageAccess.listImportable) and artwork is the artwork scan's -- three
/// separate things, found in different ways, each useful without the others.
///
/// The app cannot ship the ROMs: `kernal`, `basic` and `chargen` are
/// Commodore's and still in copyright, so a store build has to source them
/// from the user, as every other C64 emulator does.
///
/// Where a user legitimately gets them:
///   * dumped from a C64 they own;
///   * a licensed set -- Cloanto's C64 Forever ships them under licence;
///   * the ROM files already in a VICE installation they have.
///
/// This deliberately does NOT open a document picker. The files it wants have
/// fixed, well-known names, so making someone hunt through a file browser for
/// `chargen-901225-01.bin` is asking them to do work the app can do itself.
/// It looks everywhere it is allowed to look and takes what it recognises.
class RomInstallService {
  RomInstallService._();

  /// Human-readable guidance, kept next to the code that consumes it so the
  /// wording cannot drift from what the scan actually accepts.
  static const String guidance =
      'The C64 ROMs (kernal, basic, chargen) are Commodore copyright, so they '
      'are not included. Supply your own: dump them from a C64 you own, use a '
      'licensed set such as C64 Forever, or copy them from an existing VICE '
      'installation. Put them anywhere this app can see -- its own folder, or '
      'Downloads on desktop -- and Scan will find them. Include the 1541 DOS '
      'ROM too, or disk images fail with ?DEVICE NOT PRESENT. Games and '
      'artwork have their own scans.';

  /// A machine ROM is recognised by the names VICE itself uses. Matching on
  /// prefix rather than exact filenames because revisions vary by machine
  /// (kernal-901227-03, kernal-251104-04, ...).
  static const List<String> _machineRomPrefixes = [
    'kernal',
    'basic',
    'chargen',
  ];

  /// Drive ROMs all start `dos` in VICE's own DRIVES directory.
  static const String _driveRomPrefix = 'dos';

  /// Classifies one filename. Returns null if it is not something we install.
  ///
  /// Split out and kept pure so the routing rules can be tested without a
  /// filesystem -- getting a drive ROM into C64/ instead of DRIVES/ produces
  /// a failure (?DEVICE NOT PRESENT) a long way from its cause.
  static String? targetFor(String filename) {
    final name = p.basename(filename).toLowerCase();
    if (!name.endsWith('.bin')) return null;
    if (name.startsWith(_driveRomPrefix)) return 'DRIVES';
    if (_machineRomPrefixes.any(name.startsWith)) return 'C64';
    return null;
  }

  /// Scans for ROMs and SIDs and installs everything recognised.
  static Future<RomScanResult> scanAndImport() async {
    final romRoot = await ViceNativePaths.romDir();
    final targets = {
      'C64': Directory(p.join(romRoot, 'C64')),
      'DRIVES': Directory(p.join(romRoot, 'DRIVES')),
    };
    for (final dir in targets.values) {
      await dir.create(recursive: true);
    }

    var machineRoms = 0;
    var driveRoms = 0;

    for (final root in await mediaScanRoots()) {
      final List<FileSystemEntity> entries;
      try {
        entries = root.listSync(recursive: true, followLinks: false);
      } catch (_) {
        // An unreadable directory is skipped, not fatal: on desktop the scan
        // roots are user folders that may contain anything.
        continue;
      }

      for (final entry in entries) {
        if (entry is! File) continue;
        final target = targetFor(entry.path);
        if (target == null) continue;

        final destDir = targets[target]!;
        final destPath = p.join(destDir.path, p.basename(entry.path));
        // Already installed, or the scan has found the destination copy of a
        // file it installed a moment ago.
        if (p.equals(entry.path, destPath)) continue;
        if (File(destPath).existsSync()) continue;

        try {
          entry.copySync(destPath);
          switch (target) {
            case 'C64':
              machineRoms++;
            case 'DRIVES':
              driveRoms++;
          }
        } catch (_) {
          // Skip the file rather than abort the scan.
        }
      }
    }

    return RomScanResult(machineRoms: machineRoms, driveRoms: driveRoms);
  }
}
