// Cross-platform storage-access abstraction backing the setup wizard.
//
// The three platforms this app targets have fundamentally different rules
// for what a foreground app is allowed to touch:
//
//   - Linux: a normal filesystem. Any directory the user's account can read
//     is fair game -- pick a path, scan it recursively.
//   - Android: SAF (Storage Access Framework, same mechanism the original
//     SetupWizardActivity.java used via ACTION_OPEN_DOCUMENT_TREE). The
//     `file_picker` package's `getDirectoryPath()` wraps SAF's tree picker
//     and returns a real, persisted, readable path on modern Android, so
//     the same "pick a folder, scan it" flow as Linux works here too --
//     no separate SAF plugin needed.
//   - iOS: sandboxed. There is no such thing as "pick an arbitrary folder
//     and keep reading from it later" -- UIDocumentPickerViewController
//     grants access to the picked items only within that picker session
//     (security-scoped, or for our purposes: read it now or lose it).
//     So iOS steps through `file_picker`'s multi-file *selection* mode and
//     copies each chosen file into the app's own sandboxed Documents
//     directory, where the app then has ordinary permanent access.
//
// The wizard and the rest of the app should only ever talk to
// [StorageAccess.instance] and the [ImportedFile] / [FolderPickResult]
// shapes below -- never branch on Platform.isX outside this file.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../ffi/vice_native_paths.dart';
import 'zip_import.dart';

/// Whether a given platform's storage strategy is "pick a folder and scan
/// it" (Linux/Android) or "pick individual files and import them"  (iOS).
enum StorageStrategyKind { folderScan, fileImport }

/// Result of a successful folder pick (Linux/Android strategy).
class FolderPickResult {
  final String path;
  const FolderPickResult(this.path);
}

/// A single file made available to the app, whether by direct filesystem
/// path (Linux/Android, still living wherever the user's folder is) or by
/// having been copied into the app sandbox (iOS).
class ImportedFile {
  final String displayName;
  final String path;

  /// Set when this entry lives inside the zip at [path] rather than being a
  /// file in its own right; [path] is then the archive and this is the member
  /// to pull out of it.
  ///
  /// Carried as a field rather than encoded into [path] so that nothing which
  /// treats [path] as a filesystem path can be handed something that is not
  /// one -- importing is the only step that knows how to open an archive.
  final String? zipEntry;

  const ImportedFile({
    required this.displayName,
    required this.path,
    this.zipEntry,
  });

  bool get isZipMember => zipEntry != null;
}

/// Extensions the wizard's games-folder step cares about, kept in one place
/// so the wizard and [StorageAccess] agree with `MediaEntry.filterForExtension`
/// in lib/data/media_entry.dart (disk/tape/cart/prg) plus 'sid' music files,
/// which workbench_screen.dart's `_scanTestLibrary` also special-cases.
const List<String> kGameFileExtensions = [
  'd64', 'd71', 'd81', 'g64', // disk
  'tap', 't64', // tape
  'crt', // cartridge
  'prg', 'p00', // program
  'sid', // music
];

/// Where C64 media most likely already is, per platform.
///
/// Downloads is where a file lands when you fetch a .d64 or .zip in a
/// browser, so it is the first place worth looking before asking anyone to
/// go picking folders.
///
/// iOS is absent on purpose and cannot be added: "On My iPad > Downloads"
/// belongs to the Files app, and an app sandbox cannot read it. Nor can the
/// picker be aimed there -- file_picker's iOS plugin ignores initialDirectory
/// for pickFiles. On iOS the user navigates to Downloads in the picker once,
/// and after that the files live in the app's own folder.
List<String> defaultMediaSearchPaths() {
  final home = Platform.environment['HOME'];
  if (Platform.isAndroid) {
    // The public Download directory, readable with MANAGE_EXTERNAL_STORAGE
    // (declared in AndroidManifest.xml). Both spellings exist in the wild --
    // /sdcard is a symlink on most devices but not guaranteed.
    return const [
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Downloads',
      '/sdcard/Download',
    ];
  }
  if (Platform.isLinux || Platform.isMacOS) {
    final xdg = Platform.environment['XDG_DOWNLOAD_DIR'];
    return [
      if (xdg != null && xdg.isNotEmpty) xdg,
      if (home != null && home.isNotEmpty) p.join(home, 'Downloads'),
    ];
  }
  if (Platform.isWindows) {
    final profile = Platform.environment['USERPROFILE'];
    return [
      if (profile != null && profile.isNotEmpty)
        p.join(profile, 'Downloads'),
    ];
  }
  return const [];
}

/// Every directory a scan should look in, in search order.
///
/// The app's own folder first: that is where files pushed over USB, dragged
/// into the app in the Files app, or opened in from elsewhere all land, and on
/// iOS it is the only readable location. Downloads follows on the platforms
/// whose sandbox permits it.
Future<List<Directory>> mediaScanRoots() async {
  final roots = <Directory>[];
  if (Platform.isIOS) {
    roots.add(Directory(await ViceNativePaths.iosDocumentsDirPath()));
  }
  for (final path in defaultMediaSearchPaths()) {
    final dir = Directory(path);
    if (dir.existsSync()) roots.add(dir);
  }
  return roots;
}

/// The first search path that actually exists, or null.
String? firstExistingMediaSearchPath() {
  for (final path in defaultMediaSearchPaths()) {
    if (Directory(path).existsSync()) return path;
  }
  return null;
}

abstract class StorageAccess {
  /// Settable so tests can drive the screens that depend on storage --
  /// chiefly the setup wizard, which is the first thing a new user sees and
  /// was completely untested because every path through it goes through a
  /// real picker or a real directory. App code should only read it.
  static StorageAccess instance = _createInstance();

  static StorageAccess _createInstance() {
    if (Platform.isIOS) return _IOSFileImportStorage();
    // Linux and Android (and anything else, e.g. dev runs on macOS/Windows)
    // fall back to the folder-scan strategy.
    return _FolderScanStorage();
  }

  /// Whether this platform's games/app folder steps present as a folder
  /// picker ([StorageStrategyKind.folderScan]) or a file importer
  /// ([StorageStrategyKind.fileImport]).
  StorageStrategyKind get kind;

  /// Folder-scan platforms only: open the native directory picker (GTK
  /// dialog on Linux, SAF tree picker on Android) and return the chosen
  /// path, or null if the user cancelled.
  Future<FolderPickResult?> pickFolder({required String dialogTitle});

  /// Folder-scan platforms only: recursively list files under [folderPath]
  /// whose extension is in [extensions] (case-insensitive, without the
  /// leading dot).
  Future<List<ImportedFile>> scanFolder(String folderPath,
      {List<String> extensions = kGameFileExtensions});

  /// File-import platforms only: open the native document/file picker
  /// (UIDocumentPickerViewController on iOS) restricted to [extensions],
  /// copy each chosen file into [destinationSubdir] under the app's
  /// sandboxed Documents directory, and return the copies. Returns an
  /// empty list if the user cancelled or picked nothing.
  Future<List<ImportedFile>> pickAndImportFiles({
    required String destinationSubdir,
    List<String> extensions = kGameFileExtensions,
  });

  /// File-import platforms only: list files already imported into
  /// [destinationSubdir] from a previous session, so the wizard/Paths
  /// screen can show "N files imported" without re-picking.
  Future<List<ImportedFile>> listImported(String destinationSubdir);

  /// File-import platforms only: game files sitting in the app's own
  /// container but not yet imported into [destinationSubdir].
  ///
  /// These arrive without the document picker ever being involved -- dragged
  /// into "Retro-C64" in the Files app, opened into the app from
  /// another app (which lands them in Documents/Inbox), or pushed over USB.
  /// The custom import sheet lists these so a user can bring them in without
  /// going through UIDocumentPickerViewController, which cannot see files
  /// that are already inside this sandbox.
  Future<List<ImportedFile>> listImportable({
    required String destinationSubdir,
    List<String> extensions = kGameFileExtensions,
  });

  /// File-import platforms only: MOVE [files] into [destinationSubdir],
  /// returning the copies that succeeded.
  ///
  /// The source is deleted once its copy is safely in place, so an imported
  /// game does not sit in the container twice and keep reoffering itself as
  /// importable. Sources always live inside this app's own sandbox; the
  /// user's file in Downloads or iCloud is out of reach and untouched.
  Future<List<ImportedFile>> importFiles(
    List<ImportedFile> files, {
    required String destinationSubdir,
  });

  /// Where imported files live, for the library scanner to read.
  ///
  /// Null on folder-scan platforms, which have a user-chosen games folder in
  /// AppPrefs instead. On iOS nothing ever writes that pref -- there is no
  /// folder to choose -- so without this the library scanned a dev-only
  /// fallback path and came up empty no matter how many files were imported.
  Future<String?> importedDirPath(String destinationSubdir);
}

/// Linux + Android: pick a real directory, scan it directly. `file_picker`'s
/// `getDirectoryPath()` uses a native GTK dialog on Linux and Android's SAF
/// tree picker under the hood, and on modern Android (API 30+, which is all
/// this app targets -- see android/app/build.gradle.kts minSdk) hands back
/// a filesystem path the app can read from directly via `dart:io`, so no
/// separate SAF/content-URI plumbing (e.g. `shared_storage`) was needed.
class _FolderScanStorage extends StorageAccess {
  @override
  StorageStrategyKind get kind => StorageStrategyKind.folderScan;

  @override
  Future<FolderPickResult?> pickFolder({required String dialogTitle}) async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: dialogTitle,
    );
    if (path == null) return null;
    return FolderPickResult(path);
  }

  @override
  Future<List<ImportedFile>> scanFolder(String folderPath,
      {List<String> extensions = kGameFileExtensions}) async {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return const [];
    final wanted = extensions.map((e) => e.toLowerCase()).toSet();
    final results = <ImportedFile>[];
    for (final entry in dir.listSync(recursive: true, followLinks: false)) {
      if (entry is! File) continue;
      final ext = p.extension(entry.path).replaceFirst('.', '').toLowerCase();
      if (!wanted.contains(ext)) continue;
      results.add(ImportedFile(
        displayName: p.basename(entry.path),
        path: entry.path,
      ));
    }
    return results;
  }

  @override
  Future<List<ImportedFile>> pickAndImportFiles({
    required String destinationSubdir,
    List<String> extensions = kGameFileExtensions,
  }) {
    throw UnsupportedError(
        'pickAndImportFiles is an iOS-only strategy; this platform uses pickFolder/scanFolder.');
  }

  @override
  Future<List<ImportedFile>> listImported(String destinationSubdir) async =>
      const [];

  /// Whatever is sitting in the platform's Downloads folder. Nothing is
  /// copied on these platforms -- files are read where they lie -- so this
  /// is purely "here is what I can already see".
  @override
  Future<List<ImportedFile>> listImportable({
    required String destinationSubdir,
    List<String> extensions = kGameFileExtensions,
  }) async {
    final root = firstExistingMediaSearchPath();
    if (root == null) return const [];
    return scanFolder(root, extensions: extensions);
  }

  @override
  Future<List<ImportedFile>> importFiles(
    List<ImportedFile> files, {
    required String destinationSubdir,
  }) {
    throw UnsupportedError(
        'importFiles is an iOS-only strategy; this platform reads files in place.');
  }

  @override
  Future<String?> importedDirPath(String destinationSubdir) async => null;
}

/// iOS: sandboxed, no persistent folder access. Steps through
/// UIDocumentPickerViewController (via file_picker's multi-select file
/// mode) and copies each picked file into the app's own Documents
/// directory, where it stays available across launches without needing a
/// security-scoped bookmark.
class _IOSFileImportStorage extends StorageAccess {
  @override
  StorageStrategyKind get kind => StorageStrategyKind.fileImport;

  @override
  Future<FolderPickResult?> pickFolder({required String dialogTitle}) {
    throw UnsupportedError(
        'pickFolder is a folder-scan-only strategy; iOS uses pickAndImportFiles.');
  }

  @override
  Future<List<ImportedFile>> scanFolder(String folderPath,
      {List<String> extensions = kGameFileExtensions}) {
    throw UnsupportedError(
        'scanFolder is a folder-scan-only strategy; iOS uses listImported.');
  }

  Future<Directory> _destinationDir(String destinationSubdir) async {
    // Not getApplicationDocumentsDirectory(): path_provider's Apple
    // implementation goes through package:objective_c, whose native asset
    // fails to load in the Linux-built iOS app (see docs/IOS_BUILD.md). This
    // resolves the same directory straight from the app container.
    final docsPath = await ViceNativePaths.iosDocumentsDirPath();
    final dir = Directory(p.join(docsPath, destinationSubdir));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  @override
  Future<List<ImportedFile>> pickAndImportFiles({
    required String destinationSubdir,
    List<String> extensions = kGameFileExtensions,
  }) async {
    // FileType.any, NOT FileType.custom with allowedExtensions.
    //
    // On iOS file_picker turns each extension into a UTI and hands those to
    // UIDocumentPickerViewController as the allowed content types. None of
    // these extensions is a registered system type -- d64, tap, t64, crt,
    // prg, p00, sid all resolve to dynamic UTIs that match nothing -- so the
    // picker greyed out every single file and there was no way to select
    // anything. Take everything and filter by extension ourselves instead.
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      // No initialDirectory: file_picker's iOS plugin only reads that
      // argument on its saveFile path, never on pickFiles, so setting it
      // here would be silently ignored. The picker opens wherever iOS last
      // left it, and the user navigates to Downloads themselves.
    );
    if (result == null || result.files.isEmpty) return const [];

    final wanted = extensions.map((e) => e.toLowerCase()).toSet();
    final destDir = await _destinationDir(destinationSubdir);
    final imported = <ImportedFile>[];
    for (final picked in result.files) {
      final ext =
          p.extension(picked.name).replaceFirst('.', '').toLowerCase();
      if (!wanted.contains(ext)) continue;
      final sourcePath = picked.path;
      if (sourcePath == null) continue; // web-only field, never null on iOS
      final source = File(sourcePath);
      if (!source.existsSync()) continue;
      final destPath = p.join(destDir.path, picked.name);
      try {
        source.copySync(destPath);
        imported.add(ImportedFile(displayName: picked.name, path: destPath));
        // Clear the staged copy. Note this is NOT the user's file: iOS hands
        // the picker's selection over as a copy in the app's tmp directory,
        // and the original in Downloads/iCloud is outside this sandbox and
        // cannot be touched from here. Removing the staging copy just stops
        // tmp growing by the size of every import.
        try {
          source.deleteSync();
        } catch (_) {}
      } catch (_) {
        // Leave this file out of the result rather than aborting the whole
        // import; the wizard reports how many succeeded.
      }
    }
    return imported;
  }

  @override
  Future<String?> importedDirPath(String destinationSubdir) async =>
      (await _destinationDir(destinationSubdir)).path;

  @override
  Future<List<ImportedFile>> listImported(String destinationSubdir) async {
    final dir = await _destinationDir(destinationSubdir);
    final results = <ImportedFile>[];
    for (final entry in dir.listSync(followLinks: false)) {
      if (entry is! File) continue;
      results.add(ImportedFile(
        displayName: p.basename(entry.path),
        path: entry.path,
      ));
    }
    return results;
  }

  @override
  Future<List<ImportedFile>> listImportable({
    required String destinationSubdir,
    List<String> extensions = kGameFileExtensions,
  }) async {
    final docsPath = await ViceNativePaths.iosDocumentsDirPath();
    final destDir = await _destinationDir(destinationSubdir);
    final wanted = extensions.map((e) => e.toLowerCase()).toSet();
    final alreadyImported = (await listImported(destinationSubdir))
        .map((f) => f.displayName.toLowerCase())
        .toSet();

    final results = <ImportedFile>[];
    final seen = <String>{};
    for (final entry
        in Directory(docsPath).listSync(recursive: true, followLinks: false)) {
      if (entry is! File) continue;
      // Skip anything already sitting in the destination -- those are
      // imported, not importable.
      if (p.isWithin(destDir.path, entry.path)) continue;

      // A game arrives as its own zip far more often than as a loose file.
      // Its members are offered individually, exactly as if they had been
      // unpacked here, and nothing is written until one is actually imported
      // -- listing must stay free of side effects.
      if (ZipImport.isZip(entry.path)) {
        for (final member in ZipImport.memberNames(entry)) {
          final name = p.basename(member);
          final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
          if (!wanted.contains(ext)) continue;
          if (alreadyImported.contains(name.toLowerCase())) continue;
          if (!seen.add(name.toLowerCase())) continue;
          results.add(ImportedFile(
            displayName: name,
            path: entry.path,
            zipEntry: member,
          ));
        }
        continue;
      }

      final ext = p.extension(entry.path).replaceFirst('.', '').toLowerCase();
      if (!wanted.contains(ext)) continue;
      final name = p.basename(entry.path);
      if (alreadyImported.contains(name.toLowerCase())) continue;
      if (!seen.add(name.toLowerCase())) continue;
      results.add(ImportedFile(displayName: name, path: entry.path));
    }
    results.sort((a, b) => a.displayName
        .toLowerCase()
        .compareTo(b.displayName.toLowerCase()));
    return results;
  }

  @override
  Future<List<ImportedFile>> importFiles(
    List<ImportedFile> files, {
    required String destinationSubdir,
  }) async {
    final destDir = await _destinationDir(destinationSubdir);
    final imported = <ImportedFile>[];
    for (final file in files) {
      final source = File(file.path);
      if (!source.existsSync()) continue;
      final destPath = p.join(destDir.path, file.displayName);
      if (p.equals(source.path, destPath)) continue;

      // Zip members are extracted, and the archive is deliberately left in
      // place: the user may have picked one game out of a collection, and
      // deleting it the way a loose source is deleted would take the rest
      // with it. Members already imported stop being offered anyway, so a
      // fully-imported archive quietly lists nothing.
      if (file.isZipMember) {
        if (ZipImport.extractMember(source, file.zipEntry!, destPath)) {
          imported.add(
              ImportedFile(displayName: file.displayName, path: destPath));
        }
        continue;
      }

      try {
        source.copySync(destPath);
        imported.add(
            ImportedFile(displayName: file.displayName, path: destPath));
        // Import moves rather than copies: the source is a loose file inside
        // this app's own container (dropped in via Files, opened in from
        // another app, pushed over USB), so leaving it behind means the same
        // game sits there twice and keeps reappearing as "importable".
        // Deleted only after the copy succeeded, and a failure to delete is
        // not fatal -- the file is safely imported either way.
        try {
          source.deleteSync();
        } catch (_) {}
      } catch (_) {
        // Same as pickAndImportFiles: skip the file rather than abort the
        // whole batch, and let the caller report the count that landed.
      }
    }
    return imported;
  }
}
