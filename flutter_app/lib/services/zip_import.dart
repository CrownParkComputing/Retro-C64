import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Reading media and ROMs out of zip archives.
///
/// Everything people download arrives zipped -- a ROM set is one archive, a
/// game is usually its own -- and until this existed the scans walked straight
/// past them and reported "nothing found" with the archive sitting right there
/// in Downloads. That reads as a broken scan rather than an unsupported format.
///
/// Kept separate from the two scans that use it because they want different
/// things: [RomInstallService] installs every ROM it recognises immediately,
/// while game media is listed first and copied only once the user picks it.
/// Both route names through their own existing rules, so a zip can never
/// import something a loose file could not.
class ZipImport {
  ZipImport._();

  /// Whether [path] looks like an archive worth opening.
  static bool isZip(String path) =>
      p.extension(path).toLowerCase() == '.zip';

  /// The names of the files inside [zip], ignoring directories.
  ///
  /// Returns an empty list rather than throwing: a truncated or password
  /// protected download is a file to skip, not a reason to abort a scan that
  /// may have found plenty of other things.
  static List<String> memberNames(File zip) {
    try {
      return ZipDecoder()
          .decodeBytes(zip.readAsBytesSync())
          .where((e) => e.isFile)
          .map((e) => e.name)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Writes the member named [member] of [zip] to [destPath].
  ///
  /// Returns false if the member is missing or unreadable. [destPath] is
  /// supplied by the caller and is never derived from the entry's own path --
  /// an archive can contain `../../something`, and honouring that would let a
  /// download write outside the directory it was imported into.
  static bool extractMember(File zip, String member, String destPath) {
    try {
      final archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
      for (final entry in archive) {
        if (!entry.isFile || entry.name != member) continue;
        final out = File(destPath);
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(entry.readBytes() ?? const []);
        return true;
      }
    } catch (_) {
      // Fall through to false: skip this one, keep the scan going.
    }
    return false;
  }

  /// Extracts every member [accept] returns a destination directory for,
  /// filing each under its own basename. Returns the destination directory of
  /// each file actually written, so callers can count what went where.
  ///
  /// Members are matched on their basename alone, because the routing rules
  /// this feeds are filename rules -- a ROM set zipped as `C64/kernal` and one
  /// zipped as `kernal` are the same download to the person who fetched it.
  static List<String> extractWhere(
    File zip,
    String? Function(String basename) accept,
  ) {
    final written = <String>[];
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
    } catch (_) {
      return written;
    }
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final name = p.basename(entry.name);
      final destDir = accept(name);
      if (destDir == null) continue;
      final destPath = p.join(destDir, name);
      if (File(destPath).existsSync()) continue;
      try {
        final out = File(destPath);
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(entry.readBytes() ?? const []);
        written.add(destDir);
      } catch (_) {
        // Skip the member rather than abort the archive.
      }
    }
    return written;
  }
}
