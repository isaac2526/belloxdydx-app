import 'dart:async';

import 'package:belloxdydx/core/providers.dart';
import 'package:belloxdydx/data/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The single-session watcher shipped broken and stopped every student
/// on the legacy path from finishing a login. The mechanism was small
/// enough to be invisible in review and total in effect, so it is worth
/// pinning down exactly.
///
/// `Stream.periodic` has nothing to emit unless it is given a
/// computation. For a nullable element type it can emit null and get
/// away with it; for a non-nullable one it throws from the constructor —
/// not at the first tick, which is what made it look like a timing
/// problem rather than a certainty.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  themeDefaults();

  group('Stream.periodic, the shape that broke login', () {
    test('a non-nullable stream with no computation throws immediately', () {
      expect(
        () => Stream<bool>.periodic(const Duration(minutes: 3)),
        throwsA(isA<ArgumentError>()),
        reason: 'this is the exact call that was in watchSession()',
      );
    });

    test('the shape the poll uses now constructs cleanly', () {
      expect(
        () => Stream<int>.periodic(const Duration(minutes: 3), (t) => t)
            .asyncMap((_) async => true),
        returnsNormally,
      );
    });

    test('it throws on construction, before anyone listens', () {
      // The distinction matters: a fault at first tick would have shown
      // up three minutes into a session, not on the login button.
      var constructed = false;
      try {
        Stream<bool>.periodic(const Duration(days: 1));
        constructed = true;
      } catch (_) {
        // expected
      }
      expect(constructed, isFalse);
    });
  });

  group('a failing watcher must not cost the session', () {
    // refreshProfile() used to attach the watcher inside the same try as
    // the profile read, so a fault in the watcher was reported to the
    // student as "your profile could not be read" and the session that
    // had just been established was discarded. This models both shapes.
    Future<String> oldShape() async {
      var state = 'signedOut';
      try {
        state = 'active';
        throw ArgumentError('watcher failed');
      } catch (_) {
        state = 'signedOut';
      }
      return state;
    }

    Future<String> newShape() async {
      var state = 'signedOut';
      try {
        // the profile read, and only the profile read
      } catch (_) {
        return 'signedOut';
      }
      state = 'active';
      try {
        throw ArgumentError('watcher failed');
      } catch (_) {
        // the watcher is best-effort; losing it costs the single-session
        // rule until the next launch, not the student's session
      }
      return state;
    }

    test('the old shape threw the session away', () async {
      expect(await oldShape(), 'signedOut');
    });

    test('the new shape keeps the student signed in', () async {
      expect(await newShape(), 'active');
    });
  });
}

/// A first install opens light, whatever the phone is set to. This is a
/// product decision, not a bug: Belloxdydx is white and gold, and the
/// first thing a student sees should be the product rather than their
/// own night setting. "System" stays available and is honoured the
/// moment it is chosen.
///
/// These drive the real ThemeNotifier against a real LocalStore. A test
/// that re-implemented the switch would pass forever while the app read
/// something else entirely.
void themeDefaults() {
  group('the theme a fresh install opens in', () {
    Future<ThemeNotifier> notifierWith(Map<String, Object> stored) async {
      SharedPreferences.setMockInitialValues(stored);
      LocalStore.resetForTest();
      final store = await LocalStore.init();
      return ThemeNotifier(store);
    }

    test('nothing stored means light, not system', () async {
      final n = await notifierWith({});
      expect(n.state, ThemeMode.light);
    });

    test('a stored choice is honoured exactly, including system', () async {
      expect((await notifierWith({BxKeys.themeMode: 'dark'})).state,
          ThemeMode.dark);
      expect((await notifierWith({BxKeys.themeMode: 'light'})).state,
          ThemeMode.light);
      expect((await notifierWith({BxKeys.themeMode: 'system'})).state,
          ThemeMode.system);
    });

    test('an unrecognised value falls back to light rather than crashing',
        () async {
      expect((await notifierWith({BxKeys.themeMode: 'midnight'})).state,
          ThemeMode.light);
    });

    test('choosing a theme persists it for the next launch', () async {
      final n = await notifierWith({});
      await n.set(ThemeMode.dark);
      expect(n.state, ThemeMode.dark);
      // A fresh notifier over the same store must come back dark.
      final store = LocalStore.instance;
      expect(ThemeNotifier(store).state, ThemeMode.dark);
    });
  });
}
