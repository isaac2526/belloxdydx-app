import Flutter
import UIKit

// ============================================================
// THE APP DELEGATE
//
// Deliberately almost empty, and that is the fix.
//
// This file used to create the method channel, install the capture
// shield and listen for the app losing focus — and on a modern Flutter
// project NONE of it ran. The generated Xcode project declares
// UIApplicationSceneManifest in Info.plist, so the app runs under the
// UIScene lifecycle, and under that lifecycle:
//
//   · UIKit does not build the application delegate's window at all.
//     `window?.rootViewController as? FlutterViewController` was
//     therefore nil at didFinishLaunching, the `if let` never entered,
//     and the channel was NEVER CREATED. Every call from Dart —
//     setAllowScreenshots, screenshotPolicy, setLaunchTheme — landed on
//     nothing, on every iPhone.
//
//   · applicationWillResignActive and applicationDidBecomeActive are
//     not delivered. sceneWillResignActive and sceneDidBecomeActive
//     are. So the shield that keeps a question out of the app-switcher
//     thumbnail never went up either.
//
// All of that now lives in SceneDelegate.swift, where the window
// actually is. This file does the one job the application delegate
// still owns: registering the plugins with the implicit engine, exactly
// as `flutter create` writes it.
// ============================================================

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
