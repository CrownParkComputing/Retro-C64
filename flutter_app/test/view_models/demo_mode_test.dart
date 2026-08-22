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

  setUp(() {
    GetIt.instance.reset();
    setupServiceLocator();
  });

  test('normal mode offers every destination', () async {
    SharedPreferences.setMockInitialValues({'setup_completed': true});
    final vm = await settled(FakeViceCore(isRunning: false));
    expect(vm.demoMode, isFalse);
    expect(vm.visibleCategories, WorkbenchCategory.values);
  });

  test('free-ROM mode hides Games and Music', () async {
    SharedPreferences.setMockInitialValues({
      'setup_completed': true,
      'demo_rom_mode': true,
    });
    final vm = await settled(FakeViceCore(isRunning: false));

    expect(vm.demoMode, isTrue);
    expect(vm.visibleCategories, isNot(contains(WorkbenchCategory.games)));
    expect(vm.visibleCategories, isNot(contains(WorkbenchCategory.music)));
    // What is left has to be enough to run the demo, read what the mode
    // means, and get out.
    expect(vm.visibleCategories, contains(WorkbenchCategory.compliance));
    expect(vm.visibleCategories, contains(WorkbenchCategory.about));
    expect(vm.visibleCategories, contains(WorkbenchCategory.resume));
  });

  test('a hidden destination cannot stay selected', () async {
    SharedPreferences.setMockInitialValues({'setup_completed': true});
    final vm = await settled(FakeViceCore(isRunning: false));
    vm.setCategory(WorkbenchCategory.games);
    expect(vm.category, WorkbenchCategory.games);

    // Switching the mode on with Games selected would otherwise leave the
    // rail pointing at a destination it no longer lists.
    await AppPrefs.setDemoRomMode(true);
    await vm.refreshDemoMode();

    expect(vm.visibleCategories, contains(vm.category));
    expect(vm.category, WorkbenchCategory.compliance);
  });
}
