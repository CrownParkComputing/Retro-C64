// Portrait layout guard: walks the whole workbench at every portrait size
// that matters and fails on any layout overflow.
//
// Written as a probe for one bug and kept as a test for the class of bug.
// What it caught: _Row's action button would not shrink, so Paths overflowed
// to the right on EVERY iPhone width (29px at 440pt, 149px at 320pt), and the
// Music blurb wrapped into a dozen lines beside its switch, pushing the
// playlist's Expanded below zero.
//
// The failure mode this defends against is nasty in release: there is no red
// error screen, the widget simply does not paint, and it reaches a tester as
// "white screen" -- see _logFrameworkErrors in main.dart.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:retro_c64/screens/workbench_screen.dart';
import 'package:retro_c64/view_models/workbench_view_model.dart';
import 'package:retro_c64/services/app_prefs.dart';
import 'package:retro_c64/services/service_locator.dart';

import '../fakes/fake_vice_core.dart';

/// Portrait geometries that matter, smallest first.
const _sizes = <String, Size>{
  'iPhone SE 320x568': Size(320, 568),
  'iPhone 13 mini 375x812': Size(375, 812),
  'iPhone 15 Pro 393x852': Size(393, 852),
  'iPhone 17 Pro Max 440x956': Size(440, 956),
  'iPad 11in 834x1210': Size(834, 1210),
};

const _destinations = ['Resume', 'Games', 'Music', 'Paths', 'Video', 'Input',
    'About', 'Compliance', 'History'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory games;
  final report = <String>[];

  setUp(() async {
    await GetIt.instance.reset();
    games = Directory.systemTemp.createTempSync('vice_portrait_probe');

    // Paths reads the ROM directory on open; without this the screen throws
    // MissingPluginException and the sweep stops before Video/Input/About.
    final support = Directory(p.join(games.path, 'support'))
      ..createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => support.path,
    );

    // About shows the app version via package_info_plus; unmocked, its
    // future fails AFTER the test body on slow layouts (the SE), arriving
    // once FlutterError.onError is restored - the binding then trips its
    // onError invariant and the run used to sit out its whole timeout.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      (call) async => <String, dynamic>{
        'appName': 'Retro-64',
        'packageName': 'com.crownparkcomputing.c64retro',
        'version': '1.0.0',
        'buildNumber': '46',
      },
    );

    File(p.join(games.path, 'Boulder Dash.d64')).writeAsStringSync('C64');
    SharedPreferences.setMockInitialValues({
      'setup_completed': true,
      'games_folder_path': games.path,
    });
  });

  tearDown(() => games.deleteSync(recursive: true));

  tearDownAll(() {
    stderr.writeln('\n==== PORTRAIT OVERFLOW REPORT ====');
    if (report.isEmpty) {
      stderr.writeln('no overflows');
    } else {
      for (final line in report) {
        stderr.writeln(line);
      }
    }
    stderr.writeln('==== END ====\n');
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump(const Duration(milliseconds: 16));
      }
    });
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Drains every exception the last pump recorded, tagged with [where].
  /// Reads the collector rather than takeException, which folds several
  /// errors into one opaque "Multiple exceptions (2)" wrapper.
  void drain(List<FlutterErrorDetails> collected, String where) {
    for (final d in collected) {
      // The creator chain names the widget and is the difference between
      // "something overflowed" and a place to look.
      final creator = d.informationCollector
              ?.call()
              .map((n) => n.toString())
              .firstWhere((line) => line.startsWith('debugCreator'),
                  orElse: () => '') ??
          '';
      report.add('$where\n    ${d.exception.toString().split('\n').first}'
          '${creator.isEmpty ? '' : '\n    $creator'}');
    }
    collected.clear();
  }

  for (final entry in _sizes.entries) {
    testWidgets('portrait ${entry.key}', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Collect rather than fail, so one bad screen does not hide the rest.
      final collected = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = collected.add;

      if (!GetIt.instance.isRegistered<AppPrefs>()) {
        await setupServiceLocator();
      }

      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => WorkbenchViewModel(core: FakeViceCore()),
          child: const WorkbenchScreen(),
        ),
      ));
      await settle(tester);
      drain(collected, '[${entry.key}] initial');

      for (final dest in _destinations) {
        final finder = find.text(dest);
        if (finder.evaluate().isEmpty) {
          report.add('[${entry.key}] $dest\n    NOT REACHABLE (no such label)');
          continue;
        }
        await tester.tap(finder.first, warnIfMissed: false);
        await settle(tester);
        drain(collected, '[${entry.key}] $dest');
      }


      // Tear the tree down while the collector is still ours, and give the
      // pipeline a beat: dispose-time errors then land in the report instead
      // of arriving after the test with no handler to route them - which is
      // what tripped the binding's onError invariant and hung the run for
      // its whole ten-minute timeout.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
      drain(collected, '[${entry.key}] teardown');
      FlutterError.onError = previousOnError;

      // The report is for the human reading the run; this is what keeps the
      // bug from coming back. Overflows only -- an unreachable label is a
      // note about this test's guesses, not a layout fault.
      final overflows =
          report.where((line) => line.contains('overflowed')).toList();
      expect(overflows, isEmpty,
          reason: 'layout overflow in portrait:\n${overflows.join("\n")}');
    });
  }
}
