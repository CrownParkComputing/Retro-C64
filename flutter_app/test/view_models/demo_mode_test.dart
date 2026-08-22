// Free-ROM mode is a different machine, not a setting.
//
// The rail must offer only what the mode can actually do. In free-ROM mode
// the user's media folder is not the one in use, so Games and Music would be
// doors onto an empty room -- and the workbench tune would try to load a
// file that is not there and look like a fault.
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_c64/data/category.dart';
import 'package:retro_c64/services/app_prefs.dart';
import 'package:retro_c64/services/service_locator.dart';
import 'package:retro_c64/view_models/workbench_view_model.dart';

import '../fakes/fake_vice_core.dart';

Future<WorkbenchViewModel> settled(FakeViceCore core) async {
  final vm = WorkbenchViewModel(core: core);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  return vm;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await GetIt.instance.reset();
  });

  test('normal mode offers every destination', () async {
    SharedPreferences.setMockInitialValues({'setup_completed': true});
    await setupServiceLocator();
    final vm = await settled(FakeViceCore(isRunning: false));
    expect(vm.demoMode, isFalse);
    expect(vm.visibleCategories, WorkbenchCategory.values);
  });

  test('free-ROM mode hides Music but keeps Games', () async {
    SharedPreferences.setMockInitialValues({
      'setup_completed': true,
      'demo_rom_mode': true,
    });
    await setupServiceLocator();
    final vm = await settled(FakeViceCore(isRunning: false));

    expect(vm.demoMode, isTrue);
    expect(vm.visibleCategories, isNot(contains(WorkbenchCategory.music)));
    // Games stays: the demo is opened from the library like any other file,
    // because nothing is auto-started on the user's behalf.
    expect(vm.visibleCategories, contains(WorkbenchCategory.games));
    // What is left has to be enough to run the demo, read what the mode
    // means, and get out.
    expect(vm.visibleCategories, contains(WorkbenchCategory.compliance));
    expect(vm.visibleCategories, contains(WorkbenchCategory.about));
    expect(vm.visibleCategories, contains(WorkbenchCategory.resume));
  });

  test('the library follows the mode, and a bad path does not hang it',
      () async {
    SharedPreferences.setMockInitialValues({
      'setup_completed': true,
      'demo_rom_mode': true,
    });
    await setupServiceLocator();
    final vm = await settled(FakeViceCore(isRunning: false));

    expect(vm.isLibraryLoading, isFalse,
        reason: 'a directory that cannot be resolved must not hang the scan');
    expect(vm.library, isEmpty);
  });

  test('compliance mode offers no saved sessions of the user\'s', () async {
    SharedPreferences.setMockInitialValues({
      'setup_completed': true,
      'demo_rom_mode': true,
    });
    await setupServiceLocator();
    final vm = await settled(FakeViceCore(isRunning: false));
    expect(vm.demoMode, isTrue);
    expect(await vm.savedSessions(), isEmpty);
  });

  test('a hidden destination cannot stay selected', () async {
    SharedPreferences.setMockInitialValues({'setup_completed': true});
    await setupServiceLocator();
    final vm = await settled(FakeViceCore(isRunning: false));
    vm.setCategory(WorkbenchCategory.music);
    expect(vm.category, WorkbenchCategory.music);

    // Switching the mode on with Music selected would otherwise leave the
    // rail pointing at a destination it no longer lists.
    await getIt<AppPrefs>().setDemoRomMode(true);
    await vm.refreshDemoMode();

    expect(vm.visibleCategories, contains(vm.category));
    expect(vm.category, WorkbenchCategory.compliance);
  });
}
