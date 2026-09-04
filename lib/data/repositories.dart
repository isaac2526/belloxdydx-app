import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import 'backend.dart';
import 'local_store.dart';
import '../core/security.dart';
import 'offline/offline_store.dart';
import 'models.dart';

/// ============================================================
/// REPOSITORIES
///
/// Each method has two implementations: a DIRECT one that talks to
/// Postgres through an RPC (no Vercel in the path), and a LEGACY one
/// that calls the website API exactly as the app does today.
///
/// The gateway decides which runs. Screens never know the difference.
/// ============================================================

// ============================================================
// AUTH
// ============================================================

class AuthRepository {
  AuthRepository(this._b, this._store);

  final Backend _b;
  final LocalStore _store;

  Profile? _cached;
  Profile? get cachedProfile => _cached;

  /// The student this phone was signed in as last time, read with no
  /// await at all so boot can show them their own app in the first
  /// frame instead of a splash screen.
  ///
  /// Returns null on a fresh install, after a sign-out, and after a
  /// sign-in that never completed — every case where showing somebody
  /// a dashboard would be a lie.
  Profile? rememberedProfile() {
    try {
      final raw = _store.readJsonSync(BxKeys.cachedProfile);
      if (raw == null) return null;
      final p = Profile.fromJson(raw);
      return p.id.isEmpty ? null : p;
    } catch (_) {
      return null;
    }
  }

  /// Seeds the in-memory profile from the remembered one, so the first
  /// screen and the first request agree about who is using the app.
  void adopt(Profile p) => _cached ??= p;

  String deviceId() {
    var id = _store.getString(BxKeys.deviceId);
    if (id == null || id.isEmpty) {
      final r = Random.secure();
      id = List.generate(32, (_) => '0123456789abcdef'[r.nextInt(16)]).join();
      _store.setString(BxKeys.deviceId, id);
    }
    return id;
  }

  Stream<AuthState> get authChanges => _b.auth.onAuthStateChange;

  /// Fires only when the auth client itself lets the session go — an
  /// expired or revoked refresh token — never for a network failure,
  /// which Supabase reports separately and retries.
  ///
  /// This is the ONE signal allowed to end a live session on its own.
  /// Everything else the app might read as "signed out" (a timeout, a
  /// 401 from a website route, an unreachable profile) is a guess, and
  /// acting on a guess is how a student on a bad line gets thrown back
  /// to the login screen mid-question.
  Stream<void> get sessionEnded => _b.auth.onAuthStateChange
      .where((s) => s.event == AuthChangeEvent.signedOut && s.session == null)
      .map((_) {});
  bool get signedIn => _b.signedIn;

  /// Accepts an email OR a username. A username is resolved to its email
  /// first — on the direct path by an RPC that returns only the email for
  /// a username that exists, on the legacy path by the website route.
  Future<String> _resolveEmail(String login) async {
    final trimmed = login.trim();
    if (trimmed.contains('@')) return trimmed.toLowerCase();
    try {
      if (_b.isDirect) {
        final r = await _b.rpc('bx_email_for_username',
            params: {'p_username': trimmed.toLowerCase()});
        final email = r['email']?.toString();
        if (email != null && email.isNotEmpty) return email;
      } else {
        final r = await _b.apiSend('/api/auth/resolve-username',
            body: {'username': trimmed.toLowerCase()});
        final email = r['email']?.toString();
        if (email != null && email.isNotEmpty) return email;
      }
    } catch (_) {
      // Fall through: let the sign-in attempt produce the real error.
    }
    return trimmed.toLowerCase();
  }

  Future<Profile> signIn(String login, String password) async {
    final email = await _resolveEmail(login);
    try {
      await _b.auth.signInWithPassword(email: email, password: password);
    } catch (e) {
      // Every failure here goes through the same door, auth and network
      // alike. Supabase reports a lost connection as an AuthException
      // whose message is the raw request — host, path and query — so a
      // branch that trusted the auth message printed the Supabase URL
      // to the student. classify() sorts transport before auth, and
      // nothing it returns carries text from the exception.
      throw _b.faultFor(e);
    }

    await _bindDevice();
    return loadProfile(force: true);
  }

  /// Binds this device to the account and opens the single live session.
  Future<void> _bindDevice() async {
    if (_b.isDirect) {
      final r = await _b.rpc('bx_bind_device', params: {
        'p_device_id': deviceId(),
        'p_platform': defaultTargetPlatform.name,
      });
      final err = r['error']?.toString();
      if (err == 'device_locked') {
        await _b.auth.signOut();
        throw const BxError(
          'This account is locked to a different device. Chat Tutor Bello '
          'for a device reset.',
          code: 'device_locked',
        );
      }
      if (err == 'account_frozen') {
        await _b.auth.signOut();
        throw BxError(
          r['reason']?.toString() ??
              'Your account is frozen. Chat Tutor Bello.',
          code: 'frozen',
        );
      }
    } else {
      final r = await _b.apiSend('/api/auth/login',
          body: {'deviceId': deviceId()});
      final token = r['mobileToken']?.toString();
      if (token != null) {
        _b.mobileSessionToken = token;
        await _store.setString(BxKeys.mobileSession, token);
      }
    }
  }

  Future<void> signUp({
    required String surname,
    required String firstName,
    required String email,
    required String phone,
    required String username,
    required String password,
    String matric = '',
    String referral = '',
  }) async {
    final body = {
      'surname': surname.trim(),
      'firstName': firstName.trim(),
      'matric': matric.trim(),
      'email': email.trim().toLowerCase(),
      'phone': phone.trim(),
      'username': username.trim().toLowerCase(),
      'password': password,
      'referral': referral.trim().toUpperCase(),
    };

    // Registration always goes through the website route: it creates the
    // auth user, the profile and the personal activation key in one
    // transaction using the service role key. That is correct — account
    // creation is exactly the kind of trust-critical write that should
    // stay server-side.
    try {
      await _b.apiSend('/api/auth/register', body: body);
    } on BxError catch (e) {
      throw BxError(_registerMessage(e.code) ?? e.message, code: e.code);
    }

    await _b.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    await _bindDevice();
    await loadProfile(force: true);
  }

  String? _registerMessage(String? code) => switch (code) {
        'username_taken' => 'That username was taken. Pick another.',
        'invalid_username' =>
          'Username: 3 to 20 small letters, numbers or underscore.',
        'email_taken' || 'email_exists' =>
          'An account already exists with this email. Try logging in.',
        'invalid_email' => 'That email address does not look right.',
        'invalid_phone' => 'Enter a valid phone number.',
        'invalid_password' || 'weak_password' =>
          'Password: at least 8 characters, letters plus 2 symbols.',
        'name_required' => 'Enter your surname and first name in full.',
        _ => null,
      };

  /// Live username availability, debounced by the caller.
  Future<bool> isUsernameFree(String username) async {
    final u = username.trim().toLowerCase();
    if (u.isEmpty) return false;
    try {
      if (_b.isDirect) {
        final r =
            await _b.rpc('bx_username_available', params: {'p_username': u});
        return r['available'] == true;
      }
      final r = await _b.apiGet('/api/auth/check-username?u=$u', retries: 0);
      return r['available'] == true;
    } catch (_) {
      return true; // never block the form on a flaky check
    }
  }

  /// Password recovery. Supabase sends the reset mail; the deep link
  /// returns the student to the app.
  Future<void> sendPasswordReset(String email) async {
    try {
      await _b.auth.resetPasswordForEmail(
        email.trim().toLowerCase(),
        redirectTo: 'belloxdydx://reset-password',
      );
    } catch (e) {
      throw _b.faultFor(e);
    }
  }

  Future<void> updatePassword(String newPassword) async {
    try {
      await _b.auth.updateUser(UserAttributes(password: newPassword));
    } catch (e) {
      throw _b.faultFor(e);
    }
  }

  // ------------------------------------------------------------
  // Devices
  // ------------------------------------------------------------

  /// Has this account been used from this phone before?
  ///
  /// The first device a student ever signs in from is trusted on sight.
  /// There is nothing to compare it against, and challenging it would
  /// only lock out the person who just paid. Every device after that
  /// arrives untrusted and is asked to prove the student holds the
  /// account's email.
  ///
  /// Never throws. A device check that fails must not keep a paying
  /// student out of the app they paid for — it fails open, and the
  /// single-live-session rule still stands behind it.
  Future<DeviceStanding> deviceStanding({bool verified = false}) async {
    try {
      if (_b.isDirect) {
        final r = await _b.rpc('bx_device_seen', params: {
          'p_device_id': deviceId(),
          'p_platform': defaultTargetPlatform.name,
          'p_label': _deviceLabel(),
          'p_verified': verified,
        });
        if (r['error'] != null) return DeviceStanding.unknown;
        return DeviceStanding(
          known: r['known'] == true,
          trusted: r['trusted'] == true,
          total: (r['total'] as num?)?.toInt() ?? 0,
        );
      }
      final r = await _b.apiSend('/api/mobile/device', body: {
        'deviceId': deviceId(),
        'platform': defaultTargetPlatform.name,
        'label': _deviceLabel(),
        'verified': verified,
      });
      return DeviceStanding(
        known: r['known'] == true,
        trusted: r['trusted'] == true,
        total: (r['total'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('[device] standing unavailable: $e');
      return DeviceStanding.unknown;
    }
  }

  /// Sends the six-digit code to the account's email.
  ///
  /// Supabase's own mailer, the same channel that already carries
  /// password resets. Its rate limit is real and low unless custom SMTP
  /// is configured, which is why [DeviceStanding.unknown] fails open and
  /// why an admin can trust a device by hand.
  Future<void> sendDeviceCode(String email) async {
    try {
      await _b.auth.signInWithOtp(email: email, shouldCreateUser: false);
    } catch (e) {
      throw _b.faultFor(e);
    }
  }

  /// Proves the code, which mints a session with a fresh `iat` — the
  /// thing the server actually checks before trusting the device.
  Future<void> verifyDeviceCode(String email, String code) async {
    try {
      await _b.auth.verifyOTP(
        email: email,
        token: code.trim(),
        type: OtpType.email,
      );
    } catch (e) {
      throw _b.faultFor(e);
    }
  }

  String _deviceLabel() {
    final p = defaultTargetPlatform.name;
    return '${p[0].toUpperCase()}${p.substring(1)}';
  }

  Future<Profile> loadProfile({bool force = false}) async {
    if (!force && _cached != null) return _cached!;
    final uid = _b.userId;
    if (uid == null) throw const BxError('Not signed in.');

    try {
      final rows = await _b.select('profiles', eq: {'id': uid}, limit: 1);
      if (rows.isNotEmpty) {
        _cached = Profile.fromJson(rows.first);
        await _store.writeJson(BxKeys.cachedProfile, _cached!.toJson(),
            mirror: true);
        await _store.setBool(BxKeys.activated, _cached!.isActivated);
        return _cached!;
      }
    } catch (_) {
      // RLS allows students to read their own profile row; if that read
      // failed we fall back to the API and then to the cache.
    }

    try {
      final r = await _b.apiGet('/api/profile');
      final raw = r['profile'] is Map
          ? Map<String, dynamic>.from(r['profile'])
          : r;
      _cached = Profile.fromJson(raw);
      await _store.writeJson(BxKeys.cachedProfile, _cached!.toJson(),
          mirror: true);
      return _cached!;
    } catch (_) {
      final cachedRaw = await _store.readJson(BxKeys.cachedProfile);
      if (cachedRaw != null) {
        _cached = Profile.fromJson(cachedRaw);
        // Upgrades from a build that only ever wrote the file get the
        // synchronous copy here, so the NEXT launch is instant.
        unawaited(
          _store.writeJson(BxKeys.cachedProfile, cachedRaw, mirror: true),
        );
        return _cached!;
      }
      rethrow;
    }
  }

  Future<bool> activate(String key) async {
    if (_b.isDirect) {
      final r = await _b.rpc('bx_activate_key', params: {'p_key': key.trim()});
      if (r['ok'] == true) {
        _cached = _cached?.copyWith(isActivated: true);
        await _store.setBool(BxKeys.activated, true);
        return true;
      }
      throw BxError(_activationMessage(r['error']?.toString()));
    }
    try {
      await _b.apiSend('/api/activate', body: {'key': key.trim()});
      _cached = _cached?.copyWith(isActivated: true);
      await _store.setBool(BxKeys.activated, true);
      return true;
    } on BxError catch (e) {
      throw BxError(_activationMessage(e.code));
    }
  }

  String _activationMessage(String? code) => switch (code) {
        'invalid_key' =>
          'That key does not exist. Check the digits and try again.',
        'key_used' =>
          'This key has been used already. Chat Tutor Bello if this looks wrong.',
        'not_your_key' =>
          'This key belongs to another account. Use the key sent to you.',
        _ => 'Activation failed. Try again.',
      };

  Future<void> setLevel(String levelCode) async {
    if (_b.isDirect) {
      await _b.rpc('bx_set_level', params: {'p_level': levelCode});
    } else {
      await _b.apiSend('/api/profile/level', body: {'level': levelCode});
    }
    _cached = _cached?.copyWith(currentLevel: levelCode);
    await _store.setString(BxKeys.lastLevel, levelCode);
  }

  Future<void> updateProfile({
    String? firstName,
    String? surname,
    String? phone,
    String? matric,
  }) async {
    final body = <String, dynamic>{
      if (firstName != null) 'firstName': firstName,
      if (surname != null) 'surname': surname,
      if (phone != null) 'phone': phone,
      if (matric != null) 'matric': matric,
    };
    if (body.isEmpty) return;
    if (_b.isDirect) {
      await _b.rpc('bx_update_profile', params: {
        'p_first_name': firstName,
        'p_surname': surname,
        'p_phone': phone,
        'p_matric': matric,
      });
    } else {
      await _b.apiSend('/api/profile', method: 'PATCH', body: body);
    }
    await loadProfile(force: true);
  }

  /// ------------------------------------------------------------
  /// THE SINGLE-SESSION RULE
  ///
  /// The website polls /api/auth/heartbeat every 45 seconds — the audit
  /// measured this at ~80 Vercel invocations per hour per idle student,
  /// roughly 900k a month at current scale.
  ///
  /// On the direct path this becomes a Realtime subscription to the
  /// student's own active_sessions row. When another device takes the
  /// session the row changes and this device is pushed a logout
  /// instantly. Cheaper AND faster than polling.
  /// ------------------------------------------------------------
  /// One check-in, feeding everything that needs one.
  ///
  /// On the legacy path this IS the heartbeat — the same three-minute
  /// request that enforces the single-session rule now also carries the
  /// content revision and the student's own standing, so learning that
  /// an account was frozen costs nothing it was not already spending.
  ///
  /// On the direct path the session rule is a Realtime subscription
  /// rather than a poll, so the standing gets its own timer: one cheap
  /// RPC and one row read every three minutes.
  ///
  /// Broadcast and memoised, because two listeners must not become two
  /// requests.
  Stream<SessionPulse>? _standing;

  Stream<SessionPulse> watchStanding() =>
      _standing ??= (_b.isDirect ? _directStanding() : _legacyStanding())
          .asBroadcastStream();

  /// One check-in, now, rather than waiting for the timer. Used by the
  /// journey harness to prove the mechanism without driving a
  /// three-minute clock.
  @visibleForTesting
  Future<SessionPulse> standingNow() =>
      _b.isDirect ? _directPulse() : _pulse();

  Stream<SessionPulse> _legacyStanding() =>
      Stream<int>.periodic(const Duration(minutes: 3), (tick) => tick)
          .asyncMap((_) => _pulse())
          .handleError((_) => SessionPulse.unknown);

  Stream<SessionPulse> _directStanding() =>
      Stream<int>.periodic(const Duration(minutes: 3), (tick) => tick)
          .asyncMap((_) => _directPulse())
          .handleError((_) => SessionPulse.unknown);

  /// The legacy heartbeat, read for everything it now says.
  Future<SessionPulse> _pulse() async {
    // No token to present is not the same as a stolen session, and the
    // website cannot tell them apart — /api/auth/heartbeat answers 401
    // "superseded" whether another device took the row or the header was
    // simply absent. So the app has to know the difference itself.
    //
    // Without this, any state that loses the token — a reinstall that
    // kept the Supabase session, a cleared preference, a first launch
    // after an upgrade that changed the key — reads as "somebody else
    // signed in" and ejects a paying student.
    if (_b.mobileSessionToken == null) {
      try {
        await _bindDevice();
        return SessionPulse(alive: _b.mobileSessionToken != null);
      } catch (e) {
        // Could not re-bind (usually offline). Staying signed in is the
        // right way to be wrong: the next successful bind settles it.
        debugPrint('[session] could not re-bind: $e');
        return SessionPulse.unknown;
      }
    }

    try {
      final r = await _b.apiGet('/api/auth/heartbeat', retries: 0);
      return SessionPulse.fromJson(r);
    } on BxError catch (e) {
      if (e.code == 'unauthenticated') return const SessionPulse(alive: false);
      return SessionPulse.unknown; // offline is not a crime
    } catch (_) {
      return SessionPulse.unknown;
    }
  }

  /// The same three answers on the Supabase path, where there is no
  /// heartbeat route to carry them.
  Future<SessionPulse> _directPulse() async {
    final uid = _b.userId;
    if (uid == null) return SessionPulse.unknown;
    try {
      final rev = await _b.rpc('bx_revision');

      // Whether this device still holds the session, answered by the
      // SERVER rather than inferred from an empty Realtime snapshot.
      //
      // The watcher next door maps "no row" to "still mine" on purpose,
      // and that reasoning is right — an empty result is also what a
      // race looks like, and treating it as superseded logged people
      // out at random the first time this ran. The cost was that a
      // deliberate force-logout or device reset looked exactly like a
      // race, so the student stayed signed in for ever while the admin
      // panel said "Session killed ✓".
      //
      // bx_session_standing can tell them apart because bind writes
      // user_devices and active_sessions together: a device row with no
      // session row is a revocation, not a row that has not arrived
      // yet. It answers 'unknown' whenever it cannot be certain, and
      // nothing here signs anybody out on a guess.
      var alive = true;
      try {
        final standing = await _b.rpc('bx_session_standing', params: {
          'p_device_id': deviceId(),
        });
        final verdict = standing['verdict']?.toString();
        if (verdict == 'superseded' || verdict == 'revoked') alive = false;
      } catch (e) {
        // An older database with no such function. The Realtime watcher
        // still stands behind the single-session rule.
        debugPrint('[session] standing check unavailable: $e');
      }

      Map<String, dynamic> me = const {};
      try {
        final rows = await _b.select('profiles',
            columns: 'is_frozen, frozen_reason, current_level, is_activated',
            eq: {'id': uid},
            limit: 1);
        if (rows.isNotEmpty) me = rows.first;
      } catch (e) {
        // RLS may decline; the revision half still stands on its own.
        debugPrint('[session] standing unavailable: $e');
      }
      return SessionPulse.fromJson({
        'ok': alive,
        'rev': rev['rev'],
        'revAvailable': true,
        if (me.isNotEmpty) 'me': me,
      });
    } catch (e) {
      debugPrint('[session] revision unavailable: $e');
      return SessionPulse.unknown;
    }
  }

  Stream<bool> watchSession() {
    final uid = _b.userId;
    if (uid == null) return const Stream.empty();

    if (_b.isDirect) {
      final mine = deviceId();
      return _b.sb
          .from('active_sessions')
          .stream(primaryKey: ['user_id'])
          .eq('user_id', uid)
          .map((rows) {
            // ONLY a row that explicitly names a different device means
            // somebody else took the session.
            //
            // Anything else — no row yet, a row with no device recorded,
            // the initial snapshot before the insert is visible, a
            // transient read — is "unknown", and unknown must never sign
            // a student out. Treating an empty result as superseded logs
            // people out at random, which is exactly what it did the
            // first time this ran.
            if (rows.isEmpty) return true;
            final device = rows.first['device_id']?.toString();
            if (device == null || device.isEmpty) return true;
            return device == mine;
          })
          .handleError((_) => true);
    }

    // Legacy path keeps the poll, but at a calmer cadence: the audit
    // showed 45s buys nothing over 3 minutes for a rule that only has to
    // catch a second sign-in.
    //
    // Derived from the SAME pulse the standing watcher reads, so the two
    // are one request rather than two. (Historic note worth keeping: the
    // tick type must be nullable or carry a computation — Stream.periodic
    // has nothing to emit without one, so for a non-nullable element type
    // it throws from the CONSTRUCTOR rather than at the first tick, which
    // is how `Stream<bool>.periodic(...)` here once stopped every student
    // on the legacy path from finishing a login.)
    return watchStanding().map((p) => p.alive).handleError((_) => true);
  }

  Future<void> signOut() async {
    try {
      if (!_b.isDirect) {
        await _b.apiSend('/api/auth/logout').timeout(
              const Duration(seconds: 6),
              onTimeout: () => const {},
            );
      } else {
        await _b.rpc('bx_end_session').timeout(
              const Duration(seconds: 6),
              onTimeout: () => const {},
            );
      }
    } catch (_) {}
    try {
      await _b.auth.signOut();
    } catch (_) {}
    _cached = null;
    _b.mobileSessionToken = null;
    await _store.remove(BxKeys.mobileSession);
    await _store.remove(BxKeys.activated);
    // The screen this phone was going to reopen on belonged to whoever
    // just left. Restoring it for the next student would push them into
    // somebody else's practice attempt — which the server refuses, so
    // what they would actually see is an error page on launch.
    await _store.remove(BxKeys.lastRoute);
    await _store.clearCache();
  }
}

// ============================================================
// CONTENT
// ============================================================

class ContentRepository {
  ContentRepository(this._b, this._store);

  final Backend _b;
  final LocalStore _store;

  List<Course> _courses = const [];
  List<StudyMaterial> _materials = const [];
  List<StudyLevel> _levels = const [];

  List<Course> get courses => _courses;
  List<StudyMaterial> get materials => _materials;
  List<StudyLevel> get levels => _levels;

  /// The switches Tutor Bello sets from the admin panel. They ride on
  /// the bootstrap the app already makes, so obeying them costs no
  /// extra round trip, and they are cached with it so a phone that
  /// opens offline still enforces the last policy it was told rather
  /// than falling open.
  AppPolicy _policy = const AppPolicy();
  AppPolicy get policy => _policy;

  /// One bootstrap that fills the course shelf and every material header.
  /// Falls back to the last good copy on disk so the app opens offline.
  /// Loads the shelf for a level.
  ///
  /// Returns true only when the answer came from the SERVER. A cached
  /// answer is still served — the app must keep working with the data
  /// off — but the caller has to be able to tell the difference,
  /// because "Last synced just now" after a run that never left the
  /// phone is a lie the student acts on.
  Future<bool> loadContent({required String level, bool force = false}) async {
    if (!force && _courses.isNotEmpty) return false;
    try {
      if (_b.isDirect) {
        final r = await _b.rpc('bx_content', params: {'p_level': level});
        // bx_content predates the app policy, so it is asked for
        // separately rather than by changing a function that may not
        // have been deployed yet.
        if (r['settings'] is! Map) {
          try {
            final s = await _b.rpc('bx_app_settings');
            r['settings'] = s;
          } catch (e) {
            debugPrint('[policy] bx_app_settings unavailable: $e');
          }
        }
        _ingest(r);
        await _store.writeJson(BxKeys.cachedContent, r);
        return true;
      }
      final r = await _b.apiGet('/api/mobile/content');
      final shielded = _b.shieldDeep(r) as Map<String, dynamic>;
      _ingest(shielded);
      await _store.writeJson(BxKeys.cachedContent, shielded);
      return true;
    } catch (e) {
      final cached = await _store.readJson(BxKeys.cachedContent);
      if (cached != null) {
        _ingest(cached);
        return false;
      }
      if (_courses.isEmpty) rethrow;
      return false;
    }
  }

  // ------------------------------------------------------------
  // Downloading a whole course
  // ------------------------------------------------------------

  /// The one number that moves whenever ANYTHING changes on the
  /// backend. One row, one column — cheap enough to ask on every
  /// resume, which is the whole point of it existing.
  ///
  /// Answers "unavailable" rather than throwing when migration 0014 has
  /// not been applied; the caller then falls back to comparing the
  /// manifest, which is what it did before this existed.
  Future<ContentRevision> revision() async {
    try {
      final r = _b.isDirect
          ? await _b.rpc('bx_revision')
          : await _b.apiGet('/api/mobile/revision', retries: 0);
      return ContentRevision.fromJson({
        ...r,
        if (_b.isDirect) 'available': true,
      });
    } catch (e) {
      debugPrint('[content] revision unavailable: $e');
      return const ContentRevision();
    }
  }

  /// How much of each course the server is publishing right now.
  ///
  /// The cheapest question the app asks, and the whole of the "there's
  /// a change in this course, download now" badge. Deliberately not a
  /// diff: a diff costs the server real work on every app open, and the
  /// app has to fetch the changed rows anyway.
  /// The revision the last manifest was read at, so the caller can tell
  /// whether asking again could possibly say anything new.
  int lastManifestRev = 0;

  Future<List<CourseStamp>> manifest() async {
    final r = _b.isDirect
        ? await _b.rpc('bx_manifest')
        : await _b.apiGet('/api/mobile/manifest');
    lastManifestRev = ContentRevision.fromJson({
      ...r,
      if (_b.isDirect) 'available': true,
    }).rev;
    final rows = r['courses'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((e) => CourseStamp.fromJson(Map<String, dynamic>.from(e)))
        .where((c) => c.id.isNotEmpty)
        .toList(growable: false);
  }

  /// One page of one course: materials with their bodies, questions
  /// with their keys.
  ///
  /// [part] is 'all', 'materials' or 'questions'. The downloader walks
  /// the two halves separately so a course with three materials and
  /// nine hundred questions does not re-send the materials on every
  /// page.
  Future<CourseBundlePage> courseBundle(
    String courseId, {
    int offset = 0,
    int limit = 200,
    String part = 'all',
  }) async {
    final Map<String, dynamic> r;
    if (_b.isDirect) {
      r = await _b.rpc('bx_course_bundle', params: {
        'p_course_id': courseId,
        'p_offset': offset,
        'p_limit': limit,
        'p_part': part,
      });
      final err = r['error']?.toString();
      if (err != null) throw BxError(_bundleMessage(err));
    } else {
      r = await _b.apiGet(
        '/api/mobile/course-bundle?courseId=$courseId&offset=$offset'
        '&limit=$limit&part=$part',
      );
    }
    // Every storage URL in the payload goes through the shield, so an
    // image inside a note body or a question resolves the same way it
    // would have on the path the app is running.
    return CourseBundlePage.fromJson(
      _b.shieldDeep(r) as Map<String, dynamic>,
    );
  }

  /// Every id the course still publishes, withheld ones included.
  ///
  /// This is what lets a download DROP what Tutor Bello withdrew. It
  /// cannot be worked out from the bundle pages: those deliberately
  /// hold back the questions pinned to a test, so "not sent" and "no
  /// longer there" look identical from the app's side.
  Future<CourseIndex> courseIndex(String courseId) async {
    try {
      final r = _b.isDirect
          ? await _b.rpc('bx_course_ids', params: {'p_course_id': courseId})
          : await _b.apiGet(
              '/api/mobile/course-bundle?courseId=$courseId&part=ids');
      if (r['error'] != null) return const CourseIndex();
      return CourseIndex.fromJson({
        ...r,
        if (_b.isDirect) 'complete': r['complete'] ?? true,
      });
    } catch (e) {
      // A list the app could not read must never be pruned against.
      debugPrint('[content] course index unavailable: $e');
      return const CourseIndex();
    }
  }

  /// Whether a course the phone still holds has been withdrawn.
  ///
  /// "Not in the manifest" is NOT enough to answer this. The manifest is
  /// filtered to the student's current level, so a course they simply
  /// are not standing on right now looks exactly like one Tutor Bello
  /// deleted — and deleting a student's downloaded material because
  /// they switched level would be unforgivable.
  ///
  /// So it is asked directly. bx_course_ids and the ids route both look
  /// only at is_visible, not at level, so `not_found` means genuinely
  /// gone or hidden and anything else means it is still there.
  ///
  /// Returns null when the question could not be answered — offline, a
  /// timeout — and null must never be treated as gone.
  Future<bool?> isCourseWithdrawn(String courseId) async {
    if (courseId.isEmpty) return null;
    try {
      if (_b.isDirect) {
        final r = await _b.rpc('bx_course_ids', params: {
          'p_course_id': courseId,
        });
        final err = r['error']?.toString();
        if (err == 'not_found') return true;
        if (err != null) return null;
        return false;
      }
      final r = await _b.apiGet(
        '/api/mobile/course-bundle?courseId=$courseId&part=ids',
        retries: 0,
      );
      return r['error']?.toString() == 'not_found';
    } on BxError catch (e) {
      // 404 is an answer. Everything else is a failure to ask.
      if (e.code == 'not_found') return true;
      return null;
    } catch (_) {
      return null;
    }
  }

  String _bundleMessage(String code) => switch (code) {
        'not_found' => 'That course is not on your shelf.',
        'not_activated' => 'Activate your account to download a course.',
        _ => 'That course could not be downloaded.',
      };

  /// Throws the previous student's shelf away.
  ///
  /// The repository is a long-lived object and its lists are plain
  /// fields, so signing out left the courses, the levels and the
  /// SCREENSHOT POLICY of whoever just left sitting in memory — ready
  /// to be shown to the next person to sign in on that phone, for as
  /// long as it took the first content read to come back.
  void forget() {
    _courses = const [];
    _materials = const [];
    _levels = const [];
    _policy = const AppPolicy();
    lastManifestRev = 0;
  }

  void _ingest(Map<String, dynamic> r) {
    final rawCourses = r['courses'];
    if (rawCourses is List) {
      _courses = rawCourses
          .whereType<Map>()
          .map((e) => Course.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    final rawMaterials = r['materials'];
    if (rawMaterials is List) {
      _materials = rawMaterials
          .whereType<Map>()
          .map((e) => StudyMaterial.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    final rawSettings = r['settings'];
    if (rawSettings is Map) {
      _policy = AppPolicy.fromJson(Map<String, dynamic>.from(rawSettings));
    }
    final rawLevels = r['levels'];
    if (rawLevels is List) {
      _levels = rawLevels
          .whereType<Map>()
          .map((e) => StudyLevel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
  }

  Course? courseByCode(String code) {
    for (final c in _courses) {
      if (c.code.toLowerCase() == code.toLowerCase()) return c;
    }
    return null;
  }

  Course? courseById(String id) {
    for (final c in _courses) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<StudyMaterial> materialsFor(String courseId, Set<MaterialKind> kinds) {
    final list = _materials
        .where((m) => m.courseId == courseId && kinds.contains(m.kind))
        .toList()
      ..sort((a, b) {
        final s = a.sortOrder.compareTo(b.sortOrder);
        if (s != 0) return s;
        final ad = a.createdAt, bd = b.createdAt;
        if (ad == null || bd == null) return 0;
        return ad.compareTo(bd);
      });
    return list;
  }

  int countFor(String courseId, Set<MaterialKind> kinds) =>
      materialsFor(courseId, kinds).length;

  /// Full material including the note body. Activation is enforced by
  /// the database policy on the direct path, and by the route on legacy.
  Future<StudyMaterial> material(String id) async {
    final offline = Offline.store;
    final savedHtml = await offline?.readNote(id);

    try {
      final StudyMaterial m;
      if (_b.isDirect) {
        final r = await _b.rpc('bx_material', params: {'p_id': id});
        if (r['error'] == 'not_activated') throw BxError.notActivated;
        final raw = r['material'] is Map
            ? Map<String, dynamic>.from(r['material'])
            : r;
        m = StudyMaterial.fromJson(_b.shieldDeep(raw));
      } else {
        final r = await _b.apiGet('/api/mobile/material/$id');
        final raw =
            r['material'] is Map ? Map<String, dynamic>.from(r['material']) : r;
        m = StudyMaterial.fromJson(_b.shieldDeep(raw));
      }

      // Reading a note is the moment to keep it. Nothing about that
      // costs the student anything — the bytes are already down.
      if (offline != null && m.hasBody) {
        final header = _materials.where((h) => h.id == id).firstOrNull;
        final sig = m.updatedAt?.toIso8601String() ??
            header?.updatedAt?.toIso8601String() ??
            m.url;
        if (!offline.isCurrent(id, sig)) {
          unawaited(() async {
            try {
              await offline.putNote(
                id: id,
                title: m.title.isEmpty ? (header?.title ?? '') : m.title,
                html: m.contentHtml,
                courseCode: courseById(m.courseId)?.code ?? '',
                courseId: m.courseId,
                sig: sig,
              );
              await offline.flush();
            } catch (e) {
              debugPrint('[offline] could not keep note $id: $e');
            }
          }());
        }
      }
      return m;
    } catch (e) {
      final header = _materials.where((m) => m.id == id).firstOrNull;
      final saved = offline?.item(id);

      // A saved DOCUMENT counts, not only a saved note.
      //
      // This is the whole of "when I downloaded some pdf, it showed in
      // the offline vault that it's downloaded, when I put off my
      // internet connection it was saying that internet connection
      // issues". The reader asks for the material before it asks for
      // the file, and this fallback only ever recognised a note body —
      // so a slide or a past question sitting complete on the disk
      // threw a network error before anything got as far as looking at
      // the disk. The file was always there. Nothing ever opened it.
      if (savedHtml == null && saved?.hasDoc != true) rethrow;

      return StudyMaterial(
        id: id,
        courseId: header?.courseId ?? saved?.courseId ?? '',
        kind: header?.kind ??
            (saved != null
                ? materialKindOf(saved.kind)
                : MaterialKind.note),
        title: header?.title ??
            saved?.title ??
            (savedHtml != null ? 'Saved note' : 'Saved document'),
        topic: header?.topic ?? '',
        // The URL is carried through so a student who comes back online
        // can still refresh, and so the office branch has something to
        // hand to the viewer.
        url: header?.url ?? '',
        contentHtml: savedHtml ?? '',
        updatedAt: header?.updatedAt,
        createdAt: header?.createdAt,
        sortOrder: header?.sortOrder ?? 0,
      );
    }
  }

  /// Awards the reading point. Fire-and-forget: never blocks the reader.
  void markOpened(String materialId) {
    unawaited(() async {
      try {
        if (_b.isDirect) {
          await _b.rpc('bx_material_opened', params: {'p_id': materialId});
        }
        // On the legacy path the website awards this inside the page
        // render, which the app does not call — so the point is only
        // available on the direct path. Nothing breaks either way.
      } catch (_) {}
    }());
  }

  String fileUrl(String? raw) => _b.fileUrl(raw);
}

// ============================================================
// ASSESSMENT — practice, tests, exams, results, revision
// ============================================================

class AssessmentRepository {
  AssessmentRepository(this._b, [this._offline]);
  final Backend _b;

  /// Where every question the student has already been shown is kept.
  /// Nothing about questions was cached before this — not the text, not
  /// the options, not the pictures — so "questions work offline" was a
  /// claim with no code behind it.
  final OfflineStore? _offline;

  OfflineStore? get _store => _offline ?? Offline.store;

  Future<List<StudyTest>> testsFor(String courseId) async {
    if (_b.isDirect) {
      final rows =
          await _b.rpcList('bx_tests', params: {'p_course_id': courseId});
      return rows.map(StudyTest.fromJson).toList();
    }
    final r = await _b.apiGet('/api/mobile/tests');
    final all = (r['tests'] as List?) ?? const [];
    return all
        .whereType<Map>()
        .map((e) => StudyTest.fromJson(Map<String, dynamic>.from(e)))
        .where((t) => courseId.isEmpty || t.courseId == courseId)
        .toList();
  }

  Future<String> startPractice(String courseId, {int count = 20}) =>
      _start(mode: 'practice', courseId: courseId, count: count);

  Future<String> startSmart({String? courseId}) =>
      _start(mode: 'smart', courseId: courseId, count: 20);

  Future<String> startBookmarks() => _start(mode: 'bookmarks', count: 20);

  Future<String> startTest(String testId) => _start(mode: 'test', testId: testId);

  /// A live class test opened from a share code or a deep link.
  Future<String> startShareCode(String code) =>
      _start(mode: 'test', shareCode: code.toUpperCase());

  /// Refuses a server-side start while the platform is closed.
  ///
  /// Set from the app policy on every resume. Deliberately narrow: it
  /// stops things that need the SERVER, and leaves everything already
  /// on the phone alone — a student practising a downloaded course
  /// during a twenty-minute deploy should not be interrupted at all.
  AppPolicy policyForStart = const AppPolicy();

  Future<String> _start({
    required String mode,
    String? courseId,
    String? testId,
    String? shareCode,
    int count = 20,
  }) async {
    if (policyForStart.maintenance) {
      throw BxError(policyForStart.closedMessage, code: 'maintenance');
    }
    if (_b.isDirect) {
      final r = await _b.rpc('bx_start_attempt', params: {
        'p_mode': mode,
        'p_course_id': courseId,
        'p_test_id': testId,
        'p_share_code': shareCode,
        'p_count': count,
      });
      final err = r['error']?.toString();
      if (err != null) throw BxError(_startMessage(err));
      final id = r['attemptId']?.toString() ?? r['attempt_id']?.toString();
      if (id == null || id.isEmpty) {
        throw const BxError('Could not start. Try again.');
      }
      return id;
    }

    if (mode == 'test') {
      final r = await _b.apiSend('/api/cbt/start', body: {'testId': testId});
      final id = r['attemptId']?.toString();
      if (id == null) throw const BxError('Could not start the test.');
      return id;
    }
    final r = await _b.apiSend('/api/practice/start', body: {
      'mode': mode,
      if (courseId != null) 'courseId': courseId,
      'count': count,
    });
    final id = r['attemptId']?.toString();
    if (id == null) throw const BxError('Could not start practice.');
    return id;
  }

  String _startMessage(String code) => switch (code) {
        'not_activated' => 'Activate your account to start this.',
        'no_questions' =>
          'This has no questions loaded yet. Tell Tutor Bello — he will fix it.',
        'no_bookmarks' =>
          'You have not saved any questions yet. Tap Save during practice.',
        'nothing_missed' =>
          'Nothing to revise yet. Do a few practice rounds first.',
        'test_closed' =>
          'This live test is closed right now. Wait for Tutor Bello to open it.',
        'not_found' => 'That test could not be found.',
        _ => 'Could not start. Try again.',
      };

  /// Starts practice, and falls back to the phone's own bank when the
  /// server cannot be reached.
  ///
  /// Only for a TRANSPORT failure. "This course has no questions loaded
  /// yet" is a real answer from a reachable server and a student needs
  /// to read it — quietly substituting a different round would hide the
  /// thing they should be telling Tutor Bello about.
  Future<String> startPracticeOrOffline(
    String courseId, {
    int count = 20,
  }) async {
    try {
      return await startPractice(courseId, count: count);
    } catch (e) {
      final code = e is BxError ? e.code : null;
      if (code != 'offline' && code != 'timeout') rethrow;
      // The offline attempt's own message is the more useful one here:
      // "no saved questions yet, download this course" beats "no
      // internet connection", because the student can act on it.
      return startOfflinePractice(courseId: courseId, count: count);
    }
  }

  Future<AttemptSession> openAttempt(String attemptId) async {
    // A round taken with no signal never reaches a server.
    if (attemptId.startsWith(kLocalAttemptPrefix)) {
      final session = await _localSession(attemptId);
      if (session != null) return session;
      throw const BxError('That practice round is no longer on this phone.');
    }
    try {
      final live = await _openAttemptOnline(attemptId);
      await _remember(live);
      return live;
    } catch (e) {
      // Offline, or the server refused. If we hold this exact attempt
      // from an earlier open, the student carries on where they were
      // instead of losing the round.
      if (e is BxError && e.code == 'submitted') rethrow;
      final saved = await _savedSession(attemptId);
      if (saved != null) return saved;
      rethrow;
    }
  }

  Future<AttemptSession> _openAttemptOnline(String attemptId) async {
    if (_b.isDirect) {
      final r =
          await _b.rpc('bx_open_attempt', params: {'p_attempt_id': attemptId});
      if (r['error'] != null) {
        throw BxError(
          r['error'] == 'submitted'
              ? 'This attempt is already submitted.'
              : 'This attempt could not be opened.',
          code: r['error']?.toString(),
        );
      }
      return AttemptSession.fromJson(_b.shieldDeep(r));
    }
    // The legacy API splits practice and CBT across two routes.
    try {
      final r = await _b.apiGet('/api/practice/$attemptId');
      if (r['redirect'] == 'results') {
        throw const BxError('This attempt is already submitted.',
            code: 'submitted');
      }
      return AttemptSession.fromJson(_b.shieldDeep(r));
    } on BxError catch (e) {
      if (e.code == 'submitted') rethrow;
      final r = await _b.apiGet('/api/cbt/$attemptId');
      if (r['redirect'] == 'results') {
        throw const BxError('This attempt is already submitted.',
            code: 'submitted');
      }
      return AttemptSession.fromJson(_b.shieldDeep(r));
    }
  }

  /// Practice answer: graded in Postgres on the direct path, so the
  /// answer key never has to reach the device before the student commits.
  Future<AnswerVerdict> answerPractice(
    String attemptId,
    String questionId, {
    String choice = '',
    String answerText = '',
  }) async {
    if (isLocalAttempt(attemptId)) {
      return answerOffline(attemptId, questionId,
          choice: choice, answerText: answerText);
    }
    if (_b.isDirect) {
      final r = await _b.rpc('bx_answer', params: {
        'p_attempt_id': attemptId,
        'p_question_id': questionId,
        'p_choice': choice.isEmpty ? null : choice,
        'p_answer_text': answerText.isEmpty ? null : answerText,
      });
      final verdict = AnswerVerdict.fromJson(_b.shieldDeep(r));
      // NOT awaited. Both of these are bookkeeping; neither is anything
      // the student is waiting to see, and putting disk work between
      // the tap and the right/wrong is how an answer starts to feel
      // slow halfway through a semester.
      unawaited(_rememberVerdict(questionId, verdict));
      unawaited(_rememberAnswer(attemptId, questionId,
          choice: choice, answerText: answerText, correct: verdict.correct));
      return verdict;
    }
    final r = await _b.apiSend('/api/practice/answer', body: {
      'attemptId': attemptId,
      'questionId': questionId,
      'choice': choice,
      'answerText': answerText,
    });
    final verdict = AnswerVerdict.fromJson(_b.shieldDeep(r));
    unawaited(_rememberVerdict(questionId, verdict));
    unawaited(_rememberAnswer(attemptId, questionId,
        choice: choice, answerText: answerText, correct: verdict.correct));
    return verdict;
  }

  /// Writes one committed answer into the locally-held copy of the
  /// attempt.
  ///
  /// The attempt was only ever saved at the moment it OPENED. Every
  /// answer after that lived in the practice screen's State object and
  /// nowhere else, so a student who was pulled out of the app — an
  /// incoming call, a battery-saver kill, an aggressive OEM task killer,
  /// which is most of the phones this app runs on — came back to a round
  /// that had forgotten everything they had done.
  ///
  /// The screen already resumes at the first UNANSWERED question, so
  /// keeping the answers current is the whole of what "meet it back"
  /// needs: the position falls out of it.
  Future<void> _rememberAnswer(
    String attemptId,
    String questionId, {
    required String choice,
    required String answerText,
    required bool correct,
  }) async {
    final store = _store;
    if (store == null) return;
    try {
      final raw = await store.attempt(attemptId);
      if (raw == null) return;
      final session = raw['session'];
      if (session is! Map) return;

      final answers = Map<String, dynamic>.from(
          (session['answers'] as Map?)?.cast<String, dynamic>() ?? {});
      answers[questionId] = {
        'choice': choice,
        'answer_text': answerText,
        'is_correct': correct,
      };
      session['answers'] = answers;
      raw['session'] = session;
      raw['at'] = DateTime.now().millisecondsSinceEpoch;
      await store.putAttempt(attemptId, raw);
    } catch (e) {
      debugPrint('[offline] could not keep the answer: $e');
    }
  }

  /// Folds what the server just revealed back into the cached question.
  ///
  /// The direct path opens an attempt with the answer key STRIPPED and
  /// only discloses it once the student has committed an answer. That is
  /// the right call for the server and it means the cached copy of a
  /// question is incomplete until this runs. Without it, a question
  /// practised online would still be unmarkable offline.
  Future<void> _rememberVerdict(String questionId, AnswerVerdict v) async {
    final store = _store;
    if (store == null) return;

    final fields = <String, dynamic>{
      if ((v.correctKey ?? '').isNotEmpty) 'correct_key': v.correctKey,
      if ((v.acceptedAnswer ?? '').isNotEmpty) 'answer_text': v.acceptedAnswer,
      if ((v.explanationHtml ?? '').isNotEmpty)
        'explanation_html': v.explanationHtml,
      if ((v.explanationImageUrl ?? '').isNotEmpty)
        'explanation_image_url': v.explanationImageUrl,
      if ((v.explanationAudioUrl ?? '').isNotEmpty)
        'explanation_audio_url': v.explanationAudioUrl,
    };
    if (fields.isEmpty) return;

    try {
      await store.patchQuestion(questionId, fields);
    } catch (e) {
      debugPrint('[offline] could not fold in the verdict: $e');
    }
  }

  /// Test/exam answer. Never returns correctness. Always returns the
  /// freshest deadline so a live extension reaches every student.
  Future<AnswerVerdict> answerCbt(
    String attemptId,
    String questionId, {
    String choice = '',
    String answerText = '',
  }) async {
    if (_b.isDirect) {
      final r = await _b.rpc('bx_answer', params: {
        'p_attempt_id': attemptId,
        'p_question_id': questionId,
        'p_choice': choice.isEmpty ? null : choice,
        'p_answer_text': answerText.isEmpty ? null : answerText,
      });
      return AnswerVerdict.fromJson(_b.shieldDeep(r));
    }
    final r = await _b.apiSend('/api/cbt/answer', body: {
      'attemptId': attemptId,
      'questionId': questionId,
      'choice': choice,
      'answerText': answerText,
    });
    // Shielded like every other payload. This one was not, so a CBT
    // explanation picture arrived as a bare storage URL while the
    // identical field on the practice route arrived resolved.
    return AnswerVerdict.fromJson(_b.shieldDeep(r));
  }

  /// Tells the backend which question the student is looking at.
  ///
  /// Fire and forget, and deliberately so: this is a bookmark, not a
  /// commitment. It must never block a swipe, never show an error, and
  /// never be the reason a page turn feels slow. The website has
  /// accepted this since it was written (/api/practice/[id] PATCH,
  /// action "index") and the app simply never sent it.
  void reportPosition(String attemptId, int index) {
    if (isLocalAttempt(attemptId)) {
      unawaited(_rememberPosition(attemptId, index));
      return;
    }
    unawaited(() async {
      try {
        if (_b.isDirect) {
          await _b.rpc('bx_set_attempt_index', params: {
            'p_attempt_id': attemptId,
            'p_index': index,
          });
        } else {
          await _b.apiSend('/api/practice/$attemptId',
              method: 'PATCH', body: {'action': 'index', 'index': index});
        }
      } catch (_) {
        // Offline. The local copy below is what resume will read.
      }
      await _rememberPosition(attemptId, index);
    }());
  }

  /// Keeps the position on the phone too, so a resume with no signal
  /// lands in the same place a resume with signal would.
  Future<void> _rememberPosition(String attemptId, int index) async {
    final store = _store;
    if (store == null) return;
    try {
      final raw = await store.attempt(attemptId);
      if (raw == null) return;
      if (raw['session'] is Map) {
        final session = Map<String, dynamic>.from(raw['session'] as Map);
        session['current_index'] = index;
        raw['session'] = session;
      } else {
        raw['current_index'] = index;
      }
      await store.putAttempt(attemptId, raw);
    } catch (e) {
      debugPrint('[offline] could not keep the position: $e');
    }
  }

  Future<void> submit(String attemptId) async {
    if (isLocalAttempt(attemptId)) return finishOffline(attemptId);
    if (_b.isDirect) {
      await _b.rpc('bx_submit_attempt', params: {'p_attempt_id': attemptId});
      return;
    }
    try {
      await _b.apiSend('/api/cbt/submit', body: {'attemptId': attemptId});
    } catch (_) {
      await _b.apiSend('/api/practice/$attemptId',
          method: 'PATCH', body: {'action': 'finish'});
    }
  }

  Future<void> finishPractice(String attemptId) async {
    if (isLocalAttempt(attemptId)) return finishOffline(attemptId);
    if (_b.isDirect) {
      await _b.rpc('bx_submit_attempt', params: {'p_attempt_id': attemptId});
      return;
    }
    await _b.apiSend('/api/practice/$attemptId',
        method: 'PATCH', body: {'action': 'finish'});
  }

  Future<ResultReview> result(String attemptId) async {
    if (isLocalAttempt(attemptId)) {
      final local = await offlineResult(attemptId);
      if (local != null) return local;
      throw const BxError('That practice round is no longer on this phone.');
    }
    try {
      final ResultReview review;
      if (_b.isDirect) {
        final r = await _b
            .rpc('bx_attempt_result', params: {'p_attempt_id': attemptId});
        if (r['error'] != null) {
          throw const BxError('That result could not be opened.');
        }
        review = ResultReview.fromJson(_b.shieldDeep(r));
      } else {
        final r = await _b.apiGet('/api/mobile/cbt-result/$attemptId');
        review = ResultReview.fromJson(_b.shieldDeep(r));
      }
      // A review carries the explanation for every question, which is
      // the most useful thing in the app to have offline.
      if (!review.mode.isTimed) {
        await rememberQuestions(
          review.courseId.isEmpty ? 'general' : review.courseId,
          review.items.map((i) => i.question).toList(),
        );
      }
      await _rememberReview(review);
      return review;
    } catch (e) {
      final saved = await _savedReview(attemptId);
      if (saved != null) return saved;
      rethrow;
    }
  }

  Future<void> _rememberReview(ResultReview r) async {
    final store = _store;
    if (store == null || r.mode.isTimed) return;
    try {
      await store.putAttempt('review-${r.attemptId}', {
        'at': DateTime.now().millisecondsSinceEpoch,
        'kind': 'review',
        'status': 'submitted',
        'course_id': r.courseId,
        'score': r.score,
        'total': r.total,
        'title': r.title,
        'questions': r.items.map((i) => i.question.toJson()).toList(),
        'answers': {
          for (final i in r.items)
            i.question.id: {
              'choice': i.yourKey ?? '',
              'answer_text': i.yourText ?? '',
              'is_correct': i.isCorrect,
            }
        },
      });
    } catch (e) {
      debugPrint('[offline] could not keep review ${r.attemptId}: $e');
    }
  }

  Future<ResultReview?> _savedReview(String attemptId) async {
    final store = _store;
    if (store == null) return null;
    if (await store.attempt('review-$attemptId') == null) return null;
    final r = await offlineResult('review-$attemptId');
    if (r == null) return null;
    return ResultReview(
      attemptId: attemptId,
      score: r.score,
      total: r.total,
      mode: r.mode,
      title: r.title,
      courseId: r.courseId,
      items: r.items,
    );
  }

  void reportViolation(String attemptId, String kind) {
    unawaited(() async {
      try {
        if (_b.isDirect) {
          await _b.rpc('bx_log_violation',
              params: {'p_attempt_id': attemptId, 'p_kind': kind});
        } else {
          await _b.apiSend('/api/cbt/violation',
              body: {'attemptId': attemptId, 'kind': kind});
        }
      } catch (_) {}
    }());
  }

  Future<bool> toggleBookmark(String questionId) async {
    if (_b.isDirect) {
      final r = await _b
          .rpc('bx_toggle_bookmark', params: {'p_question_id': questionId});
      return r['saved'] == true;
    }
    final r = await _b
        .apiSend('/api/bookmarks/toggle', body: {'questionId': questionId});
    return r['saved'] == true || r['bookmarked'] == true;
  }

  Future<void> reportQuestion(String questionId, String reason) async {
    if (_b.isDirect) {
      await _b.rpc('bx_report_question',
          params: {'p_question_id': questionId, 'p_reason': reason});
      return;
    }
    await _b.apiSend('/api/questions/report',
        body: {'questionId': questionId, 'reason': reason});
  }

  Future<List<WeakSpot>> weakSpots() async {
    if (_b.isDirect) {
      final rows = await _b.rpcList('bx_weak_spots');
      return rows.map(WeakSpot.fromJson).toList();
    }
    final r = await _b.apiGet('/api/mistakes');
    final rows = (r['byCourse'] as List?) ?? const [];
    return rows
        .whereType<Map>()
        .map((e) => WeakSpot.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<int> bookmarkCount() async {
    if (_b.isDirect) {
      final r = await _b.rpc('bx_bookmark_count');
      return intOf(r['count']);
    }
    try {
      final r = await _b.apiGet('/api/mistakes');
      return intOf(r['bookmarkCount']);
    } catch (_) {
      return 0;
    }
  }

  Future<List<Question>> mistakes() async {
    try {
      final List<Question> list;
      if (_b.isDirect) {
        final rows = await _b.rpcList('bx_mistakes');
        list = rows.map((e) => Question.fromJson(_b.shieldDeep(e))).toList();
      } else {
        final r = await _b.apiGet('/api/mistakes');
        final rows = (r['items'] as List?) ?? const [];
        list = rows
            .whereType<Map>()
            .map((e) =>
                Question.fromJson(_b.shieldDeep(Map<String, dynamic>.from(e))))
            .toList();
      }
      await rememberQuestions('mistakes', list);
      return list;
    } catch (e) {
      // The revision list is exactly what a student wants on a bus with
      // no signal, so the saved copy answers when the network cannot.
      final saved = await _savedQuestions('mistakes');
      if (saved.isNotEmpty) return saved;
      rethrow;
    }
  }

  Future<List<Question>> _savedQuestions(String bucket) async {
    final store = _store;
    if (store == null) return const [];
    try {
      return (await store.questions(bucket)).map(Question.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<AttemptSummary>> recentResults({int limit = 20}) async {
    if (_b.isDirect) {
      final rows = await _b.rpcList('bx_recent_results', params: {'p_limit': limit});
      return rows.map(AttemptSummary.fromJson).toList();
    }
    try {
      final r = await _b.apiGet('/api/me/summary');
      final rows = (r['recent'] as List?) ?? const [];
      return rows
          .whereType<Map>()
          .map((e) => AttemptSummary.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // ============================================================
  // OFFLINE
  //
  // Everything below exists because "questions work offline" was not
  // true. Nothing about a question was written to disk anywhere in the
  // app: not the text, not the options, not the explanation, not the
  // pictures. The Offline Vault held only whole documents a student had
  // remembered to tap Save on, which is why it looked empty.
  //
  // What is kept, and what deliberately is not:
  //
  //   · **Practice, smart revision, saved questions and mistakes** are
  //     kept in full — text, options, marks, the answer key, the
  //     explanation, and every picture and voice note they reference.
  //     The key is already on the device the moment an attempt opens on
  //     both backend paths (the legacy route selects `*`, and the direct
  //     RPC returns it for untimed modes), so keeping it discloses
  //     nothing new. It is what lets a round be marked with no signal.
  //
  //   · **Tests and exams are never kept.** Both paths deliberately
  //     strip the key for timed modes, and a cached exam paper would be
  //     a leak whatever we did with it. `_cacheable` is the gate, and it
  //     is checked on every write.
  // ============================================================

  /// Only untimed work is ever written to disk.
  static bool _cacheable(AttemptMode mode) => !mode.isTimed;

  /// Pulls down the pictures and voice notes a set of questions points
  /// at, right now rather than at the next sync.
  ///
  /// Without this there is a chicken and egg: the sync prefetches media
  /// for questions it already holds, and it only holds questions after
  /// a round has been opened — so the first round's diagrams would not
  /// be on the phone until a sync that happens later. A student who
  /// practises once and then loses signal would have the text and a
  /// grey box.
  Future<void> _keepQuestionMedia(Iterable<Question> questions) async {
    final store = _store;
    if (store == null) return;
    final urls = <String>{};
    for (final q in questions) {
      for (final raw in [
        q.questionImageUrl,
        q.questionAudioUrl,
        q.explanationImageUrl,
        q.explanationAudioUrl,
      ]) {
        if (raw != null && raw.trim().isNotEmpty) urls.add(raw);
      }
      for (final body in [q.questionHtml, q.explanationHtml ?? '']) {
        for (final m in kEmbeddedStorageUrl.allMatches(body)) {
          urls.add(m.group(0)!);
        }
      }
    }
    for (final raw in urls) {
      final url = _b.fileUrl(raw);
      if (url.isEmpty || store.hasAsset(url)) continue;
      try {
        final res = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 30));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          await store.putAsset(url, res.bodyBytes);
        }
      } catch (_) {
        // One missing diagram is not worth failing a round over.
      }
    }
    await store.flush();
  }

  Future<void> _remember(AttemptSession s) async {
    final store = _store;
    if (store == null || !_cacheable(s.mode)) return;
    try {
      await store.putQuestions(
        s.courseId.isEmpty ? 'general' : s.courseId,
        s.questions.map((q) => q.toJson()).toList(),
      );
      unawaited(_keepQuestionMedia(s.questions));
      // The session itself, so a resume works with the radio off.
      await store.putAttempt(s.id, {
        'at': DateTime.now().millisecondsSinceEpoch,
        'kind': 'server',
        'session': _sessionToJson(s),
      });
    } catch (e) {
      debugPrint('[offline] could not keep attempt ${s.id}: $e');
    }
  }

  /// Files a batch of questions that did not arrive inside an attempt —
  /// the mistakes list, the millionaire deal, a result review.
  Future<void> rememberQuestions(String bucket, List<Question> questions) async {
    final store = _store;
    if (store == null || questions.isEmpty) return;
    try {
      await store.putQuestions(
          bucket, questions.map((q) => q.toJson()).toList());
      unawaited(_keepQuestionMedia(questions));
    } catch (e) {
      debugPrint('[offline] could not keep $bucket: $e');
    }
  }

  Future<AttemptSession?> _savedSession(String attemptId) async {
    final store = _store;
    if (store == null) return null;
    final raw = await store.attempt(attemptId);
    final session = raw?['session'];
    if (session is! Map) return null;
    try {
      return AttemptSession.fromJson(Map<String, dynamic>.from(session));
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _sessionToJson(AttemptSession s) => {
        'id': s.id,
        'mode': s.mode.name,
        'status': s.status,
        'questions': s.questions.map((q) => q.toJson()).toList(),
        'answers': {
          for (final e in s.answers.entries)
            e.key: {
              'choice': e.value.choice,
              'answer_text': e.value.answerText,
              'is_correct': e.value.isCorrect,
            }
        },
        'bookmarks': s.bookmarks.toList(),
        'title': s.title,
        'course_code': s.courseCode,
        'course_title': s.courseTitle,
        'course_id': s.courseId,
        // Without this the position is lost the moment the round is
        // resumed from disk instead of from the server, which is
        // precisely the case offline resume exists for.
        'current_index': s.currentIndex,
      };

  // ---- a round taken with no signal ---------------------------

  /// How many questions are available to practise offline right now.
  Future<int> offlineQuestionCount({String? courseId}) async {
    final store = _store;
    if (store == null) return 0;
    final rows = await store.allQuestions();
    if (courseId == null || courseId.isEmpty) return rows.length;
    return rows.where((r) => '${r['course_id'] ?? ''}' == courseId).length;
  }

  /// Starts a practice round from what is already on the phone.
  ///
  /// It is deliberately NOT replayed to the server afterwards. Minting a
  /// server attempt from the device and answering it programmatically
  /// would put points, streaks and leaderboard positions into the
  /// database that no server ever saw being earned, and there is no way
  /// to verify it did the right thing. So an offline round is revision:
  /// it marks itself, it shows the explanations, it feeds the local
  /// mistakes list, and it says plainly that it is not on the record.
  Future<String> startOfflinePractice({String? courseId, int count = 20}) async {
    final store = _store;
    if (store == null) {
      throw const BxError('This device cannot keep offline questions.');
    }
    var rows = await store.allQuestions();
    if (courseId != null && courseId.isNotEmpty) {
      final forCourse =
          rows.where((r) => '${r['course_id'] ?? ''}' == courseId).toList();
      if (forCourse.isNotEmpty) rows = forCourse;
    }
    if (rows.isEmpty) {
      throw const BxError(
          'No saved questions for this course yet. Open the course and tap '
          'Download — it pulls every question onto this phone.');
    }

    // Only questions that can actually be MARKED. A round where every
    // answer comes back wrong because the key was never on the phone is
    // worse than no round at all, and the direct path deliberately
    // withholds the key until a question has been answered once.
    final markable = rows.where(isMarkableOffline).toList();
    if (markable.isEmpty) {
      throw const BxError(
          'The questions on this phone cannot be marked without data yet. '
          'Open the course and tap Download — that brings the answers down '
          'too.');
    }
    rows = markable;
    rows.shuffle();
    final picked = rows.take(count.clamp(1, rows.length)).toList();

    final id = '$kLocalAttemptPrefix${DateTime.now().millisecondsSinceEpoch}';
    await store.putAttempt(id, {
      'at': DateTime.now().millisecondsSinceEpoch,
      'kind': 'local',
      'status': 'in_progress',
      'course_id': courseId ?? '',
      'questions': picked,
      'answers': <String, dynamic>{},
    });
    return id;
  }

  Future<AttemptSession?> _localSession(String id) async {
    final store = _store;
    if (store == null) return null;
    final raw = await store.attempt(id);
    if (raw == null) return null;
    final questions = (raw['questions'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Question.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    if (questions.isEmpty) return null;
    final answers = <String, GivenAnswer>{};
    final rawAnswers = raw['answers'];
    if (rawAnswers is Map) {
      rawAnswers.forEach((k, v) {
        if (v is Map) {
          answers['$k'] = GivenAnswer.fromJson(Map<String, dynamic>.from(v));
        }
      });
    }
    // The course comes off the questions themselves. Without it the
    // header reads as a blank strip and an offline round looks like a
    // broken one.
    final code = questions
        .map((q) => q.courseCode)
        .firstWhere((c) => c.isNotEmpty, orElse: () => '');

    return AttemptSession(
      id: id,
      mode: AttemptMode.practice,
      status: '${raw['status'] ?? 'in_progress'}',
      questions: questions,
      answers: answers,
      title: 'Offline practice',
      courseCode: code,
      courseTitle: 'Saved on this phone',
      courseId: '${raw['course_id'] ?? ''}',
    );
  }

  /// Marks an answer on the device, using the key that came down with
  /// the question. Same comparison the server does.
  Future<AnswerVerdict> answerOffline(
    String attemptId,
    String questionId, {
    String choice = '',
    String answerText = '',
  }) async {
    final store = _store;
    if (store == null) throw const BxError('That round is no longer here.');
    final raw = await store.attempt(attemptId);
    if (raw == null) throw const BxError('That round is no longer here.');

    final row = (raw['questions'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .firstWhere((e) => '${e['id']}' == questionId,
            orElse: () => <String, dynamic>{});
    if (row.isEmpty) throw const BxError('That question is not in this round.');

    final q = Question.fromJson(row);
    final correct = gradeLocally(q, choice: choice, answerText: answerText);

    final answers = Map<String, dynamic>.from(
        (raw['answers'] as Map?)?.cast<String, dynamic>() ?? {});
    answers[questionId] = {
      'choice': choice,
      'answer_text': answerText,
      'is_correct': correct,
    };
    raw['answers'] = answers;
    await store.putAttempt(attemptId, raw);

    return AnswerVerdict(
      correct: correct,
      correctKey: q.correctKey,
      acceptedAnswer: q.acceptedAnswer.isEmpty ? null : q.acceptedAnswer,
      explanationHtml: q.explanationHtml,
      explanationImageUrl: q.explanationImageUrl,
      explanationAudioUrl: q.explanationAudioUrl,
    );
  }

  Future<void> finishOffline(String attemptId) async {
    final store = _store;
    if (store == null) return;
    final raw = await store.attempt(attemptId);
    if (raw == null) return;
    raw['status'] = 'submitted';
    raw['finished_at'] = DateTime.now().millisecondsSinceEpoch;
    await store.putAttempt(attemptId, raw);
  }

  Future<ResultReview?> offlineResult(String attemptId) async {
    final store = _store;
    if (store == null) return null;
    final raw = await store.attempt(attemptId);
    if (raw == null) return null;
    final answers = (raw['answers'] as Map?) ?? const {};
    final rows = (raw['questions'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    var score = 0;
    final items = <ReviewItem>[];
    for (var i = 0; i < rows.length; i++) {
      final q = Question.fromJson(rows[i]);
      final given = answers[q.id];
      final choice = given is Map ? '${given['choice'] ?? ''}' : '';
      final text = given is Map ? '${given['answer_text'] ?? ''}' : '';
      final ok = given is Map && given['is_correct'] == true;
      if (ok) score += 1;
      items.add(ReviewItem(
        n: i + 1,
        question: q,
        yourKey: choice.isEmpty ? null : choice,
        yourText: text.isEmpty ? null : text,
        isCorrect: ok,
        answered: choice.isNotEmpty || text.trim().isNotEmpty,
      ));
    }

    final title = '${raw['title'] ?? ''}';
    return ResultReview(
      attemptId: attemptId,
      score: score,
      total: rows.length,
      mode: AttemptMode.practice,
      title: title.isEmpty ? 'Offline practice' : title,
      courseId: '${raw['course_id'] ?? ''}',
      items: items,
    );
  }

}

// ============================================================
// ENGAGEMENT — dashboard, leaderboards, games, announcements, AI
// ============================================================

class EngageRepository {
  EngageRepository(this._b, this._store);

  final Backend _b;
  final LocalStore _store;

  Future<DashboardData> dashboard({bool allowCache = true}) async {
    try {
      if (_b.isDirect) {
        final r = await _b.rpc('bx_dashboard');
        await _store.writeJson(BxKeys.cachedDashboard, r);
        return DashboardData.fromJson(r);
      }
      // Legacy needs two calls; the website has no single dashboard route.
      final home = await _b.apiGet('/api/mobile/home2');
      Map<String, dynamic> summary = const {};
      try {
        summary = await _b.apiGet('/api/me/summary');
      } catch (_) {}
      final merged = {...home, ...summary};
      await _store.writeJson(BxKeys.cachedDashboard, merged);
      return DashboardData.fromJson(merged);
    } catch (e) {
      if (allowCache) {
        final cached = await _store.readJson(BxKeys.cachedDashboard);
        if (cached != null) return DashboardData.fromJson(cached);
      }
      rethrow;
    }
  }

  Future<void> touchStreak() async {
    try {
      if (_b.isDirect) {
        await _b.rpc('bx_touch_streak');
      } else {
        await _b.apiSend('/api/streak/touch');
      }
    } catch (_) {}
  }

  Future<({List<LeaderRow> top, LeaderRow me})> leaderboard() async {
    final meId = _b.userId;
    if (_b.isDirect) {
      final r = await _b.rpc('bx_leaderboard');
      final top = ((r['top'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) =>
              LeaderRow.fromJson(Map<String, dynamic>.from(e), meId: meId))
          .toList();
      final me = r['me'] is Map
          ? LeaderRow.fromJson(Map<String, dynamic>.from(r['me']), meId: meId)
          : const LeaderRow(rank: 0, username: '');
      return (top: top, me: me);
    }
    final r = await _b.apiGet('/api/mobile/leaderboard');
    final top = ((r['top'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => LeaderRow.fromJson(Map<String, dynamic>.from(e), meId: meId))
        .toList();
    final me = r['me'] is Map
        ? LeaderRow.fromJson(Map<String, dynamic>.from(r['me']), meId: meId)
        : const LeaderRow(rank: 0, username: '');
    return (top: top, me: me);
  }

  Future<List<TestRanking>> testRankings(String testId) async {
    final meId = _b.userId;
    if (_b.isDirect) {
      final rows =
          await _b.rpcList('bx_test_rankings', params: {'p_test_id': testId});
      return rows.map((e) => TestRanking.fromJson(e, meId: meId)).toList();
    }
    return const [];
  }

  Future<({List<LeagueRow> table, List<MillionaireWinner> winners})>
      league() async {
    final meId = _b.userId;
    Map<String, dynamic> r;
    if (_b.isDirect) {
      r = await _b.rpc('bx_league');
    } else {
      r = await _b.apiGet('/api/league');
    }
    final table = ((r['table'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => LeagueRow.fromJson(Map<String, dynamic>.from(e), meId: meId))
        .toList();
    final winners = ((r['winners'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => MillionaireWinner.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return (table: table, winners: winners);
  }

  Future<DailyChallenge?> daily() async {
    try {
      final r = _b.isDirect
          ? await _b.rpc('bx_daily')
          : await _b.apiGet('/api/daily');
      if (r['id'] == null) return null;
      return DailyChallenge.fromJson(_b.shieldDeep(r));
    } catch (_) {
      return null;
    }
  }

  String? dailyAnswerFor(String day) =>
      _store.getString('${BxKeys.dailyAnswerPrefix}$day');

  Future<void> rememberDailyAnswer(String day, String choice) =>
      _store.setString('${BxKeys.dailyAnswerPrefix}$day', choice);

  Future<List<Question>> millionaireDeal(List<String> courseIds) async {
    if (_b.isDirect) {
      final rows = await _b.rpcList('bx_millionaire_deal',
          params: {'p_course_ids': courseIds});
      return rows.map((e) => Question.fromJson(_b.shieldDeep(e))).toList();
    }
    final r = await _b.apiSend('/api/millionaire', body: {'courseIds': courseIds});
    final rows = (r['questions'] as List?) ?? const [];
    return rows
        .whereType<Map>()
        .map((e) =>
            Question.fromJson(_b.shieldDeep(Map<String, dynamic>.from(e))))
        .toList();
  }

  Future<({int sample, Map<String, int> spread})> millionairePoll(
      String questionId) async {
    try {
      final r = _b.isDirect
          ? await _b.rpc('bx_millionaire_poll',
              params: {'p_question_id': questionId})
          : await _b.apiGet('/api/millionaire/poll?qid=$questionId');
      final raw = (r['spread'] as Map?) ?? const {};
      return (
        sample: intOf(r['sample']),
        spread: raw.map((k, v) => MapEntry('$k', intOf(v))),
      );
    } catch (_) {
      return (sample: 0, spread: <String, int>{});
    }
  }

  void millionaireReport(int won, bool crowned) {
    unawaited(() async {
      try {
        if (_b.isDirect) {
          await _b.rpc('bx_millionaire_report',
              params: {'p_won': won, 'p_crowned': crowned});
        } else {
          await _b.apiSend('/api/millionaire',
              method: 'PUT', body: {'won': won, 'crowned': crowned});
        }
      } catch (_) {}
    }());
  }

  Future<List<Announcement>> announcements() async {
    if (_b.isDirect) {
      final rows = await _b.rpcList('bx_announcements');
      return rows.map(Announcement.fromJson).toList();
    }
    final r = await _b.apiGet('/api/mobile/content');
    final rows = (r['announcements'] as List?) ?? const [];
    return rows
        .whereType<Map>()
        .map((e) => Announcement.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> acknowledge(String announcementId) async {
    try {
      if (_b.isDirect) {
        await _b.rpc('bx_ack_announcement', params: {'p_id': announcementId});
      } else {
        await _b.apiSend('/api/announcements/ack',
            body: {'announcementId': announcementId});
      }
    } catch (_) {}
  }

  Future<void> acknowledgeAll() async {
    try {
      if (_b.isDirect) {
        await _b.rpc('bx_ack_all_announcements');
      } else {
        await _b.apiSend('/api/announcements/read-all');
      }
    } catch (_) {}
  }

  /// Bello AI stays on the website: the Gemini key must live server-side,
  /// and this is a handful of calls per session rather than hundreds.
  Future<String> askAi(List<({String role, String text})> messages) async {
    try {
      final r = await _b.apiSend(
        '/api/ai/chat',
        body: {
          'messages':
              messages.map((m) => {'role': m.role, 'text': m.text}).toList(),
        },
        timeout: const Duration(seconds: 60),
      );
      final reply = r['reply']?.toString();
      if (reply != null && reply.isNotEmpty) return reply;
      return r['message']?.toString() ??
          'Bello AI hit a snag. Try again shortly.';
    } on BxError catch (e) {
      return e.code == 'offline'
          ? 'Could not reach Bello AI. Check your connection and retry.'
          : e.message;
    } catch (_) {
      return 'Could not reach Bello AI. Check your connection and retry.';
    }
  }

  Future<({int versionCode, int minVersionCode, String versionName, String notes, String apkUrl})?>
      checkUpdate() async {
    try {
      final r = await _b.apiGet('/api/mobile/version', retries: 0);
      return (
        versionCode: intOf(r['versionCode']),
        minVersionCode: intOf(r['minVersionCode']),
        versionName: '${r['versionName'] ?? ''}',
        notes: '${r['notes'] ?? ''}',
        apkUrl: '${r['apkUrl'] ?? BxConfig.downloadUrl}',
      );
    } catch (_) {
      return null;
    }
  }
}
