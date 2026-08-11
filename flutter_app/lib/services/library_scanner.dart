// Turning a folder on disk into the games library.
//
// Pulled out of workbench_screen.dart so the walk itself can be tested
// against a real temp directory with no Flutter binding, no core and no
// device. Two behaviours here have already been bugs and both are pinned by
// tests: the walk is RECURSIVE (games filed in per-publisher subfolders
// simply never appeared when it wasn't), and a file that lists but cannot
// be READ is counted, not listed -- Android 11+ scoped storage happily
// enumerates directories the app has no permission to open, and every one
// of those entries launched into a blank screen.
import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/category.dart';
import '../data/media_entry.dart';

/// The library as found on disk, plus what had to be skipped.
class LibraryScanResult {
  final List<MediaEntry> entries;

  /// Files that matched a supported extension but whose bytes could not be
  /// read. Surfaced as a banner with a way to fix it rather than hidden.
  final int unreadableCount;

  const LibraryScanResult({required this.entries, required this.unreadableCount});

  static const empty = LibraryScanResult(entries: [], unreadableCount: 0);
}

class LibraryScanner {
  LibraryScanner._();

  /// Every supported media file under [directoryPath], at any depth.
  /// A missing directory scans to nothing rather than throwing.
  static LibraryScanResult scan(String directoryPath) {
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) return LibraryScanResult.empty;

    final entries = <MediaEntry>[];
    int unreadable = 0;
    // followLinks: false so a symlink loop inside the games folder cannot
    // hang the scan.
    for (final f in dir.listSync(recursive: true, followLinks: false)) {
      if (f is! File) continue;
      final ext = p.extension(f.path).replaceFirst('.', '');
      if (ext.isEmpty) continue;
      final filter = MediaEntry.filterForExtension(ext);
      if (filter == MediaFormatFilter.none) continue;
      if (!isReadable(f)) {
        unreadable++;
        continue;
      }
      entries.add(MediaEntry(
        displayName: p.basename(f.path),
        path: f.path,
        mediaType: filter,
      ));
    }
    return LibraryScanResult(entries: entries, unreadableCount: unreadable);
  }

  /// True if the file's bytes can actually be read, not merely listed.
  /// A successful first-byte read is the cheapest honest proof.
  static bool isReadable(File f) {
    try {
      final handle = f.openSync();
      try {
        // A zero-byte file counts as unusable too: there is nothing for the
        // core to boot, so listing it would produce the same blank screen
        // the readability check exists to prevent.
        return handle.readSync(1).isNotEmpty;
      } finally {
        handle.closeSync();
      }
    } on FileSystemException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
