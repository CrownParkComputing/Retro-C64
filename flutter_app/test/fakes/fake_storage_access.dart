// An in-memory StorageAccess, so screens that depend on storage can be
// tested without a picker, a device or a real directory.
//
// The setup wizard is the reason this exists: it is the first thing a new
// user sees and it was completely untested, because every path through it
// runs a native file picker or sweeps a real container.
import 'package:retro_c64/services/storage_access.dart';

class FakeStorageAccess extends StorageAccess {
  FakeStorageAccess({
    this.kind = StorageStrategyKind.fileImport,
    List<ImportedFile> importable = const [],
    List<ImportedFile> imported = const [],
    this.pickResult = const [],
    this.folderToPick,
    this.throwOnScan = false,
  })  : _importable = [...importable],
        _imported = [...imported];

  @override
  final StorageStrategyKind kind;

  final List<ImportedFile> _importable;
  final List<ImportedFile> _imported;

  /// What the picker "returns" when the user imports by hand.
  final List<ImportedFile> pickResult;
  final FolderPickResult? folderToPick;

  /// Makes the sweep blow up, to prove the wizard survives it.
  final bool throwOnScan;

  int importCalls = 0;

  /// Counted so a test can assert that the library was NOT searched. The
  /// setup wizard must not go looking before the user has said which kind of
  /// machine they want.
  int scanCalls = 0;
  int pickCalls = 0;

  List<ImportedFile> get imported => List.unmodifiable(_imported);

  @override
  Future<FolderPickResult?> pickFolder({required String dialogTitle}) async {
    pickCalls++;
    return folderToPick;
  }

  @override
  Future<List<ImportedFile>> scanFolder(String folderPath,
      {List<String> extensions = kGameFileExtensions}) async {
    scanCalls++;
    if (throwOnScan) throw StateError('scan failed');
    return List.unmodifiable(_imported);
  }

  @override
  Future<List<ImportedFile>> pickAndImportFiles({
    required String destinationSubdir,
    List<String> extensions = kGameFileExtensions,
  }) async {
    pickCalls++;
    _imported.addAll(pickResult);
    return pickResult;
  }

  @override
  Future<List<ImportedFile>> listImported(String destinationSubdir) async =>
      List.unmodifiable(_imported);

  @override
  Future<List<ImportedFile>> listImportable({
    required String destinationSubdir,
    List<String> extensions = kGameFileExtensions,
  }) async {
    if (throwOnScan) throw StateError('scan failed');
    return List.unmodifiable(_importable);
  }

  @override
  Future<List<ImportedFile>> importFiles(
    List<ImportedFile> files, {
    required String destinationSubdir,
  }) async {
    importCalls++;
    _imported.addAll(files);
    _importable.clear();
    return files;
  }

  @override
  Future<String?> importedDirPath(String destinationSubdir) async =>
      '/fake/$destinationSubdir';
}
