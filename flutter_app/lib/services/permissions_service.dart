// Shared-storage permission handling.
//
// There is none any more, and this file exists to say so in one place rather
// than leave every caller to work it out.
//
// The app used to ask for MANAGE_EXTERNAL_STORAGE ("All files access"), which
// is what let it read .d64/.t64/.tap/.prg out of a folder like
// /storage/emulated/0/Vice/Games - those are not images, video or audio, so
// READ_MEDIA_* never applied. Play treats that permission as sensitive:
// undeclared it blocks the release outright, and declared it means a review
// aimed at file managers, backup and antivirus apps, which an emulator is
// unlikely to pass and which every future update would then wait on.
//
// The folder is granted through the system picker instead - see
// _AndroidSafStorage - and nothing needs granting, so isRelevant is false and
// the screens that offered a trip to Settings stop offering it. Sending anyone
// to that toggle now would send them to a switch that grants a permission this
// app does not declare, which does nothing at all.

class PermissionsService {
  PermissionsService._();

  /// Whether anything here still needs granting. Nothing does. Kept as a
  /// getter so the screens that hid their permission rows behind it keep
  /// compiling and simply stop showing them.
  static bool get isRelevant => false;

  /// True if the app can currently read arbitrary files out of shared
  /// storage. Always true where the concept doesn't apply.
  static Future<bool> hasStorageAccess() async => true;

  /// Asks for shared-storage access. On Android 11+ this opens the system
  /// "All files access" settings page for this app; the returned value is
  /// the state as of when the call returns, so callers should re-check
  /// after the user comes back.
  /// Nothing to request: the host no longer implements this.
  static Future<bool> requestStorageAccess() async => true;
}
