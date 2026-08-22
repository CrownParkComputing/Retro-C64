import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_c64/ffi/vice_native_paths.dart';
import 'package:retro_c64/data/category.dart';
import 'package:retro_c64/services/demo_roms_service.dart';
import 'package:retro_c64/services/library_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('demoroms'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('installs the Open ROMs under the names the core actually opens', () async {
    expect(await DemoRomsService.install(temp), 3);

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
    await DemoRomsService.install(temp);
    // The same check the app uses to decide whether it can boot at all. If
    // the demo ROMs did not satisfy it, a first run would still end at
    // "no ROMs found" -- which is the whole thing this feature removes.
    expect(
      ViceNativePaths.romsInstalledIn(Directory('${temp.path}/C64')),
      isTrue,
    );
  });

  test('reports demo ROMs as installed only when they are', () async {
    expect(await DemoRomsService.installed(temp), isFalse);
    await DemoRomsService.install(temp);
    expect(await DemoRomsService.installed(temp), isTrue);

    // Decided by content, not by a flag: importing a real kernal over the
    // top has to flip this back, or the app keeps using the .prg autostart
    // path that only suits the Open ROMs.
    final kernal = File('${temp.path}/C64/${ViceNativePaths.requiredRomNames.first}');
    final bytes = kernal.readAsBytesSync();
    bytes[0] = bytes[0] ^ 0xFF;
    kernal.writeAsBytesSync(bytes, flush: true);
    expect(await DemoRomsService.installed(temp), isFalse);
  });

  test('the installed demo is something the library scanner will list', () async {
    // The bug this pins: the demo was installed into the app's media
    // directory, which is a scan root on no platform, so it arrived
    // correctly and then never appeared in Games. The install location is
    // now libraryScanRoot(); what this checks is the other half -- that a
    // demo sitting in a scanned folder is recognised as playable media.
    await DemoRomsService.installDemoProgram(temp);
    final found = await LibraryScanner.scan(temp.path);
    expect(
      found.entries.map((e) => e.displayName),
      contains('${DemoRomsService.demoTitle}.prg'),
    );
    expect(found.entries.single.mediaType, MediaFormatFilter.prg);
  });

  test('puts a demo program in the library for the user to pick', () async {
    final path = await DemoRomsService.installDemoProgram(temp);
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
