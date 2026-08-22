import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:retro_c64/ffi/vice_native_paths.dart';

const Map<String, String> _openRomAssets = {
  'assets/vice/OPENROMS/kernal': 'kernal-901227-03.bin',
  'assets/vice/OPENROMS/basic': 'basic-901226-01.bin',
  'assets/vice/OPENROMS/chargen': 'chargen-901225-01.bin',
};

class DemoRomsService {
  static const String demoTitle = 'Retro-C64 Demo';
  static const String demoFileName = 'DEMO.PRG';
  static const String _demoAsset = 'assets/demo/demo.prg';
  static const String _backupSuffix = '.user-rom';

  Future<Directory> demoRomDir() async {
    final root = Platform.isIOS
        ? await ViceNativePaths.iosDocumentsDirPath()
        : await ViceNativePaths.mediaDirPath();
    return Directory('$root/FreeRomDemo');
  }

  Future<List<String>> demoFiles({Directory? from}) async {
    final dir = from ?? await demoRomDir();
    if (!dir.existsSync()) return const [];
    final names = <String>[];
    for (final e in dir.listSync(recursive: true)) {
      if (e is File) {
        names.add(e.path.substring(dir.path.length + 1));
      }
    }
    names.sort();
    return names;
  }

  Future<String> prepareDemoEnvironment({Directory? into}) async {
    final root = into ?? await demoRomDir();
    await install(root);

    if (root.existsSync()) {
      for (final f in root.listSync()) {
        if (f is File &&
            f.path.toLowerCase().endsWith('.prg') &&
            f.uri.pathSegments.last != demoFileName) {
          f.deleteSync();
        }
      }
    }

    final prg = File('${root.path}/$demoFileName');
    final data = await rootBundle.load(_demoAsset);
    await prg.writeAsBytes(data.buffer.asUint8List(), flush: true);

    for (final name in const [
      'README.txt',
      'COPYING',
      'COPYING.LESSER',
      'LICENSE.txt',
    ]) {
      final bytes = await rootBundle.load('assets/vice/OPENROMS/$name');
      await File('${root.path}/$name')
          .writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    }
    return prg.path;
  }

  Future<int> install(Directory viceDir) async {
    final target = Directory('${viceDir.path}/C64');
    await target.create(recursive: true);
    var n = 0;
    for (final entry in _openRomAssets.entries) {
      final data = await rootBundle.load(entry.key);
      final bytes = data.buffer.asUint8List();
      final file = File('${target.path}/${entry.value}');

      if (await file.exists() && !await _sameBytes(file, bytes)) {
        final backup = File('${file.path}$_backupSuffix');
        if (!await backup.exists()) await file.rename(backup.path);
      }

      await file.writeAsBytes(bytes, flush: true);
      n++;
    }
    return n;
  }

  Future<bool> hasUserRomBackup(Directory viceDir) async {
    for (final name in _openRomAssets.values) {
      if (await File('${viceDir.path}/C64/$name$_backupSuffix').exists()) {
        return true;
      }
    }
    return false;
  }

  Future<int> restoreUserRoms(Directory viceDir) async {
    var n = 0;
    for (final name in _openRomAssets.values) {
      final backup = File('${viceDir.path}/C64/$name$_backupSuffix');
      if (!await backup.exists()) continue;
      await backup.rename('${viceDir.path}/C64/$name');
      n++;
    }
    return n;
  }

  Future<bool> _sameBytes(File file, List<int> other) async {
    final there = await file.readAsBytes();
    if (there.length != other.length) return false;
    for (var i = 0; i < other.length; i++) {
      if (there[i] != other[i]) return false;
    }
    return true;
  }

  Future<bool> installed(Directory viceDir) async {
    final kernal = File('${viceDir.path}/C64/${_openRomAssets.values.first}');
    if (!await kernal.exists()) return false;
    final ours = (await rootBundle.load('assets/vice/OPENROMS/kernal'))
        .buffer
        .asUint8List();
    final there = await kernal.readAsBytes();
    if (there.length != ours.length) return false;
    for (var i = 0; i < ours.length; i++) {
      if (there[i] != ours[i]) return false;
    }
    return true;
  }

  Future<String> installDemoProgram(Directory mediaDir) async {
    await mediaDir.create(recursive: true);
    final file = File('${mediaDir.path}/$demoTitle.prg');
    final data = await rootBundle.load(_demoAsset);
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return file.path;
  }
}
