// Where the SID tunes are and which one to play.
//
// Extracted from MusicScreen because the workbench now starts music too: the
// backdrop plays a tune while you browse, so both screens need the same
// answer to "what is available and where". Two copies of a search path is how
// the Music tab and the workbench end up disagreeing about which tunes exist.
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:retro_c64/ffi/vice_native_paths.dart';
import 'package:retro_c64/screens/setup_wizard_screen.dart' show kGamesImportSubdir;
import 'package:retro_c64/services/service_locator.dart';
import 'app_prefs.dart';
import 'storage_access.dart';

class MusicLibrary {
  MusicLibrary._();

  /// (title, artist, filename). The tunes are NOT bundled -- these are
  /// commercial compositions whose composers hold the rights -- so an entry
  /// resolves only if the user has that file. See pubspec.yaml.
  static const List<(String, String, String)> playlist = [
    ('Commando', 'Rob Hubbard', 'Commando.sid'),
    ('Arkanoid', 'Martin Galway', 'Arkanoid.sid'),
    ('Monty on the Run', 'Rob Hubbard', 'Monty_on_the_Run.sid'),
    ('Delta', 'Rob Hubbard', 'Delta.sid'),
    ('Sanxion', 'Rob Hubbard', 'Sanxion.sid'),
    ('Spellbound', 'Rob Hubbard', 'Spellbound.sid'),
    ('International Karate', 'Rob Hubbard', 'International_Karate.sid'),
    ('Warhawk', 'Rob Hubbard', 'Warhawk.sid'),
    ('The Last V8', 'Rob Hubbard', 'Last_V8.sid'),
    ('Cybernoid II', 'Jeroen Tel', 'Cybernoid_II.sid'),
    ('Lightforce', 'Rob Hubbard', 'Lightforce.sid'),
    ('Thing on a Spring', 'Rob Hubbard', 'Thing_on_a_Spring.sid'),
    ('Crazy Comets', 'Rob Hubbard', 'Crazy_Comets.sid'),
    ('Zoids', 'Rob Hubbard', 'Zoids.sid'),
    ('Auf Wiedersehen Monty', 'Rob Hubbard', 'Auf_Wiedersehen_Monty.sid'),
    ('Nemesis the Warlock', 'Rob Hubbard', 'Nemesis_the_Warlock.sid'),
    ('Comic Bakery', 'Martin Galway', 'Comic_Bakery.sid'),
    ('Wizball', 'Martin Galway', 'Wizball.sid'),
    ('Parallax', 'Martin Galway', 'Parallax.sid'),
    ('Rambo: First Blood Part II', 'Martin Galway', 'Rambo_First_Blood_Part_II.sid'),
  ];

  /// Directories searched, in priority order: a curated `Music/` folder
  /// beside the games folder wins, then whatever the importer brought in
  /// (SIDs arrive through the same importer as games, so they land in the
  /// games directory and the Music tab has to look there), then the app's
  /// own SID folder.
  static Future<List<String>> searchDirs() async {
    final dirs = <String>[];
    final gamesFolder = await getIt<AppPrefs>().getGamesFolderPath();
    if (gamesFolder != null) {
      final candidate = p.join(p.dirname(gamesFolder), 'Music');
      if (Directory(candidate).existsSync()) dirs.add(candidate);
    }
    final importedDir =
        await getIt<StorageAccess>().importedDirPath(kGamesImportSubdir);
    if (importedDir != null && Directory(importedDir).existsSync()) {
      dirs.add(importedDir);
    }
    try {
      dirs.add(await ViceNativePaths.extractBundledSidDir());
    } catch (_) {
      // Nothing to fall back on; any user folder found above still works.
    }
    return dirs;
  }

  /// Absolute path of [filename] in the first directory that has it.
  static String? resolve(String filename, List<String> dirs) {
    for (final dir in dirs) {
      final path = p.join(dir, filename);
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  /// The first playlist entry the user actually has, or null.
  ///
  /// Order follows the playlist rather than the directory, so the tune that
  /// greets you is the same one every time instead of depending on how the
  /// filesystem happens to sort.
  static (String title, String path)? firstAvailable(List<String> dirs) {
    for (final (title, _, filename) in playlist) {
      final path = resolve(filename, dirs);
      if (path != null) return (title, path);
    }
    return null;
  }

  /// The playlist title whose filename matches [path], if any.
  static String? titleForPath(String path) {
    final name = p.basename(path);
    for (final (title, _, filename) in playlist) {
      if (filename == name) return title;
    }
    return null;
  }
}
