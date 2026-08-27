import 'package:flutter/widgets.dart';
import 'dart:io';

/// The platform this build is actually running on.
///
/// The app is multiplatform, but any given copy of it is running on exactly
/// one OS, and saying which is more useful to the person holding it than
/// repeating "multiplatform" back at them. Used by the About tab's
/// "Running on:" line and by the workbench screensaver's scroller.
String platformName() {
  if (Platform.isAndroid) return 'Android';
  if (Platform.isIOS) return 'iOS';
  if (Platform.isLinux) return 'Linux';
  if (Platform.isMacOS) return 'macOS';
  if (Platform.isWindows) return 'Windows';
  return 'this platform';
}

/// What Apple calls this device inside the Files app.
///
/// The app's folder lives under "On My iPhone" on a phone and "On My iPad" on
/// a tablet, and instructions that name the wrong one send the user looking
/// for a heading that is not on their screen. The wizard and the Paths screen
/// both tell that story, and both used to say iPad on every device.
///
/// iPadOS reports itself as iOS and dart:io cannot tell the two apart, so the
/// idiom comes from the shortest side. 600dp is the conventional tablet
/// threshold and every iPhone, the Pro Max included, is comfortably under it.
String filesAppDeviceName(BuildContext context) {
  if (!Platform.isIOS) return 'this device';
  return isTabletSized(MediaQuery.of(context).size)
      ? 'On My iPad'
      : 'On My iPhone';
}

/// Split out from [filesAppDeviceName] so the threshold itself is testable:
/// `Platform.isIOS` is false under `flutter test`, which would otherwise make
/// the phone/tablet branch unreachable from a test.
bool isTabletSized(Size size) => size.shortestSide >= 600;
