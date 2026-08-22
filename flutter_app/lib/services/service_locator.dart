import 'package:get_it/get_it.dart';
import '../ffi/vice_bindings.dart';
import '../ffi/vice_core.dart';
import 'gamepad_service.dart';
import 'video_settings.dart';
import 'vsid_service.dart';

final getIt = GetIt.instance;

void setupServiceLocator() {
  // We don't register AppPrefs here because it's a collection of static methods,
  // but if we refactor it to a class with an interface later, we will.

  // The emulator core. Initialized in main.dart or via the core loader.
  // We'll register it as a singleton once it's loaded.

  getIt.registerLazySingleton<VsidService>(() => VsidService.instance);
  getIt.registerLazySingleton<VideoSettings>(() => VideoSettings.instance);
  getIt.registerLazySingleton<GamepadService>(() => GamepadService());
}

/// Helper to register the core once it's loaded.
void registerCore(ViceCore core) {
  if (getIt.isRegistered<ViceCore>()) {
    getIt.unregister<ViceCore>();
  }
  getIt.registerSingleton<ViceCore>(core);
}
