// A StorageAccess that behaves like iOS's file-import strategy, so the
// tests can exercise that path on whatever machine the suite runs on
// (Platform.isIOS is false everywhere CI runs it).
import 'package:path/path.dart' as p;
import 'package:vice_multiplatform/services/storage_access.dart';

class FakeFileImportStorage extends StorageAccess {
  FakeFileImportStorage({required this.importDir, this.imported = const []});

  /// Stands in for the app's sandboxed Documents. Each subdir gets its own
  /// directory underneath, exactly as the real iOS strategy does -- the
  /// library and the scan's staging area must not be the same folder, or
  /// clearing one destroys the other.
  final String importDir;

  /// What [listImported] reports; the wizard uses it for its "N FILE(S)
  /// IMPORTED" line.
  List<ImportedFile> imported;

  /// Files [pickAndImportFiles] pretends the user picked. Empty models the
  /// case that mattered: a user with nothing to import yet.
  List<ImportedFile> pickResult = const [];

  int pickAndImportCalls = 0;

  @override
  StorageStrategyKind get kind => StorageStrategyKind.fileImport;

  @override
  Future<FolderPickResult?> pickFolder({required String dialogTitle}) =>
      throw UnsupportedError('file-import strategy has no folder picker');

  @override
  Future<List<ImportedFile>> scanFolder(String folderPath,
          {List<String> extensions = kGameFileExtensions}) =>
      throw UnsupportedError('file-import strategy has no folder scan');

  @override
  Future<List<ImportedFile>> pickAndImportFiles({
    required String destinationSubdir,
    List<String> extensions = kGameFileExtensions,
  }) async {
    pickAndImportCalls++;
    return pickResult;
  }

  @override
  Future<List<ImportedFile>> listImported(String destinationSubdir) async =>
      imported;

  @override
  Future<String?> importedDirectory(String destinationSubdir) async =>
      p.join(importDir, destinationSubdir);
}
