import 'dart:io';

import 'package:path/path.dart' as p;

import '../ffi/vice_native_paths.dart';
import 'app_log.dart';
import 'rom_install_service.dart';
import 'storage_access.dart';
import 'zip_import.dart';

/// The three-zip startup contract: everything the emulator needs arrives as
/// zips dropped in the app's folder, and launching the app imports them.
///
///   1. A ROM zip - required. Without it the machine cannot start at all,
///      and the setup screen says so rather than pretending to search.
///   2. A music zip - every .sid inside goes to the tune library. Optional
///      but the workbench is better with it.
///   3. A games zip - the sample set, every recognised game format inside
///      goes to the games shelf.
///
/// Zips are routed by what is INSIDE them, not by their filename, so it does
/// not matter what a download ended up called. The Files app is the only road
/// files travel on iOS - the sandbox cannot see the system Downloads folder -
/// so "drop it in the app's folder" has to be the whole journey, with no
/// browse step and no import button.
///
/// Imports are idempotent: a file that already exists at its destination is
/// skipped, so the zips can stay in the folder as the user's own originals.
class StartupImport {
  StartupImport._();

  /// Whether a member name carries no identity of its own. These come from
  /// multi-disk releases, where the zip is the game and the members are just
  /// its sides.
  static bool _isGenericName(String name) {
    final stem = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.')).toLowerCase()
        : name.toLowerCase();
    const generic = ['disk', 'side', 'game', 'program', 'boot', 'saves',
        'save', 'character', 'player', 'story', 'data', 'dungeon', 'questions'];
    return generic.any((g) =>
        stem == g || (stem.startsWith(g) && stem.length <= g.length + 14));
  }

  /// What one launch imported, for the log and the setup screen.
  static Future<({int roms, int tunes, int games})> run() async {
    // ROMs first, and through the existing service: it already knows every
    // name VICE uses and files them where the core looks.
    var roms = 0;
    if (!await ViceNativePaths.romsInstalled()) {
      final scanned = await RomInstallService.scanAndImport();
      roms = scanned.total;
      if (!scanned.isEmpty) AppLog.log('startup import: ${scanned.summary}');
    }

    var tunes = 0;
    var games = 0;
    // The zip routing is the iOS journey; folder-scan platforms already read
    // media where it lies.
    if (!Platform.isIOS) return (roms: roms, tunes: tunes, games: games);
    final String docsPath = await ViceNativePaths.iosDocumentsDirPath();

    final docs = Directory(docsPath);
    if (!docs.existsSync()) return (roms: roms, tunes: tunes, games: games);

    final sidRoot = await ViceNativePaths.sidDir();
    final gamesRoot = Directory(p.join(docsPath, 'games'));

    for (final entry in docs.listSync()) {
      if (entry is! File || !ZipImport.isZip(entry.path)) continue;
      final zipName = p.basenameWithoutExtension(entry.path);
      for (final member in ZipImport.memberNames(entry)) {
        var name = p.basename(member);
        final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
        // Multi-disk games name their members Disk1, SideA, Game - names
        // that say nothing on a shelf and collide across zips, so the last
        // zip imported silently owned every "Disk1.d64". A generic member
        // takes its zip's name; a member that already names its game keeps
        // its own.
        if (_isGenericName(name)) {
          name = '$zipName - $name';
        }
        String? destPath;
        if (ext == 'sid') {
          destPath = p.join(sidRoot, name);
        } else if (kGameFileExtensions.contains(ext)) {
          destPath = p.join(gamesRoot.path, name);
        }
        if (destPath == null) continue; // ROM names were the service's job.
        if (File(destPath).existsSync()) continue; // already imported
        if (ZipImport.extractMember(entry, member, destPath)) {
          if (ext == 'sid') {
            tunes++;
          } else {
            games++;
          }
        }
      }
    }

    if (tunes > 0 || games > 0) {
      AppLog.log('startup import: $tunes tune(s), $games game(s) from zips');
    }
    return (roms: roms, tunes: tunes, games: games);
  }
}
