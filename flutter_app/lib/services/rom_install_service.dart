import 'dart:io';

import 'package:path/path.dart' as p;

import '../ffi/vice_native_paths.dart';
import 'storage_access.dart';
import 'zip_import.dart';

/// One line of "what you need to supply, and where it ends up".
class RomRequirement {
  /// The filenames, as the user will recognise them.
  final String what;

  /// Subfolder of the ROM directory the scan files them into. Shown because
  /// people who prefer to copy files in by hand need to know, and because
  /// the wrong folder is a silent failure.
  final String folder;

  final String why;

  const RomRequirement({
    required this.what,
    required this.folder,
    required this.why,
  });
}

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
      'These are Commodore copyright, so they are not included. Supply your '
      'own: dump them from a C64 you own, use a licensed set such as C64 '
      'Forever, or copy them from an existing VICE installation. Put them '
      'anywhere this app can see -- its own folder, or Downloads on desktop '
      '-- and Scan will find them and file them in the right place. A zip is '
      'fine: leave the download as it is and Scan will look inside it. Names '
      'may carry VICE part numbers (kernal-901227-03.bin) or no extension at '
      'all (kernal); both are recognised. Games and artwork have their own '
      'scans.';

  /// What the user has to supply, why, and where the scan puts it.
  ///
  /// A list rather than prose because the two groups fail in completely
  /// different ways and people need to see which one they are missing: with
  /// no machine ROMs nothing starts at all, while a missing drive ROM leaves
  /// a perfectly working C64 that cannot read a single .d64 -- and .d64 is
  /// most of the library.
  static const List<RomRequirement> requirements = [
    RomRequirement(
      what: 'kernal, basic, chargen',
      folder: 'C64',
      why: 'Required. Without these the emulator cannot boot at all.',
    ),
    RomRequirement(
      what: 'dos1541',
      folder: 'DRIVES',
      why: 'Required for disk images. Without it .d64 files fail with '
          '?DEVICE NOT PRESENT, even though everything else works.',
    ),
  ];

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

  /// Exact names VICE uses when its ROMs carry no extension at all. Older
  /// VICE installs -- and the ones most people already have -- ship
  /// `C64/kernal`, `C64/basic`, `DRIVES/dos1541` with no suffix; only since
  /// 3.5 are they `kernal-901227-03.bin` and friends.
  ///
  /// Requiring `.bin` therefore silently found nothing in exactly the place
  /// this service's own guidance tells people to look ("copy them from an
  /// existing VICE installation"). Extensionless files are accepted, but only
  /// on an EXACT name match: the scan walks Downloads recursively, and a
  /// prefix rule with no extension would happily import any stray file called
  /// `basicsomething`.
  static const Set<String> _extensionlessRomNames = {
    'kernal', 'basic', 'chargen',
    'dos1541', 'dos1541ii', 'dos1571', 'dos1581', 'dos2031', 'dos1001',
  };

  /// Classifies one filename. Returns null if it is not something we install.
  ///
  /// Split out and kept pure so the routing rules can be tested without a
  /// filesystem -- getting a drive ROM into C64/ instead of DRIVES/ produces
  /// a failure (?DEVICE NOT PRESENT) a long way from its cause.
  static String? targetFor(String filename) {
    final name = p.basename(filename).toLowerCase();
    if (p.extension(name).isEmpty) {
      if (!_extensionlessRomNames.contains(name)) return null;
      return name.startsWith(_driveRomPrefix) ? 'DRIVES' : 'C64';
    }
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

        // A ROM set is almost always downloaded as one archive. Its members
        // go through targetFor exactly as loose files do, so a zip cannot
        // install anything a loose file could not -- and a zip of the whole
        // VICE data directory files kernal and dos1541 correctly rather than
        // dumping both into one folder.
        if (ZipImport.isZip(entry.path)) {
          for (final dir in ZipImport.extractWhere(
            entry,
            (name) => switch (targetFor(name)) {
              'C64' => targets['C64']!.path,
              'DRIVES' => targets['DRIVES']!.path,
              _ => null,
            },
          )) {
            if (dir == targets['C64']!.path) {
              machineRoms++;
            } else {
              driveRoms++;
            }
          }
          continue;
        }

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
