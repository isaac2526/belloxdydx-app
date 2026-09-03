import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// ============================================================
/// NATIVE BRIDGE
///
/// The few things Flutter cannot do from Dart alone.
///
/// Every method here is a no-op on platforms that cannot honour it,
/// and each one reports honestly whether it took effect — nothing in
/// this file pretends. A caller that needs to tell a student "this
/// phone cannot block screenshots" gets a truthful answer from
/// [screenshotPolicy] rather than a silent success.
/// ============================================================

class ScreenshotPolicy {
  /// True when the platform can actually stop a capture, not merely
  /// notice one afterwards.
  final bool enforceable;

  /// What the app is currently set to.
  final bool allowed;

  /// What is doing the enforcing, for the settings screen to explain.
  final String mechanism;

  const ScreenshotPolicy({
    required this.enforceable,
    required this.allowed,
    required this.mechanism,
  });

  static const unsupported = ScreenshotPolicy(
    enforceable: false,
    allowed: true,
    mechanism: 'none',
  );
}

abstract final class NativeBridge {
  static const _channel = MethodChannel('belloxdydx/native');

  /// Android and iOS both answer on this channel. They answer
  /// DIFFERENTLY, on purpose: Android reports true from
  /// [setAllowScreenshots] because FLAG_SECURE really did take effect,
  /// and iOS reports false because no iOS API can refuse a screenshot
  /// and returning a success the platform did not deliver is how a
  /// settings toggle becomes a lie.
  static bool get _hasNative =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Fires when a student takes a screenshot on iOS. There is no way to
  /// stop the shot — only to know it happened, after the fact.
  static void onScreenshot(void Function() taken,
      {void Function(bool recording)? capturing}) {
    if (!_hasNative) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'screenshotTaken':
          taken();
        case 'screenCaptureChanged':
          capturing?.call(call.arguments == true);
      }
      return null;
    });
  }

  /// Remembers the theme for the NEXT cold start, so the window Android
  /// paints before Flutter has started already matches what the student
  /// chose. It cannot affect the current launch — the system reads the
  /// pre-launch window background from the manifest before any of our
  /// code runs — which is also why a first install is always light.
  static Future<void> rememberLaunchTheme(bool dark) async {
    if (!_hasNative) return;
    try {
      await _channel.invokeMethod<bool>(
        'setLaunchTheme',
        dark ? 'dark' : 'light',
      );
    } on PlatformException catch (e) {
      debugPrint('[native] launch theme not stored: ${e.code}');
    } on MissingPluginException {
      // An older build of the native side. Not worth a crash.
    }
  }

  /// Turns capture blocking on or off for this session AND remembers it,
  /// so the next launch is already correct before the backend has been
  /// asked again.
  static Future<bool> setAllowScreenshots(bool allow) async {
    if (!_hasNative) return false;
    try {
      return await _channel.invokeMethod<bool>('setAllowScreenshots', allow) ??
          false;
    } on PlatformException catch (e) {
      debugPrint('[native] screenshot policy not applied: ${e.code}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// What this device can actually do about screen capture.
  static Future<ScreenshotPolicy> screenshotPolicy() async {
    if (!_hasNative) return ScreenshotPolicy.unsupported;
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>(
        'screenshotPolicy',
      );
      if (r == null) return ScreenshotPolicy.unsupported;
      return ScreenshotPolicy(
        enforceable: r['enforceable'] == true,
        allowed: r['allowed'] == true,
        mechanism: r['mechanism']?.toString() ?? 'unknown',
      );
    } catch (_) {
      return ScreenshotPolicy.unsupported;
    }
  }
}
