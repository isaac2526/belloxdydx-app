import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../data/local_store.dart';
import 'native_bridge.dart';

/// ============================================================
/// SECURITY
///
/// Three separate jobs that share one file because they share one
/// source of truth — a policy Tutor Bello sets from the admin panel and
/// every phone obeys on its next launch, with no new build.
///
///   1. **Screen capture.** Android's FLAG_SECURE, applied from the
///      backend switch. What that can and cannot do is documented on
///      [ScreenCapture] below, honestly, including the part where iOS
///      cannot be stopped.
///
///   2. **A phone this account has never used.** It must prove the
///      student holds the account's email before it opens.
///
///   3. **The inactivity lock.** The thing to get right here is what
///      "inactive" means. A plain timer that fires every five minutes
///      would interrupt a student in the middle of reading a note,
///      which is worse than useless — they would turn it off. This
///      counts time since the last TOUCH, and time spent in the
///      background. Reading, scrolling, typing and answering all keep
///      it awake; putting the phone down does not.
///
/// The lock is opened with the phone's own fingerprint, face or screen
/// PIN. Never the account password — the student proved that at sign-in
/// and asking again every few minutes teaches them to type it in public.
/// ============================================================

@immutable
class AppPolicy {
  final bool allowScreenshots;
  final bool deviceVerification;
  final int lockMinutes;

  const AppPolicy({
    this.allowScreenshots = false,
    this.deviceVerification = true,
    this.lockMinutes = 5,
  });

  Duration get lockAfter => Duration(minutes: lockMinutes.clamp(1, 120));

  factory AppPolicy.fromJson(Map<String, dynamic> j) {
    final raw = j['lockMinutes'] ?? j['lock_minutes'];
    final minutes = raw is num
        ? raw.toInt()
        : int.tryParse('${raw ?? ''}') ?? 5;
    return AppPolicy(
      // Blocked unless the backend explicitly says otherwise. A missing
      // or malformed setting must never open the question bank up.
      allowScreenshots:
          (j['allowScreenshots'] ?? j['allow_screenshots']) == true,
      deviceVerification:
          (j['deviceVerification'] ?? j['device_verification']) != false,
      lockMinutes: minutes.clamp(1, 120),
    );
  }

  Map<String, dynamic> toJson() => {
        'allowScreenshots': allowScreenshots,
        'deviceVerification': deviceVerification,
        'lockMinutes': lockMinutes,
      };
}

/// What this platform can actually do about a screenshot.
///
/// Written out because the alternative is a switch in an admin panel
/// that does nothing on half the phones and says nothing about it.
///
/// **Android** — `FLAG_SECURE` on the window. The operating system
/// itself refuses the capture: a screenshot comes out black, a screen
/// recording records black, and the app does not appear in the recent
/// apps thumbnail. It cannot be worked around from inside another app.
/// It can be added and removed at runtime, which is what lets a backend
/// switch take effect on the screen the student is already looking at.
/// A camera pointed at the screen still works — nothing can stop that.
///
/// **iOS** — there is no equivalent, and any library claiming otherwise
/// is claiming too much. Apple gives an app no way to refuse a
/// screenshot. What is available is `UIScreen.isCaptured` (a live
/// recording or AirPlay mirror is running, so the app can blank itself)
/// and `userDidTakeScreenshotNotification` (a shot was taken, after the
/// fact, so the app can report it). The app uses both, and the admin
/// panel says so rather than implying the switch stops iPhones.
///
/// **Web** — nothing. A browser cannot refuse a screenshot.
abstract final class ScreenCapture {
  static Future<void> apply(AppPolicy policy) async {
    await NativeBridge.setAllowScreenshots(policy.allowScreenshots);
  }

  static Future<ScreenshotPolicy> describe() => NativeBridge.screenshotPolicy();
}

// ------------------------------------------------------------
// The lock
// ------------------------------------------------------------

enum BxLockState {
  /// The app is open and usable.
  open,

  /// Waiting behind the lock screen.
  locked,

  /// The student is being asked for a fingerprint right now.
  asking,

  /// This phone has no fingerprint, no face and no screen PIN, so
  /// there is nothing to lock with. Pretending otherwise would be a
  /// button labelled "Unlock" that anybody can press.
  unavailable,
}

class AppLockNotifier extends StateNotifier<BxLockState>
    with WidgetsBindingObserver {
  AppLockNotifier(this._store) : super(BxLockState.open) {
    WidgetsBinding.instance.addObserver(this);
    unawaited(_checkCapability());
  }

  final LocalAuthentication _auth = LocalAuthentication();
  final LocalStore _store;

  AppPolicy _policy = const AppPolicy();
  bool _enabled = false;
  bool _capable = false;

  /// The last moment the student did something. A touch anywhere, a
  /// scroll, a keystroke.
  DateTime _lastActive = DateTime.now();

  /// When the app went to the background, or null while it is in front.
  DateTime? _backgroundedAt;

  Timer? _tick;

  set policy(AppPolicy p) {
    _policy = p;
    _restartTicker();
  }

  bool get isEnabled => _enabled;
  bool get isCapable => _capable;
  Duration get idleFor => DateTime.now().difference(_lastActive);

  Future<void> _checkCapability() async {
    if (kIsWeb) {
      _capable = false;
      state = BxLockState.unavailable;
      return;
    }
    try {
      // isDeviceSupported() is true when there is ANY screen lock —
      // fingerprint, face, PIN, pattern. That breadth is deliberate:
      // requiring a fingerprint specifically would shut out a student
      // whose phone has none, and a device PIN is still something an
      // account-sharer standing next to them does not have.
      _capable = await _auth.isDeviceSupported();
    } catch (e) {
      debugPrint('[lock] cannot query the device: $e');
      _capable = false;
    }
    _enabled = _capable && _store.getBool(BxKeys.biometricOn, fallback: true);
    if (!_capable && mounted) state = BxLockState.unavailable;
    _restartTicker();
  }

  /// Turned on by default where the phone can honour it, and the
  /// student can turn it off in Profile — it is their phone.
  Future<void> setEnabled(bool on) async {
    _enabled = on && _capable;
    await _store.setBool(BxKeys.biometricOn, on);
    if (!_enabled && state == BxLockState.locked) state = BxLockState.open;
    _restartTicker();
  }

  /// Called from the root of the widget tree on any pointer or key
  /// event. This is what makes the lock respect a student who is
  /// actually working.
  void touch() {
    _lastActive = DateTime.now();
  }

  void _restartTicker() {
    _tick?.cancel();
    if (!_enabled) return;
    // Checked once a minute rather than scheduled for a single instant,
    // so a phone that slept through the deadline still locks the moment
    // it wakes.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _evaluate());
  }

  void _evaluate() {
    if (!_enabled || state != BxLockState.open) return;
    if (idleFor >= _policy.lockAfter) state = BxLockState.locked;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) { // ignore: avoid_renaming_method_parameters
    // Named `lifecycle` rather than `state` on purpose: `state` is the
    // StateNotifier's own field, and shadowing it inside a method that
    // assigns to it is exactly the kind of thing that reads fine and
    // does the wrong thing.
    switch (lifecycle) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundedAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final away = _backgroundedAt;
        _backgroundedAt = null;
        if (!_enabled) {
          _lastActive = DateTime.now();
          return;
        }
        // Time spent in the background counts as idle time. Coming back
        // after a minute should not ask for a fingerprint; coming back
        // the next morning should.
        if (away != null &&
            DateTime.now().difference(away) >= _policy.lockAfter) {
          state = BxLockState.locked;
        } else {
          _lastActive = DateTime.now();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Locks now — used by the "Lock now" action in Profile.
  void lock() {
    if (_capable && _enabled) state = BxLockState.locked;
  }

  /// Asks the phone. Returns true when the student got back in.
  Future<bool> unlock() async {
    if (state == BxLockState.asking) return false;
    final previous = state;
    state = BxLockState.asking;
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock Belloxdydx',
        options: const AuthenticationOptions(
          // false lets the phone fall back to its PIN or pattern. A
          // student whose fingerprint sensor is wet must still be able
          // to get into the app they paid for.
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (!mounted) return ok;
      if (ok) {
        _lastActive = DateTime.now();
        state = BxLockState.open;
      } else {
        state = previous == BxLockState.asking ? BxLockState.locked : previous;
      }
      return ok;
    } catch (e) {
      debugPrint('[lock] authenticate failed: $e');
      if (mounted) state = BxLockState.locked;
      return false;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
