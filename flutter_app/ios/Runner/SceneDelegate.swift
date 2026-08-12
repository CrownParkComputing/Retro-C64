import Flutter
import UIKit

/// Deliberately empty, and it must stay that way.
///
/// This class must NOT create a UIWindow. Doing so is what caused a black
/// screen with no error in any log, and the reason is worth writing down
/// because nothing about it is guessable from this file.
///
/// On the Linux build path (docs/IOS_BUILD.md) `iosbox` does not compile the
/// AppDelegate.swift sitting next to this file. It substitutes its own, which
/// runs an explicit `FlutterEngine(name: "main")` and creates the window
/// itself:
///
///     self.window = UIWindow(frame: UIScreen.main.bounds)
///     self.window?.rootViewController = flutterVC
///     self.window?.makeKeyAndVisible()
///
/// `FlutterSceneDelegate` then notices, at scene-connect time, that the app
/// delegate already owns a rooted window. It logs "WARNING - The
/// UIApplicationDelegate is setting up the UIWindow ... at launch" and calls
/// its `moveRootViewControllerFrom:to:` escape hatch, which builds a scene
/// window and re-parents the FlutterViewController into it. That migration is
/// the only window handling this app needs, and it works.
///
/// Add a window here and two compete: UIKit refuses the re-parent ("Manually
/// adding the rootViewController's view to the view hierarchy is no longer
/// supported"), the view controller is dragged through appearance transitions
/// without matching end calls ("Unbalanced calls to begin/end appearance
/// transitions"), and the FlutterView ends up attached to nothing. Dart runs,
/// the emulator core starts, no error is printed anywhere, and the screen is
/// black.
///
/// A previous comment here claimed `FlutterAppDelegate` creates the window at
/// launch. That is false for Flutter 3.41 -- `FlutterAppDelegate.mm` never
/// assigns `_window`. The window comes from iosbox's replacement, on this
/// build path only.
///
/// The stock Flutter 3.41 template is also an empty subclass, but it pairs
/// with `UISceneStoryboardFile` in Info.plist. We have no storyboard (ibtool
/// is macOS-only), so the app delegate's window is what stands in for it.
class SceneDelegate: FlutterSceneDelegate {
}
