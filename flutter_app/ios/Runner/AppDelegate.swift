import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configureAudioSession()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// The RemoteIO unit in native/vice_core/bridge/audio_backend_ios.c plays
  /// into whatever session the app has configured, and the default one
  /// (SoloAmbient) is silenced by the ring/silent switch -- which would read
  /// as "the emulator has no sound" on a phone that happens to be on silent.
  /// SID audio is the point of half this app, so ask for playback.
  ///
  /// Deliberately not fatal: if the session can't be configured the core
  /// still runs, and the picture is still worth having.
  private func configureAudioSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .default)
      try session.setActive(true)
    } catch {
      NSLog("VICE: could not configure audio session: \(error.localizedDescription)")
    }

    // A call or Siri deactivates the session and stops the emulator's output
    // unit. iOS restarts neither, so both halves have to be put back: the
    // session here, the unit in audio_backend_ios.c, which observes this same
    // notification. Registering first means this runs first, which is the
    // order those two steps have to happen in.
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioInterruption(_:)),
      name: AVAudioSession.interruptionNotification,
      object: session)
  }

  @objc private func handleAudioInterruption(_ notification: Notification) {
    guard
      let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      AVAudioSession.InterruptionType(rawValue: raw) == .ended
    else { return }
    do {
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      NSLog("VICE: could not reactivate audio session: \(error.localizedDescription)")
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
