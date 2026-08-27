import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:retro_c64/ffi/vice_native_paths.dart';
import 'app_log.dart';
import 'service_locator.dart';
import 'rom_install_service.dart';
import 'storage_access.dart';
import 'zip_import.dart';

class StartupImport {
  StartupImport._();
  factory StartupImport() => StartupImport._();

  bool _isGenericName(String name) {
    final stem = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.')).toLowerCase()
        : name.toLowerCase();
    const generic = ['disk', 'side', 'game', 'program', 'boot', 'saves',
        'save', 'character', 'player', 'story', 'data', 'dungeon', 'questions'];
    return generic.any((g) =>
        stem == g || (stem.startsWith(g) && stem.length <= g.length + 14));
  }

  /// [includeMedia] files the music and games zips as well as the ROM one.
  /// Launch passes false: those two carry content the user is still
  /// arranging in the Files app, and filing them on every launch made the
  /// shelf populate itself out from under them. An explicit Scan asks for
  /// the lot.
  Future<({int roms, int tunes, int games})> run({
    bool includeMedia = true,
  }) async {
    var roms = 0;
    if (!await ViceNativePaths.romsInstalled()) {
      final scanned = await getIt<RomInstallService>().scanAndImport();
      roms = scanned.total;
      if (!scanned.isEmpty) AppLog.log('startup import: ${scanned.summary}');
    }

    var tunes = 0;
    var games = 0;
    if (!includeMedia) return (roms: roms, tunes: tunes, games: games);
    if (!Platform.isIOS) return (roms: roms, tunes: tunes, games: games);
    final String docsPath = await ViceNativePaths.iosDocumentsDirPath();

    final docs = Directory(docsPath);
    if (!docs.existsSync()) return (roms: roms, tunes: tunes, games: games);

    final sidRoot = await ViceNativePaths.sidDir();
    final gamesRoot = Directory(p.join(docsPath, 'games'));

    for (final entry in docs.listSync()) {
      if (entry is! File || !ZipImport.isZip(entry.path)) continue;
      final zipName = p.basenameWithoutExtension(entry.path);
      var owes = false;
      for (final member in ZipImport.memberNames(entry)) {
        var name = p.basename(member);
        final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
        if (_isGenericName(name)) {
          name = '$zipName - $name';
        }
        String? destPath;
        if (ext == 'sid') {
          destPath = p.join(sidRoot, name);
        } else if (kGameFileExtensions.contains(ext)) {
          destPath = p.join(gamesRoot.path, name);
        }
        if (destPath == null) {
          if (getIt<RomInstallService>().targetFor(name) != null) {
            owes = !await ViceNativePaths.romsInstalled();
          } else {
            owes = true;
          }
          continue;
        }
        if (File(destPath).existsSync()) continue;
        if (ZipImport.extractMember(entry, member, destPath)) {
          if (ext == 'sid') {
            tunes++;
          } else {
            games++;
          }
        } else {
          owes = true;
        }
      }
      if (!owes) {
        try {
          entry.deleteSync();
        } on FileSystemException {
        }
      }
    }

    if (tunes > 0 || games > 0) {
      AppLog.log('startup import: $tunes tune(s), $games game(s) from zips');
    }
    return (roms: roms, tunes: tunes, games: games);
  }
}
