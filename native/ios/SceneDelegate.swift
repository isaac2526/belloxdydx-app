import Flutter
import UIKit

// ============================================================
// WHAT AN IPHONE CAN AND CANNOT DO ABOUT A SCREENSHOT
//
// Android has FLAG_SECURE: the operating system refuses the capture and
// the screenshot comes out black. iOS has no equivalent, and any
// library claiming to "block screenshots on iOS" is claiming more than
// Apple gives it. There is no API to refuse a screenshot, full stop.
//
// What Apple DOES give, and what this file uses, both of it:
//
//   1. UIScreen.isCaptured — true while the screen is being RECORDED or
//      mirrored to AirPlay. A recording is the thing that actually
//      matters for a question bank: one recording carries a whole
//      session, where a screenshot carries one screen. While it is
//      true, the app's content is covered, so the recording captures a
//      brand plate instead of the questions.
//
//   2. userDidTakeScreenshotNotification — fires AFTER a still shot was
//      taken. It cannot be prevented, only noticed. Dart is told, and
//      the app reports it, which is what turns "we cannot stop you"
//      into "we know who did it".
//
// The admin panel says exactly this rather than implying the switch
// stops iPhones.
//
// ---- why this lives in the SCENE delegate -------------------
//
// It used to live in AppDelegate.swift and it never ran. The project
// declares UIApplicationSceneManifest, so the window belongs to the
// scene: the application delegate's `window` is nil, the guard that
// looked for a FlutterViewController on it never passed, and the method
// channel was never created on any iPhone. The lifecycle callbacks were
// wrong for the same reason — under scenes, applicationWillResignActive
// is not delivered; sceneWillResignActive is.
// ============================================================

class SceneDelegate: FlutterSceneDelegate {
  private var channel: FlutterMethodChannel?
  private var shield: UIView?
  private var allowCapture = false

  private static let channelName = "belloxdydx/native"
  private static let allowKey = "bx_allow_screenshots"

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    // Blocked unless the backend has said otherwise, and the last
    // answer is remembered so the very first frame after a cold start
    // already obeys it rather than waiting for a network call.
    allowCapture = UserDefaults.standard.object(forKey: Self.allowKey) as? Bool ?? false

    attachChannel()

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(captureStateChanged),
      name: UIScreen.capturedDidChangeNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenshotTaken),
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    // Tried again here on purpose: depending on how the window is
    // built, the root view controller may not be a FlutterViewController
    // yet when the scene connects. A channel that silently failed to
    // attach is exactly the bug this file exists to fix, so it is
    // retried rather than assumed.
    attachChannel()
    updateShield()
  }

  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    // The app switcher's thumbnail is a screenshot the system takes for
    // itself. Covering the window while the app leaves the foreground
    // keeps a question out of it.
    if !allowCapture { showShield() }
  }

  // MARK: - The channel

  private func attachChannel() {
    guard channel == nil else { return }
    guard let controller = window?.rootViewController as? FlutterViewController
    else { return }

    let ch = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: controller.binaryMessenger
    )
    channel = ch
    ch.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(FlutterMethodNotImplemented) }
      switch call.method {
      case "setAllowScreenshots":
        let allow = (call.arguments as? Bool) ?? false
        self.allowCapture = allow
        UserDefaults.standard.set(allow, forKey: Self.allowKey)
        DispatchQueue.main.async { self.updateShield() }
        // Reports FALSE on purpose. The Dart side asked us to enforce a
        // policy and we cannot enforce it here, so we say so rather than
        // returning a success the platform did not deliver.
        result(false)

      case "screenshotPolicy":
        result([
          "enforceable": false,
          "allowed": self.allowCapture,
          "mechanism": "capture-detection",
        ])

      // Android stores a launch theme; there is nothing to store here.
      case "setLaunchTheme":
        result(true)

      // Keeps a student's downloaded library out of their iCloud
      // backup. Everything under it can be fetched again, and Apple's
      // own guidance is explicit that re-downloadable content must not
      // be backed up — an app that fills somebody's iCloud quota with
      // four hundred megabytes of lecture slides gets rejected for it,
      // and deserves to be.
      case "excludeFromBackup":
        result(self.excludeFromBackup(call.arguments as? String))

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func excludeFromBackup(_ path: String?) -> Bool {
    guard let path, !path.isEmpty else { return false }
    var url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else { return false }
    do {
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try url.setResourceValues(values)
      return true
    } catch {
      return false
    }
  }

  // MARK: - Capture

  @objc private func captureStateChanged() {
    DispatchQueue.main.async { self.updateShield() }
    channel?.invokeMethod("screenCaptureChanged", arguments: UIScreen.main.isCaptured)
  }

  @objc private func screenshotTaken() {
    // After the fact is the only moment iOS offers.
    channel?.invokeMethod("screenshotTaken", arguments: nil)
  }

  private func updateShield() {
    if allowCapture || !UIScreen.main.isCaptured {
      hideShield()
    } else {
      showShield()
    }
  }

  private func showShield() {
    guard shield == nil, let window else { return }
    let cover = UIView(frame: window.bounds)
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cover.backgroundColor = UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1)

    let label = UILabel()
    label.text = "BELLOXDYDX"
    label.textAlignment = .center
    label.textColor = UIColor(red: 0.72, green: 0.55, blue: 0.16, alpha: 1)
    label.font = .systemFont(ofSize: 20, weight: .heavy)
    label.translatesAutoresizingMaskIntoConstraints = false
    cover.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
    ])

    window.addSubview(cover)
    shield = cover
  }

  private func hideShield() {
    shield?.removeFromSuperview()
    shield = nil
  }
}
