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

  /// The first pass, right after an account is created or signed into.
  /// Same gate, different words: the student is being shown what will
  /// guard the app from now on rather than being kept out of it.
  enrolling,

  /// This phone has no fingerprint, no face and no screen PIN, so
  /// there is nothing to lock with. Pretending otherwise would be a
  /// button labelled "Unlock" that anybody can press.
  unavailable,
}

class AppLockNotifier extends StateNotifier<BxLockState>
    with WidgetsBindingObserver {
  AppLockNotifier(this._store, {bool hasSession = false})
      : _hasSession = hasSession,
        super(_startState(_store, hasSession)) {
    WidgetsBinding.instance.addObserver(this);
    unawaited(_checkCapability());
  }

  /// What the app comes up as.
  ///
  /// It used to come up [BxLockState.open], always, and that one word
  /// was the whole reason the lock "did not work". Every timer, every
  /// idle count and every backgrounded-at stamp lived in RAM, so
  /// killing the app — which is what a phone under memory pressure does
  /// to a backgrounded app within minutes — reset all of it. The lock
  /// only ever guarded a session that was never interrupted, which is
  /// the one case that does not need guarding.
  ///
  /// Now the last moment of activity is on disk, and a launch that
  /// comes back to it late comes back to a lock screen. Five minutes is
  /// the floor used before the backend's real setting has arrived, so a
  /// relaunch straight after a kill does not nag; a launch the next
  /// morning does.
  static BxLockState _startState(LocalStore store, bool hasSession) {
    if (kIsWeb || !hasSession) return BxLockState.open;
    if (!store.getBool(BxKeys.biometricOn, fallback: true)) {
      return BxLockState.open;
    }
    final last = store.getInt(BxKeys.lockAfterMs);
    if (last <= 0) return BxLockState.locked;
    final away = DateTime.now().millisecondsSinceEpoch - last;
    return away >= const Duration(minutes: 5).inMilliseconds
        ? BxLockState.locked
        : BxLockState.open;
  }

  /// The cold-start decision on its own, so a test can pin it down
  /// without a platform channel in the way.
  @visibleForTesting
  static BxLockState startStateForTest(LocalStore store, bool hasSession) =>
      _startState(store, hasSession);

  final LocalAuthentication _auth = LocalAuthentication();
  final LocalStore _store;

  /// Whether there is a student behind the lock at all. A signed-out app
  /// has nothing to guard, and a lock screen over a login form is just a
  /// dead end with a fingerprint icon on it.
  bool _hasSession;
  set hasSession(bool v) {
    _hasSession = v;
    if (!v && state != BxLockState.unavailable) state = BxLockState.open;
  }

  AppPolicy _policy = const AppPolicy();
  bool _enabled = false;
  bool _capable = false;

  /// The last moment the student did something. A touch anywhere, a
  /// scroll, a keystroke. Restored from disk, because a lock that
  /// forgets is not a lock.
  late DateTime _lastActive = _restoreLastActive(_store);

  static DateTime _restoreLastActive(LocalStore store) {
    final ms = store.getInt(BxKeys.lockAfterMs);
    return ms > 0
        ? DateTime.fromMillisecondsSinceEpoch(ms)
        : DateTime.now();
  }

  /// When the app went to the background, or null while it is in front.
  DateTime? _backgroundedAt;

  Timer? _tick;
  DateTime _lastPersist = DateTime.fromMillisecondsSinceEpoch(0);

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
    if (!mounted) return;
    if (!_capable) {
      // Nothing on this phone can open a lock, so the app must not come
      // up behind one. This is the reason the cold-start lock above is
      // safe to be optimistic: it is corrected here, within a frame or
      // two, before the student can do anything about it.
      state = BxLockState.unavailable;
    } else if (!_enabled && state == BxLockState.locked) {
      state = BxLockState.open;
    }
    _restartTicker();
  }

  /// Whether this phone has ever proved it can open the lock.
  bool get isEnrolled => _store.getBool(BxKeys.lockEnrolled);

  /// Run once, straight after an account is created or signed into.
  ///
  /// "Force passkey" means this: the student is shown the gate on the
  /// way in, while they are still paying attention, rather than
  /// discovering it a week later at the worst moment. On a phone with a
  /// fingerprint, a face or a screen PIN, that is one touch. On a phone
  /// with none of those, there is nothing to force and pretending
  /// otherwise would be a lie — [isCapable] stays false and Profile
  /// says plainly what the phone is missing.
  Future<void> enrolNow() async {
    if (kIsWeb) return;
    if (!_capable) await _checkCapability();
    if (!_capable || !mounted) return;
    // Signing in is itself activity, so the clock starts here.
    _lastActive = DateTime.now();
    await _persist(force: true);
    if (isEnrolled) return;
    _enabled = true;
    await _store.setBool(BxKeys.biometricOn, true);
    if (!mounted) return;
    state = BxLockState.enrolling;
    _restartTicker();
  }

  /// Writes the moment of last activity where a killed app can find it.
  ///
  /// Throttled: this runs from the pointer handler, and a preferences
  /// write on every finger movement would be its own bug.
  Future<void> _persist({bool force = false}) async {
    final now = DateTime.now();
    if (!force && now.difference(_lastPersist) < const Duration(seconds: 30)) {
      return;
    }
    _lastPersist = now;
    try {
      await _store.setInt(
        BxKeys.lockAfterMs,
        _lastActive.millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  /// Turned on by default where the phone can honour it, and the
  /// student can turn it off in Profile — it is their phone.
  Future<void> setEnabled(bool on) async {
    _enabled = on && _capable;
    await _store.setBool(BxKeys.biometricOn, on);
    if (!_enabled &&
        (state == BxLockState.locked || state == BxLockState.enrolling)) {
      state = BxLockState.open;
    }
    _restartTicker();
  }

  /// Called from the root of the widget tree on any pointer or key
  /// event. This is what makes the lock respect a student who is
  /// actually working.
  void touch() {
    _lastActive = DateTime.now();
    unawaited(_persist());
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
    if (!_enabled || !_hasSession || state != BxLockState.open) return;
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
        // The last chance to write anything down. A phone reclaiming
        // memory kills a backgrounded app without another callback, and
        // whatever is only in RAM at this moment is gone.
        unawaited(_persist(force: true));
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
            _hasSession &&
            DateTime.now().difference(away) >= _policy.lockAfter) {
          if (state == BxLockState.open) state = BxLockState.locked;
        } else {
          _lastActive = DateTime.now();
          unawaited(_persist(force: true));
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Locks now — used by the "Lock now" action in Profile.
  void lock() {
    if (_capable && _enabled && _hasSession) state = BxLockState.locked;
  }

  /// Lets the student past the first-time gate without proving
  /// anything. The lock stays ON — this only means "not this second".
  /// A student whose sensor is wet must never be locked out of an app
  /// they have just paid for.
  void skipEnrolment() {
    if (state != BxLockState.enrolling) return;
    _lastActive = DateTime.now();
    unawaited(_persist(force: true));
    state = BxLockState.open;
  }

  /// Asks the phone. Returns true when the student got back in.
  Future<bool> unlock() async {
    if (state == BxLockState.asking) return false;
    final previous = state;
    final enrolling = previous == BxLockState.enrolling;
    state = BxLockState.asking;
    try {
      final ok = await _auth.authenticate(
        localizedReason: enrolling
            ? 'Set this as the key to Belloxdydx'
            : 'Unlock Belloxdydx',
        options: const AuthenticationOptions(
          // false lets the phone fall back to its PIN or pattern. A
          // student whose fingerprint sensor is wet must still be able
          // to get into the app they paid for.
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (ok) await _store.setBool(BxKeys.lockEnrolled, true);
      if (!mounted) return ok;
      if (ok) {
        _lastActive = DateTime.now();
        await _persist(force: true);
        state = BxLockState.open;
      } else {
        state = previous == BxLockState.asking ? BxLockState.locked : previous;
      }
      return ok;
    } catch (e) {
      debugPrint('[lock] authenticate failed: $e');
      if (mounted) {
        state = enrolling ? BxLockState.enrolling : BxLockState.locked;
      }
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
