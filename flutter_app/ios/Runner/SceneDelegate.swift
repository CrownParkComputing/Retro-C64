import Flutter
import UIKit

/// Adopts the window the app delegate already built, instead of letting
/// Flutter migrate it or building a second one.
///
/// Background, because none of this is guessable from this file. On the Linux
/// build path (docs/IOS_BUILD.md) `iosbox` does not compile the
/// AppDelegate.swift next to this one -- it substitutes its own, which runs an
/// explicit `FlutterEngine(name: "main")` and creates the window itself:
///
///     self.window = UIWindow(frame: UIScreen.main.bounds)
///     self.window?.rootViewController = flutterVC
///     self.window?.makeKeyAndVisible()
///
/// That window is built before any scene exists, so it belongs to no
/// UIWindowScene. `FlutterSceneDelegate` tries to rescue exactly this case: on
/// scene connect it sees a rooted `appDelegate.window`, logs "WARNING - The
/// UIApplicationDelegate is setting up the UIWindow ... at launch" and calls
/// `moveRootViewControllerFrom:to:`, which makes a fresh scene window and
/// re-parents the FlutterViewController into it.
///
/// On iOS 18 that migration does not work. UIKit refuses the re-parent --
/// "Manually adding the rootViewController's view to the view hierarchy is no
/// longer supported" -- the controller is dragged through appearance
/// transitions without matching end calls ("Unbalanced calls to begin/end
/// appearance transitions"), and the FlutterView is left attached to nothing.
/// Dart runs, the emulator core starts, no error is printed anywhere, and the
/// screen is black. An empty subclass of FlutterSceneDelegate hits this, and so
/// does creating a second window here.
///
/// So do the migration properly instead: give the existing window to this
/// scene, take ownership of it, and clear `appDelegate.window` so Flutter's
/// legacy path sees nothing to rescue and skips straight to registering the
/// engine for scene life-cycle events.
class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    // Cast to the concrete class, not the UIApplicationDelegate protocol:
    // `window` on the protocol existential is immutable, and it has to be
    // cleared below. FlutterAppDelegate is a class, so a let binding of it
    // still allows the property write.
    if let windowScene = scene as? UIWindowScene,
       let appDelegate = UIApplication.shared.delegate as? FlutterAppDelegate,
       let existingWindow = appDelegate.window,
       existingWindow.rootViewController != nil {
      // Attaching the scene is the part the app delegate could not do: it ran
      // before any scene existed, so this window had none.
      existingWindow.windowScene = windowScene
      self.window = existingWindow

      // Hides it from FlutterSceneDelegate's migration guard, which fires on
      // `appDelegate.window.rootViewController` being non-nil. Ownership has
      // moved to this scene, so the app delegate should not still hold it.
      appDelegate.window = nil

      existingWindow.makeKeyAndVisible()
    } else if let windowScene = scene as? UIWindowScene {
      // Nothing built a window, so build one here.
      //
      // The branch above handles the Linux path, where `iosbox` substitutes an
      // AppDelegate that creates the window itself. The AppDelegate committed
      // next to this file does not: it only registers plugins on the implicit
      // engine. Normally a storyboard would instantiate the
      // FlutterViewController that brings that engine up, but this app has no
      // Main.storyboard on purpose (ibtool is macOS-only -- see
      // docs/IOS_BUILD.md), so on an Xcode build nothing ever created one.
      //
      // No FlutterViewController means no engine, which means Dart never runs:
      // the app launches, the scene connects, and the screen stays black with
      // no crash and nothing in the log. That is what an Xcode-built binary
      // did on the simulator, and the same code path runs on device.
      let engine = FlutterEngine(name: "main")
      engine.run()
      GeneratedPluginRegistrant.register(with: engine)

      let window = UIWindow(windowScene: windowScene)
      window.rootViewController = FlutterViewController(
        engine: engine, nibName: nil, bundle: nil)
      self.window = window
      window.makeKeyAndVisible()
    }

    // Still call super: it registers the engine for scene life-cycle events,
    // which is how plugins receive them. It finds the FlutterViewController
    // through `self.window.rootViewController`, which is now correctly set.
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }
}
