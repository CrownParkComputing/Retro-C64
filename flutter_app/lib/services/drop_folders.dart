// The drop folders: named, empty subfolders of the app's own Documents
// folder, created on request so the Files app shows somewhere obvious to put
// each kind of file.
//
// WHY THIS IS ONLY A CONVENIENCE. The scans do not need these folders. Both
// the ROM scan (RomInstallService.scanAndImport, over mediaScanRoots) and the
// game/SID scan (StorageAccess.listImportable) walk Documents RECURSIVELY, so
// a file dropped anywhere under it is found wherever it sits. What the folders
// fix is the other half: an empty folder tells the user what this app wants
// before they have dropped anything, which a flat empty folder cannot.
//
// The names are chosen to work WITH the pipeline rather than beside it:
//
//  - Games is the games destination itself (kGamesImportSubdir, 'games').
//    Apple's filesystem is case-insensitive, so creating 'Games' resolves to
//    the same directory the library already reads -- a game dropped there is
//    on the shelf without a scan at all.
//  - Music is a plain drop folder. .sid is in kGameFileExtensions, so tunes
//    left here are imported into the games folder, which is where the Music
//    tab looks for them.
//  - ROMs is a plain drop folder, swept by the recursive ROM scan.
import 'dart:io';

import 'package:path/path.dart' as p;

/// One drop folder: the directory name, and the note left inside it.
class DropFolder {
  final String name;
  final String readme;
  const DropFolder(this.name, this.readme);
}

class DropFolders {
  DropFolders._();

  /// The note's filename. Prefixed so it sorts above whatever the user adds.
  static const String readmeName = '_READ ME.txt';

  static const List<DropFolder> folders = [
    DropFolder(
      'ROMs',
      'Put the three Commodore ROM files here:\n'
          '  kernal   basic   chargen\n'
          'and, for disk images to work, the 1541 drive ROM:\n'
          '  dos1541\n\n'
          'VICE part numbers are fine (kernal-901227-03.bin), and so is no '
          'extension at all. A zip is fine too -- leave it as it is and the '
          'scan looks inside it.\n\n'
          'These are Commodore copyright and are not shipped with the app. '
          'Supply your own: dump them from a C64 you own, use a licensed set '
          'such as C64 Forever, or copy them from an existing VICE install.\n\n'
          'Then open Paths & Setup in the app and tap "Scan for ROMs".\n',
    ),
    DropFolder(
      'Games',
      'Put game files here: .d64  .tap  .t64  .crt  .prg  .g64  .d81\n'
          'Zips are fine -- the scan looks inside them.\n\n'
          'This folder IS the app library, so anything you drop here shows up '
          'on the Games shelf without a scan. Everywhere else in the '
          'Retro-C64 folder works too; it just needs a scan first.\n',
    ),
    DropFolder(
      'Music',
      'Put .sid tunes here, loose or in a zip.\n\n'
          'Then open Paths & Setup in the app and tap "Scan", and they appear '
          'on the Music page alongside the tunes that ship with the app.\n',
    ),
  ];

  /// Creates any missing drop folder under [documentsPath] and writes its
  /// note. Returns the names of the folders that did not already exist.
  ///
  /// Existing folders are left alone and their notes are refreshed rather
  /// than duplicated, so this is safe to run again -- which it has to be:
  /// the button stays on the page after the first tap.
  static Future<List<String>> create(String documentsPath) async {
    final created = <String>[];
    for (final folder in folders) {
      final dir = Directory(p.join(documentsPath, folder.name));
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
        created.add(folder.name);
      }
      // Rewritten every time: the wording is part of the app, so an upgrade
      // should correct a note left by an older version.
      await File(p.join(dir.path, readmeName))
          .writeAsString(folder.readme, flush: true);
    }
    return created;
  }

  /// Which of the drop folders exist under [documentsPath] right now.
  static List<String> existing(String documentsPath) => [
        for (final folder in folders)
          if (Directory(p.join(documentsPath, folder.name)).existsSync())
            folder.name,
      ];
}
