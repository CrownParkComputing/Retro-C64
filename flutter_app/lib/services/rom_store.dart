// The C64 ROMs, which the user supplies.
//
// The app used to ship Commodore's kernal/basic/chargen images inside its
// own bundle. They are third-party copyrighted code, and shipping them in a
// store build is the usual reason an emulator submission is rejected -- so
// the app now asks for them instead, exactly as VICE itself does on the
// desktop.
//
// VICE opens ROMs BY NAME out of its data directory (see C64_KERNAL_REV3_NAME
// and friends in the VICE source), so importing is not just a copy: each
// file has to land under the name VICE will look for. That mapping, and the
// question of whether enough of a set is present to boot at all, is what
// this class is for.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// One ROM the machine needs, and how to recognise it in whatever the user
/// hands over.
class RomSlot {
  /// The filename VICE will try to open.
  final String canonicalName;

  /// Subdirectory of the ROM root: 'C64' for machine ROMs, 'DRIVES' for
  /// the disk drive's.
  final String subdir;

  /// Lower-case filename prefix that identifies this ROM in a set the user
  /// supplies -- ROM sets in the wild keep VICE's own names, so this
  /// matches "kernal-901227-03.bin" as readily as "kernal.bin".
  final String namePrefix;

  /// Exact size in bytes. A "kernal" that isn't 8K is not a kernal, and
  /// silently installing it would produce a machine that boots to garbage.
  final int sizeBytes;

  /// Whether the machine refuses to start without it.
  final bool required;

  final String description;

  const RomSlot({
    required this.canonicalName,
    required this.subdir,
    required this.namePrefix,
    required this.sizeBytes,
    required this.required,
    required this.description,
  });
}

/// What a ROM import will look at. `.bin` is what the images themselves
/// are; `.zip` because ROM sets are essentially always distributed as one.
const List<String> kRomFileExtensions = ['bin', 'rom', 'zip'];

class RomStore {
  RomStore._();

  /// The three the C64 cannot boot without, plus the 1541 ROM -- without
  /// which the machine still boots, but every D64 fails to load with
  /// ?DEVICE NOT PRESENT, which reads as "the app is broken".
  static const List<RomSlot> slots = [
    RomSlot(
      canonicalName: 'kernal-901227-03.bin',
      subdir: 'C64',
      namePrefix: 'kernal',
      sizeBytes: 8192,
      required: true,
      description: 'KERNAL',
    ),
    RomSlot(
      canonicalName: 'basic-901226-01.bin',
      subdir: 'C64',
      namePrefix: 'basic',
      sizeBytes: 8192,
      required: true,
      description: 'BASIC',
    ),
    RomSlot(
      canonicalName: 'chargen-901225-01.bin',
      subdir: 'C64',
      namePrefix: 'chargen',
      sizeBytes: 4096,
      required: true,
      description: 'Character generator',
    ),
    RomSlot(
      canonicalName: 'dos1541-325302-01+901229-05.bin',
      subdir: 'DRIVES',
      namePrefix: 'dos1541',
      sizeBytes: 16384,
      required: false,
      description: '1541 disk drive (needed to load .d64 files)',
    ),
  ];

  /// The directory VICE is pointed at: it holds C64/ and DRIVES/.
  static Future<String> romRoot() async {
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'vice');
  }

  static String pathFor(String romRoot, RomSlot slot) =>
      p.join(romRoot, slot.subdir, slot.canonicalName);

  /// Slots with no file present, in the order they are listed above.
  static List<RomSlot> missing(String romRoot) => [
        for (final slot in slots)
          if (!File(pathFor(romRoot, slot)).existsSync()) slot,
      ];

  /// Whether the machine can start: every required ROM is present. The
  /// 1541 ROM being absent is a degraded library, not a dead emulator.
  static bool canBoot(String romRoot) =>
      missing(romRoot).every((slot) => !slot.required);

  static String describeMissing(String romRoot) {
    final gone = missing(romRoot);
    if (gone.isEmpty) return 'All ROMs installed.';
    return gone.map((s) => s.description).join(', ');
  }

  /// Installs whatever ROMs it recognises among [candidatePaths], copying
  /// each under the name VICE expects. Returns the slots that were filled.
  ///
  /// Unrecognised files are ignored rather than rejected: a ROM set
  /// routinely carries a dozen images for machines this app does not
  /// emulate, and refusing the lot because of them would be useless.
  static Future<List<RomSlot>> install(
    List<String> candidatePaths,
    String romRoot,
  ) async {
    final installed = <RomSlot>[];
    for (final slot in slots) {
      final match = _matchFor(slot, candidatePaths);
      if (match == null) continue;
      final target = File(pathFor(romRoot, slot));
      try {
        target.parent.createSync(recursive: true);
        File(match).copySync(target.path);
        installed.add(slot);
      } catch (_) {
        // One unreadable file costs that ROM, not the whole import.
      }
    }
    return installed;
  }

  static String? _matchFor(RomSlot slot, List<String> candidatePaths) {
    String? sizeOnlyFallback;
    for (final path in candidatePaths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final name = p.basename(path).toLowerCase();
      final int length;
      try {
        length = file.lengthSync();
      } catch (_) {
        continue;
      }
      if (length != slot.sizeBytes) continue;
      // Exact VICE name wins outright; a name that merely starts right is
      // the normal case ("kernal.bin", "kernal-901227-02.bin").
      if (name == slot.canonicalName.toLowerCase()) return path;
      if (name.startsWith(slot.namePrefix)) sizeOnlyFallback ??= path;
    }
    return sizeOnlyFallback;
  }
}
