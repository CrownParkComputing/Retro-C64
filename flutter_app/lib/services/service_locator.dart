import 'dart:io';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_c64/ffi/vice_core.dart';
import 'package:retro_c64/services/app_prefs.dart';
import 'package:retro_c64/services/demo_roms_service.dart';
import 'package:retro_c64/services/gamepad_service.dart';
import 'package:retro_c64/services/startup_import.dart';
import 'package:retro_c64/services/rom_install_service.dart';
import 'package:retro_c64/services/storage_access.dart';
import 'package:retro_c64/services/video_settings.dart';
import 'package:retro_c64/services/vsid_service.dart';

final getIt = GetIt.instance;

Future<void> setupServiceLocator({SharedPreferences? prefs}) async {
  final sharedPrefs = prefs ?? await SharedPreferences.getInstance();

  if (!GetIt.instance.isRegistered<AppPrefs>()) {
    GetIt.instance.registerSingleton<AppPrefs>(SharedPrefsImpl(sharedPrefs));
  }
  if (!GetIt.instance.isRegistered<VsidService>()) {
    GetIt.instance.registerLazySingleton<VsidService>(() => VsidService());
  }
  if (!GetIt.instance.isRegistered<VideoSettings>()) {
    GetIt.instance.registerLazySingleton<VideoSettings>(() => VideoSettings());
  }
  if (!GetIt.instance.isRegistered<GamepadService>()) {
    GetIt.instance.registerLazySingleton<GamepadService>(() => GamepadService());
  }
  if (!GetIt.instance.isRegistered<DemoRomsService>()) {
    GetIt.instance.registerLazySingleton<DemoRomsService>(() => DemoRomsService());
  }
  if (!GetIt.instance.isRegistered<StartupImport>()) {
    GetIt.instance.registerLazySingleton<StartupImport>(() => StartupImport());
  }
  if (!GetIt.instance.isRegistered<RomInstallService>()) {
    GetIt.instance.registerLazySingleton<RomInstallService>(() => RomInstallService());
  }

  if (!GetIt.instance.isRegistered<StorageAccess>()) {
    GetIt.instance.registerLazySingleton<StorageAccess>(() {
      if (Platform.isIOS) return IOSFileImportStorage();
      if (Platform.isAndroid) return AndroidSafStorage();
      return FolderScanStorage();
    });
  }
}

void registerCore(ViceCore core) {
  if (GetIt.instance.isRegistered<ViceCore>()) {
    GetIt.instance.unregister<ViceCore>();
  }
  GetIt.instance.registerSingleton<ViceCore>(core);
}
