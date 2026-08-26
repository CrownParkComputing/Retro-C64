// Shared-storage permission handling: all-files access, the Retro-Amiga way.
//
// The library is read in place from wherever the user keeps it -- often an
// SD card -- and Android 11+ will not let the app read a raw path there
// without the All-files-access grant. This app used to refuse the permission
// and copy files in through a SAF grant instead; the whole Retro-* family
// now asks for the permission (Retro-Amiga shipped this way and passed
// Play's sensitive-permission review), and the SAF grant remains as the
// fallback for anyone who declines.
import 'dart:io';

import 'package:flutter/services.dart';

class PermissionsService {
  PermissionsService._();

  static const MethodChannel _channel =
      MethodChannel('com.crownpark.retroc64/storage_permissions');

  /// Only Android gates raw-path reads this way.
  static bool get isRelevant => Platform.isAndroid;

  /// True if the app can currently read arbitrary files out of shared
  /// storage. Always true where the concept doesn't apply.
  static Future<bool> hasStorageAccess() async {
    if (!isRelevant) return true;
    try {
      return await _channel.invokeMethod<bool>('hasSharedStorageAccess') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Asks for shared-storage access. On Android 11+ this opens the system
  /// "All files access" settings page for this app and waits for the user
  /// to come back. Returns whether access was granted.
  static Future<bool> requestStorageAccess() async {
    if (!isRelevant) return true;
    try {
      return await _channel
              .invokeMethod<bool>('requestSharedStorageAccess')
              .timeout(const Duration(seconds: 90)) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Check, ask if needed, re-check. The one call sites use.
  static Future<bool> ensure() async {
    if (await hasStorageAccess()) return true;
    return requestStorageAccess();
  }
}
