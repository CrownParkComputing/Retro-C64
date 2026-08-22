import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:retro_c64/ffi/vice_native_paths.dart';
import 'storage_access.dart';
import 'zip_import.dart';

class RomRequirement {
  final String what;
  final String folder;
  final String why;

  const RomRequirement({
    required this.what,
    required this.folder,
    required this.why,
  });
}

class RomScanResult {
  final int machineRoms;
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

class RomInstallService {
  RomInstallService._();
  factory RomInstallService() => RomInstallService._();

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

  static const List<String> _machineRomPrefixes = [
    'kernal',
    'basic',
    'chargen',
  ];

  static const String _driveRomPrefix = 'dos';

  static const Set<String> _extensionlessRomNames = {
    'kernal', 'basic', 'chargen',
    'dos1541', 'dos1541ii', 'dos1571', 'dos1581', 'dos2031', 'dos1001',
  };

  String? targetFor(String filename) {
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

  Future<RomScanResult> scanAndImport() async {
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
        continue;
      }

      for (final entry in entries) {
        if (entry is! File) continue;

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
        }
      }
    }

    return RomScanResult(machineRoms: machineRoms, driveRoms: driveRoms);
  }
}
