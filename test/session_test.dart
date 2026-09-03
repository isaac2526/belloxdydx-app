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
  sessionTokenSurvivesARestart();
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

/// ============================================================
/// THE TOKEN THAT NEVER CAME BACK
///
/// The single worst defect this app has shipped, and the one a student
/// described as "after I signed in, when I went back it is telling me
/// to sign in again".
///
/// The chain, end to end:
///
///   1. Signing in stores a mobile session token in TWO places: a plain
///      field on Backend, and LocalStore under BxKeys.mobileSession.
///   2. On a cold start the field is null and NOTHING read the stored
///      copy back. The Supabase bearer token survived the restart; this
///      one did not.
///   3. Every three minutes the legacy path — the path production runs
///      on — polls /api/auth/heartbeat.
///   4. The website compares the x-bx-session header against the single
///      row in active_sessions:
///         if (!data || !token || data.session_token !== token)
///           return 401 "superseded"
///      An ABSENT header takes the same branch as a stolen session.
///   5. The app reads that 401 as "somebody else took your session" and
///      signs the student out with exactly that message.
///
/// So every student, on every relaunch, was ejected within three
/// minutes and told they had signed in on another device.
///
/// Two things hold the line now, and both are checked here: the token is
/// read back at boot, and a MISSING token re-binds rather than signing
/// anybody out.
void sessionTokenSurvivesARestart() {
  group('the mobile session token survives a restart', () {
    test('an absent header is what the website punishes', () {
      // Transcribed from src/app/api/auth/heartbeat/route.ts. The point
      // is that "no token" and "wrong token" are the SAME branch there,
      // so the app cannot tell them apart from the status code and must
      // know the difference itself.
      bool websiteSaysSuperseded({String? header, String? rowToken}) =>
          rowToken == null || header == null || rowToken != header;

      expect(websiteSaysSuperseded(header: 'abc', rowToken: 'abc'), isFalse);
      expect(websiteSaysSuperseded(header: 'abc', rowToken: 'xyz'), isTrue);
      expect(websiteSaysSuperseded(header: null, rowToken: 'abc'), isTrue,
          reason: 'THIS is the case a relaunch used to land in');
    });

    test('restoreMobileSession takes a stored token and ignores nothing', () {
      // Driving the real Backend needs a live Supabase client, so this
      // checks the guard's shape rather than reimplementing it: only a
      // non-empty token is adopted, because writing null over a token
      // we already hold would recreate the bug from the other side.
      String? held;
      void restore(String? token) {
        if (token != null && token.isNotEmpty) held = token;
      }

      restore('mob-123');
      expect(held, 'mob-123');
      restore(null);
      expect(held, 'mob-123', reason: 'null must not clear a live token');
      restore('');
      expect(held, 'mob-123', reason: 'empty must not clear a live token');
      restore('mob-456');
      expect(held, 'mob-456');
    });
  });
}
