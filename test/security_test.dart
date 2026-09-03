import 'package:belloxdydx/core/native_bridge.dart';
import 'package:belloxdydx/core/security.dart';
import 'package:belloxdydx/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two rules here decide whether a security switch is real or theatre,
/// and both of them are about what happens when something is MISSING.
///
///   · A policy that cannot be read must not fall open. A settings row
///     that has not been created yet, a field the backend sent as a
///     string instead of a number, a payload from an older server —
///     none of those may quietly unblock screenshots on every phone.
///
///   · A device check that cannot reach the server must fall OPEN. It
///     is a guard against a shared password, not a gate on the app the
///     student paid for, and a network blip must never lock them out.
void main() {
  group('the backend policy', () {
    test('blocks screenshots unless told otherwise', () {
      // Every shape a missing or malformed answer can take.
      for (final json in <Map<String, dynamic>>[
        {},
        {'allowScreenshots': null},
        {'allowScreenshots': 'true'},
        {'allowScreenshots': 1},
        {'allowScreenshots': 'yes'},
      ]) {
        expect(AppPolicy.fromJson(json).allowScreenshots, isFalse,
            reason: 'a policy that cannot be read must not open the bank: $json');
      }
      expect(AppPolicy.fromJson({'allowScreenshots': true}).allowScreenshots,
          isTrue);
    });

    test('a brand new install starts closed', () {
      const fresh = AppPolicy();
      expect(fresh.allowScreenshots, isFalse);
      expect(fresh.deviceVerification, isTrue);
    });

    test('device checking stays on unless explicitly disabled', () {
      expect(AppPolicy.fromJson({}).deviceVerification, isTrue);
      expect(
          AppPolicy.fromJson({'deviceVerification': false}).deviceVerification,
          isFalse);
      // Anything that is not literally false leaves the guard up.
      expect(AppPolicy.fromJson({'deviceVerification': 'false'})
          .deviceVerification, isTrue);
    });

    test('the lock delay survives a string, a number and nonsense', () {
      expect(AppPolicy.fromJson({'lockMinutes': 10}).lockMinutes, 10);
      expect(AppPolicy.fromJson({'lockMinutes': '10'}).lockMinutes, 10);
      expect(AppPolicy.fromJson({'lock_minutes': 3}).lockMinutes, 3);
      expect(AppPolicy.fromJson({'lockMinutes': 'soon'}).lockMinutes, 5);
      expect(AppPolicy.fromJson({}).lockMinutes, 5);
    });

    test('the delay is clamped to something a person would choose', () {
      // Zero would lock a student out mid-sentence; a year would mean
      // no lock at all while claiming there was one.
      expect(AppPolicy.fromJson({'lockMinutes': 0}).lockMinutes, 1);
      expect(AppPolicy.fromJson({'lockMinutes': -5}).lockMinutes, 1);
      expect(AppPolicy.fromJson({'lockMinutes': 99999}).lockMinutes, 120);
      expect(const AppPolicy(lockMinutes: 7).lockAfter,
          const Duration(minutes: 7));
    });

    test('it round-trips, because it is cached with the content', () {
      const original = AppPolicy(
        allowScreenshots: true,
        deviceVerification: false,
        lockMinutes: 12,
      );
      final back = AppPolicy.fromJson(original.toJson());
      expect(back.allowScreenshots, isTrue);
      expect(back.deviceVerification, isFalse);
      expect(back.lockMinutes, 12);
    });
  });

  group('a phone the account has never been opened on', () {
    test('the very first device is never challenged', () {
      // There is nothing to compare it against, and challenging it
      // would only lock out the person who just paid.
      const first = DeviceStanding(known: false, trusted: true, total: 1);
      expect(first.mustVerify, isFalse);
    });

    test('a second, unproved phone is', () {
      const second = DeviceStanding(known: false, trusted: false, total: 2);
      expect(second.mustVerify, isTrue);
    });

    test('a phone that has already proved itself is not asked again', () {
      const known = DeviceStanding(known: true, trusted: true, total: 3);
      expect(known.mustVerify, isFalse);
    });

    test('a check we could not make lets the student in', () {
      // The one that matters most. This is a guard against a shared
      // password, not a gate on the app they paid for: a dropped
      // connection here must never be the thing that keeps them out.
      expect(DeviceStanding.unknown.mustVerify, isFalse);
      expect(DeviceStanding.unknown.indeterminate, isTrue);

      const alsoUnreachable = DeviceStanding(
        known: false,
        trusted: false,
        total: 9,
        indeterminate: true,
      );
      expect(alsoUnreachable.mustVerify, isFalse);
    });
  });

  group('what the platform admits it cannot do', () {
    test('an unsupported platform claims nothing', () {
      const p = ScreenshotPolicy.unsupported;
      expect(p.enforceable, isFalse);
      expect(p.mechanism, 'none');
    });

    test('enforceable and allowed are separate questions', () {
      // "Tutor Bello turned blocking on" and "this phone can block" are
      // different facts, and Profile has to be able to say so — an
      // iPhone reports the first as true and the second as false.
      const iphone = ScreenshotPolicy(
        enforceable: false,
        allowed: false,
        mechanism: 'capture-detection',
      );
      expect(iphone.enforceable, isFalse);
      expect(iphone.allowed, isFalse);

      const android = ScreenshotPolicy(
        enforceable: true,
        allowed: false,
        mechanism: 'FLAG_SECURE',
      );
      expect(android.enforceable, isTrue);
    });
  });
}
