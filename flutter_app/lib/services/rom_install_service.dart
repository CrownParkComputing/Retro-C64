import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../ffi/vice_native_paths.dart';

/// Installs the C64 ROM set the emulator needs, from files the user supplies.
///
/// The app cannot ship these. `kernal`, `basic` and `chargen` are Commodore's
/// ROMs and are still in copyright, so a store build has to ask for them --
/// which is the same thing every other C64 emulator on the App Store does.
///
/// Where a user legitimately gets them:
///   * dumped from a C64 they own;
///   * a licensed set -- Cloanto's C64 Forever ships them under licence;
///   * the ROM files already sitting in a VICE installation they have.
class RomInstallService {
  RomInstallService._();

  /// Human-readable guidance, kept next to the code that needs it so the
  /// wording cannot drift away from what the importer actually accepts.
  static const String guidance =
      'The C64 ROMs (kernal, basic, chargen) are Commodore copyright, so '
      'they are not included. Supply your own: dump them from a C64 you own, '
      'use a licensed set such as C64 Forever, or copy them from an existing '
      'VICE installation. Add the 1541 DOS ROM too, or disk images fail to '
      'load with ?DEVICE NOT PRESENT.';

  /// Opens the file picker and installs whatever ROM files come back.
  ///
  /// Returns how many were installed. Files are routed by name into the two
  /// directories VICE expects: anything starting `dos` is a drive ROM, the
  /// rest are machine ROMs.
  static Future<int> importRoms() async {
    // FileType.any for the same reason as the game importer: `.bin` is not a
    // registered iOS UTI, so a custom-extension filter greys out every file
    // and nothing can be selected at all.
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
    if (result == null || result.files.isEmpty) return 0;

    final romRoot = await ViceNativePaths.romDir();
    final c64Dir = Directory(p.join(romRoot, 'C64'));
    final drivesDir = Directory(p.join(romRoot, 'DRIVES'));
    await c64Dir.create(recursive: true);
    await drivesDir.create(recursive: true);

    var installed = 0;
    for (final picked in result.files) {
      final sourcePath = picked.path;
      if (sourcePath == null) continue;
      final source = File(sourcePath);
      if (!source.existsSync()) continue;

      final name = p.basename(picked.name);
      if (!name.toLowerCase().endsWith('.bin')) continue;

      final target = name.toLowerCase().startsWith('dos') ? drivesDir : c64Dir;
      try {
        source.copySync(p.join(target.path, name));
        installed++;
      } catch (_) {
        // Skip the file rather than abort the batch; the caller reports the
        // count that actually landed.
      }
    }
    return installed;
  }
}
