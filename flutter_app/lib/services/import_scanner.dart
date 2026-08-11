// Finding C64 media in a folder full of downloads.
//
// The picker-based import (StorageAccess.pickAndImportFiles) makes you name
// every file yourself, and it cannot see inside a .zip at all -- which is
// how nearly everything arrives from the internet. This walks a directory
// instead, looks inside any archive it finds, and reports every .d64/.t64/
// .sid/... it can reach, ready to be copied into the library in one go.
//
// Kept free of Flutter and of any picker so it can be tested against a real
// temp directory: the scan is the part with the rules in it.
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'storage_access.dart';

/// One importable thing the scan found: either a file on disk, or an entry
/// inside a zip that has to be extracted first.
class ImportCandidate {
  /// The name it will be imported under.
  final String name;

  /// The file on disk -- the media file itself, or the archive holding it.
  final String sourcePath;

  /// Path within [sourcePath] when it is an archive, otherwise null.
  final String? archiveEntry;

  /// Uncompressed size in bytes, for the "12 KB" line in the picker.
  final int sizeBytes;

  const ImportCandidate({
    required this.name,
    required this.sourcePath,
    required this.sizeBytes,
    this.archiveEntry,
  });

  bool get isInArchive => archiveEntry != null;

  /// What to show under the name: the archive it came out of, or the
  /// folder it sits in.
  String get sourceLabel => isInArchive
      ? 'in ${p.basename(sourcePath)}'
      : p.basename(p.dirname(sourcePath));

  /// Whether this is a tune rather than something to boot. Only used to
  /// tell the user which half of the app it will show up in.
  bool get isSid => p.extension(name).toLowerCase() == '.sid';
}

class ImportScanner {
  ImportScanner._();

  /// Archives worth opening. Only zip: .d64.gz and friends are rare enough
  /// that guessing at them would cost more than it returns.
  static const Set<String> _archiveExtensions = {'zip'};

  /// Where downloads land, per platform, or null where there is no such
  /// place the app may read (iOS, where the user picks a folder instead).
  static String? defaultDownloadsDirectory() {
    if (Platform.isAndroid) {
      for (final candidate in const [
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Downloads',
      ]) {
        if (Directory(candidate).existsSync()) return candidate;
      }
      return null;
    }
    if (Platform.isLinux || Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home == null) return null;
      final candidate = p.join(home, 'Downloads');
      return Directory(candidate).existsSync() ? candidate : null;
    }
    return null;
  }

  /// Every supported file under [directoryPath], at any depth, including
  /// the ones inside zips. Sorted by name so the list doesn't reshuffle
  /// between scans.
  ///
  /// A directory that doesn't exist scans to nothing rather than throwing,
  /// and one unreadable file or corrupt archive costs that file, not the
  /// scan.
  static Future<List<ImportCandidate>> scanDirectory(
    String directoryPath, {
    List<String> extensions = kGameFileExtensions,
  }) async {
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) return const [];
    final wanted = extensions.map((e) => e.toLowerCase()).toSet();
    final found = <ImportCandidate>[];

    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).replaceFirst('.', '').toLowerCase();
      if (wanted.contains(ext)) {
        found.add(ImportCandidate(
          name: p.basename(entity.path),
          sourcePath: entity.path,
          sizeBytes: _sizeOf(entity),
        ));
      } else if (_archiveExtensions.contains(ext)) {
        found.addAll(_scanArchive(entity, wanted));
      }
    }

    found.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return found;
  }

  /// The same scan over an explicit set of files -- what the iOS flow uses,
  /// where the user hands over files (zips included) rather than a folder.
  static Future<List<ImportCandidate>> scanFiles(
    List<String> filePaths, {
    List<String> extensions = kGameFileExtensions,
  }) async {
    final wanted = extensions.map((e) => e.toLowerCase()).toSet();
    final found = <ImportCandidate>[];
    for (final path in filePaths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
      if (wanted.contains(ext)) {
        found.add(ImportCandidate(
          name: p.basename(path),
          sourcePath: path,
          sizeBytes: _sizeOf(file),
        ));
      } else if (_archiveExtensions.contains(ext)) {
        found.addAll(_scanArchive(file, wanted));
      }
    }
    found.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return found;
  }

  static List<ImportCandidate> _scanArchive(File file, Set<String> wanted) {
    final found = <ImportCandidate>[];
    try {
      final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
      for (final entry in archive) {
        if (!entry.isFile) continue;
        final ext = p.extension(entry.name).replaceFirst('.', '').toLowerCase();
        if (!wanted.contains(ext)) continue;
        found.add(ImportCandidate(
          // Flattened: a zip's internal folders are the uploader's
          // business, not the library's.
          name: p.basename(entry.name),
          sourcePath: file.path,
          archiveEntry: entry.name,
          sizeBytes: entry.size,
        ));
      }
    } catch (_) {
      // Not a readable zip (truncated download, wrong extension). Skipping
      // it loses that archive, not the rest of the scan.
    }
    return found;
  }

  static int _sizeOf(File file) {
    try {
      return file.lengthSync();
    } catch (_) {
      return 0;
    }
  }

  /// Copies (or extracts) [candidates] into [destinationDir], and returns
  /// the ones that made it. Names already taken get a " (2)" suffix rather
  /// than overwriting a title the user already has.
  static Future<List<ImportedFile>> importAll(
    List<ImportCandidate> candidates,
    String destinationDir,
  ) async {
    final dir = Directory(destinationDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final imported = <ImportedFile>[];
    // One decode per archive however many entries are taken from it.
    final archives = <String, Archive>{};
    for (final candidate in candidates) {
      try {
        final target = _freePath(destinationDir, candidate.name);
        if (candidate.isInArchive) {
          final archive = archives[candidate.sourcePath] ??= ZipDecoder()
              .decodeBytes(File(candidate.sourcePath).readAsBytesSync());
          final entry = archive.files.firstWhere(
            (f) => f.name == candidate.archiveEntry,
            orElse: () => throw StateError('entry vanished'),
          );
          File(target).writeAsBytesSync(entry.content as List<int>);
        } else {
          File(candidate.sourcePath).copySync(target);
        }
        imported.add(
            ImportedFile(displayName: p.basename(target), path: target));
      } catch (_) {
        // Leave this one out of the result rather than abandoning the
        // whole import; the caller reports how many arrived.
      }
    }
    return imported;
  }

  static String _freePath(String dir, String name) {
    var candidate = p.join(dir, name);
    if (!File(candidate).existsSync()) return candidate;
    final stem = p.basenameWithoutExtension(name);
    final ext = p.extension(name);
    for (var i = 2; i < 1000; i++) {
      candidate = p.join(dir, '$stem ($i)$ext');
      if (!File(candidate).existsSync()) return candidate;
    }
    return candidate;
  }
}
