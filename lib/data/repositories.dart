import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import 'backend.dart';
import 'local_store.dart';
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
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      throw BxError(
        m.contains('invalid login') || m.contains('invalid credentials')
            ? 'Wrong username or password. Check and try again.'
            : m.contains('email not confirmed')
                ? 'Your email is not confirmed yet. Chat Tutor Bello.'
                : e.message,
      );
    } catch (e) {
      throw _b.isDirect ? BxError.offline : BxError.offline;
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
    } on AuthException catch (e) {
      throw BxError(e.message);
    } catch (_) {
      throw BxError.offline;
    }
  }

  Future<void> updatePassword(String newPassword) async {
    try {
      await _b.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw BxError(e.message);
    }
  }

  Future<Profile> loadProfile({bool force = false}) async {
    if (!force && _cached != null) return _cached!;
    final uid = _b.userId;
    if (uid == null) throw const BxError('Not signed in.');

    try {
      final rows = await _b.select('profiles', eq: {'id': uid}, limit: 1);
      if (rows.isNotEmpty) {
        _cached = Profile.fromJson(rows.first);
        await _store.writeJson(BxKeys.cachedProfile, _cached!.toJson());
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
      await _store.writeJson(BxKeys.cachedProfile, _cached!.toJson());
      return _cached!;
    } catch (_) {
      final cachedRaw = await _store.readJson(BxKeys.cachedProfile);
      if (cachedRaw != null) {
        _cached = Profile.fromJson(cachedRaw);
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
    return Stream<bool>.periodic(const Duration(minutes: 3))
        .asyncMap((_) => _heartbeat())
        .handleError((_) => true);
  }

  Future<bool> _heartbeat() async {
    try {
      await _b.apiGet('/api/auth/heartbeat', retries: 0);
      return true;
    } on BxError catch (e) {
      if (e.code == 'unauthenticated') return false;
      return true; // offline is not a crime
    } catch (_) {
      return true;
    }
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

  /// One bootstrap that fills the course shelf and every material header.
  /// Falls back to the last good copy on disk so the app opens offline.
  Future<void> loadContent({required String level, bool force = false}) async {
    if (!force && _courses.isNotEmpty) return;
    try {
      if (_b.isDirect) {
        final r = await _b.rpc('bx_content', params: {'p_level': level});
        _ingest(r);
        await _store.writeJson(BxKeys.cachedContent, r);
        return;
      }
      final r = await _b.apiGet('/api/mobile/content');
      final shielded = _b.shieldDeep(r) as Map<String, dynamic>;
      _ingest(shielded);
      await _store.writeJson(BxKeys.cachedContent, shielded);
    } catch (e) {
      final cached = await _store.readJson(BxKeys.cachedContent);
      if (cached != null) {
        _ingest(cached);
        return;
      }
      if (_courses.isEmpty) rethrow;
    }
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
    // An offline copy always wins — it is instant and costs nothing.
    final offlineHtml = await _store.readVaultHtml(id);

    try {
      if (_b.isDirect) {
        final r = await _b.rpc('bx_material', params: {'p_id': id});
        if (r['error'] == 'not_activated') throw BxError.notActivated;
        final raw = r['material'] is Map
            ? Map<String, dynamic>.from(r['material'])
            : r;
        return StudyMaterial.fromJson(_b.shieldDeep(raw));
      }
      final r = await _b.apiGet('/api/mobile/material/$id');
      final raw =
          r['material'] is Map ? Map<String, dynamic>.from(r['material']) : r;
      return StudyMaterial.fromJson(_b.shieldDeep(raw));
    } catch (e) {
      if (offlineHtml != null) {
        final header = _materials.where((m) => m.id == id).firstOrNull;
        return StudyMaterial(
          id: id,
          courseId: header?.courseId ?? '',
          kind: header?.kind ?? MaterialKind.note,
          title: header?.title ?? 'Saved note',
          contentHtml: offlineHtml,
        );
      }
      rethrow;
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
  AssessmentRepository(this._b);
  final Backend _b;

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

  Future<String> _start({
    required String mode,
    String? courseId,
    String? testId,
    String? shareCode,
    int count = 20,
  }) async {
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

  Future<AttemptSession> openAttempt(String attemptId) async {
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
    if (_b.isDirect) {
      final r = await _b.rpc('bx_answer', params: {
        'p_attempt_id': attemptId,
        'p_question_id': questionId,
        'p_choice': choice.isEmpty ? null : choice,
        'p_answer_text': answerText.isEmpty ? null : answerText,
      });
      return AnswerVerdict.fromJson(_b.shieldDeep(r));
    }
    final r = await _b.apiSend('/api/practice/answer', body: {
      'attemptId': attemptId,
      'questionId': questionId,
      'choice': choice,
      'answerText': answerText,
    });
    return AnswerVerdict.fromJson(_b.shieldDeep(r));
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
      return AnswerVerdict.fromJson(r);
    }
    final r = await _b.apiSend('/api/cbt/answer', body: {
      'attemptId': attemptId,
      'questionId': questionId,
      'choice': choice,
      'answerText': answerText,
    });
    return AnswerVerdict.fromJson(r);
  }

  Future<void> submit(String attemptId) async {
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
    if (_b.isDirect) {
      await _b.rpc('bx_submit_attempt', params: {'p_attempt_id': attemptId});
      return;
    }
    await _b.apiSend('/api/practice/$attemptId',
        method: 'PATCH', body: {'action': 'finish'});
  }

  Future<ResultReview> result(String attemptId) async {
    if (_b.isDirect) {
      final r =
          await _b.rpc('bx_attempt_result', params: {'p_attempt_id': attemptId});
      if (r['error'] != null) {
        throw const BxError('That result could not be opened.');
      }
      return ResultReview.fromJson(_b.shieldDeep(r));
    }
    final r = await _b.apiGet('/api/mobile/cbt-result/$attemptId');
    return ResultReview.fromJson(_b.shieldDeep(r));
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
    if (_b.isDirect) {
      final rows = await _b.rpcList('bx_mistakes');
      return rows.map((e) => Question.fromJson(_b.shieldDeep(e))).toList();
    }
    final r = await _b.apiGet('/api/mistakes');
    final rows = (r['items'] as List?) ?? const [];
    return rows
        .whereType<Map>()
        .map((e) =>
            Question.fromJson(_b.shieldDeep(Map<String, dynamic>.from(e))))
        .toList();
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
