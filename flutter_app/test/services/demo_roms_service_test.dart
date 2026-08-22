import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_c64/ffi/vice_native_paths.dart';
import 'package:retro_c64/data/category.dart';
import 'package:retro_c64/services/demo_roms_service.dart';
import 'package:retro_c64/services/library_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  final service = DemoRomsService();

  setUp(() => temp = Directory.systemTemp.createTempSync('demoroms'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('installs the Open ROMs under the names the core actually opens', () async {
    expect(await service.install(temp), 3);

    final installed = Directory('${temp.path}/C64')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toSet();

    // The names are not cosmetic and this is not a tautology test. The core
    // is started without -kernal/-basic/-chargen, so VICE looks up its own
    // built-in resource defaults; a file called plain "kernal" is never
    // opened and the machine dies at
    // "Couldn't load kernal ROM `kernal-901227-03.bin'".
    expect(installed, containsAll(ViceNativePaths.requiredRomNames));
  });

  test('the ROMs it installs read as a usable set', () async {
    await service.install(temp);
    // The same check the app uses to decide whether it can boot at all. If
    // the demo ROMs did not satisfy it, a first run would still end at
    // "no ROMs found" -- which is the whole thing this feature removes.
    expect(
      ViceNativePaths.romsInstalledIn(Directory('${temp.path}/C64')),
      isTrue,
    );
  });

  test('reports demo ROMs as installed only when they are', () async {
    expect(await service.installed(temp), isFalse);
    await service.install(temp);
    expect(await service.installed(temp), isTrue);

    // Decided by content, not by a flag: importing a real kernal over the
    // top has to flip this back, or the app keeps using the .prg autostart
    // path that only suits the Open ROMs.
    final kernal = File('${temp.path}/C64/${ViceNativePaths.requiredRomNames.first}');
    final bytes = kernal.readAsBytesSync();
    bytes[0] = bytes[0] ^ 0xFF;
    kernal.writeAsBytesSync(bytes, flush: true);
    expect(await service.installed(temp), isFalse);
  });

  test('the installed demo is something the library scanner will list', () async {
    // The bug this pins: the demo was installed into the app's media
    // directory, which is a scan root on no platform, so it arrived
    // correctly and then never appeared in Games. The install location is
    // now libraryScanRoot(); what this checks is the other half -- that a
    // demo sitting in a scanned folder is recognised as playable media.
    await service.installDemoProgram(temp);
    final found = await LibraryScanner.scan(temp.path);
    expect(
      found.entries.map((e) => e.displayName),
      contains('${DemoRomsService.demoTitle}.prg'),
    );
    expect(found.entries.single.mediaType, MediaFormatFilter.prg);
  });

  test('moves the user\'s own ROMs aside instead of destroying them', () async {
    // The demo is now runnable at any time -- from Paths, or by re-running
    // setup -- not only on a first launch with an empty ROM directory. The
    // Open ROMs must occupy VICE's default filenames, which are the same
    // names a real dump occupies, so a plain overwrite would destroy a ROM
    // set the user may have no other copy of.
    final c64 = Directory('${temp.path}/C64')..createSync(recursive: true);
    final mine = File('${c64.path}/${ViceNativePaths.requiredRomNames.first}');
    final myBytes = List<int>.generate(8192, (i) => (i * 7) & 0xff);
    mine.writeAsBytesSync(myBytes);

    await service.install(temp);
    expect(await service.installed(temp), isTrue);
    expect(await service.hasUserRomBackup(temp), isTrue);

    final restored = await service.restoreUserRoms(temp);
    expect(restored, 1);
    expect(mine.readAsBytesSync(), myBytes, reason: 'the real ROM came back');
    expect(await service.installed(temp), isFalse);
  });

  test('running the demo twice does not overwrite the stored-away ROM', () async {
    final c64 = Directory('${temp.path}/C64')..createSync(recursive: true);
    final mine = File('${c64.path}/${ViceNativePaths.requiredRomNames.first}');
    final myBytes = List<int>.generate(8192, (i) => (i * 3) & 0xff);
    mine.writeAsBytesSync(myBytes);

    await service.install(temp);
    // A second run would otherwise back up the demo ROM over the real one,
    // and the user's set would be gone with no way back.
    await service.install(temp);

    await service.restoreUserRoms(temp);
    expect(mine.readAsBytesSync(), myBytes);
  });

  test('the demo environment is a separate world from the user\'s ROMs',
      () async {
    // The claim the compliance page makes is that running the demo cannot
    // affect a machine set up with real ROMs. That holds only while the demo
    // has its own ROM directory -- so this checks that preparing it writes a
    // complete, self-contained set somewhere, and that the somewhere is not
    // the directory the user's ROMs live in.
    final userRoms = Directory('${temp.path}/C64')
      ..createSync(recursive: true);
    final mine = File('${userRoms.path}/${ViceNativePaths.requiredRomNames.first}');
    final myBytes = List<int>.generate(8192, (i) => (i * 11) & 0xff);
    mine.writeAsBytesSync(myBytes);

    // A directory of its own, standing in for the visible one the app picks
    // on a device (resolving that needs a platform channel).
    final demoDir = Directory.systemTemp.createTempSync('demoworld');
    addTearDown(() => demoDir.deleteSync(recursive: true));
    expect(demoDir.path, isNot(equals(temp.path)));

    final prg = await service.prepareDemoEnvironment(into: demoDir);

    expect(File(prg).existsSync(), isTrue);
    expect(await service.installed(demoDir), isTrue,
        reason: 'the demo directory has a complete free ROM set');

    // The reviewer-facing promise: the files are listable and include the
    // licence texts, next to the ROMs they cover.
    final files = await service.demoFiles(from: demoDir);
    expect(files, contains('COPYING.LESSER'));
    // 8.3, upper case, no spaces. The emulated machine reads this name, not
    // the app: a LOAD of "Retro-C64 Demo.prg" failed with the wrong name on
    // screen, so the name the C64 sees is kept boring.
    expect(files, contains(DemoRomsService.demoFileName));
    expect(DemoRomsService.demoFileName, isNot(contains(' ')));
    expect(DemoRomsService.demoFileName,
        equals(DemoRomsService.demoFileName.toUpperCase()));

    // And the user's own ROM is exactly as it was.
    expect(mine.readAsBytesSync(), myBytes);
    expect(await service.hasUserRomBackup(temp), isFalse,
        reason: 'nothing of the user\'s was moved aside');
  });

  test('leaves exactly one demo program behind', () async {
    // The demo's filename has already changed once, and the old file simply
    // stayed put -- so the library listed two demos where there is one.
    final demoDir = Directory.systemTemp.createTempSync('demoworld');
    addTearDown(() => demoDir.deleteSync(recursive: true));
    File('${demoDir.path}/Retro-C64 Demo.prg').writeAsBytesSync([1, 2, 3]);

    await service.prepareDemoEnvironment(into: demoDir);

    final prgs = (await service.demoFiles(from: demoDir))
        .where((f) => f.toLowerCase().endsWith('.prg'))
        .toList();
    expect(prgs, [DemoRomsService.demoFileName]);
  });

  test('puts a demo program in the library for the user to pick', () async {
    final path = await service.installDemoProgram(temp);
    final file = File(path);
    expect(file.existsSync(), isTrue);
    expect(path, endsWith('.prg'));

    // A .prg starts with its little-endian load address. The demo is built
    // to load at $0801, where BASIC programs go, because autostart runs it
    // by typing RUN.
    final bytes = file.readAsBytesSync();
    expect(bytes.length, greaterThan(2));
    expect(bytes[0] | (bytes[1] << 8), 0x0801);
  });
}
