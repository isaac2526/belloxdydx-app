import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// ============================================================
/// FAILURES
///
/// Every exception this app can catch turns into one of the faults
/// below, and each fault has exactly one sentence written for it here.
///
/// The rule that makes it safe: **no exception text is ever copied into
/// a message a student reads.** An exception chooses a fault; the fault
/// chooses a sentence. Nothing is interpolated.
///
/// That rule exists because the alternative shipped. Supabase's auth
/// client wraps every network failure as
/// `AuthRetryableFetchException(message: e.toString())` — and because
/// that class extends AuthException, a "no signal" error arrived at the
/// UI dressed as an auth error and was printed verbatim:
///
///   ClientException with SocketException: Failed host lookup:
///   'xxxxxxxx.supabase.co' … uri=https://xxxxxxxx.supabase.co/auth/v1/
///   token?grant_type=password
///
/// A student read that. Hence: classify network faults BEFORE auth
/// faults, and never trust a message just because a library handed it
/// over. `test/failures_test.dart` holds the line.
/// ============================================================

enum BxFault {
  offline,
  serverUnreachable,
  timeout,
  unauthenticated,
  forbidden,
  notActivated,
  frozen,
  deviceLocked,
  timeUp,
  notFound,
  maintenance,
  rateLimited,
  badCredentials,
  emailNotConfirmed,
  weakPassword,
  emailTaken,
  usernameTaken,
  featureMissing,
  outOfSpace,
  server,
  unknown,
}

extension BxFaultCopy on BxFault {
  /// The only sentences a student can be shown for a failure.
  String get message => switch (this) {
        BxFault.offline =>
          'No internet connection. Check your data or Wi-Fi and try again.',
        BxFault.serverUnreachable =>
          'We could not reach Belloxdydx. Try again in a moment.',
        BxFault.timeout => 'That took too long. Try again.',
        BxFault.unauthenticated => 'Your session ended. Sign in again.',
        BxFault.forbidden => 'You do not have access to that.',
        BxFault.notActivated => 'Activate your account to open this.',
        BxFault.frozen => 'Your account is frozen. Chat Tutor Bello.',
        BxFault.deviceLocked =>
          'This account is locked to a different device. Chat Tutor Bello '
              'for a device reset.',
        BxFault.timeUp => 'Time is up.',
        BxFault.notFound => 'We could not find that.',
        BxFault.maintenance =>
          'Belloxdydx is under maintenance. We dey come back soon.',
        BxFault.rateLimited => 'Too many tries. Wait a moment and try again.',
        BxFault.badCredentials =>
          'Wrong username or password. Check and try again.',
        BxFault.emailNotConfirmed =>
          'Your email is not confirmed yet. Chat Tutor Bello.',
        BxFault.weakPassword =>
          'Password: at least 8 characters, letters plus 2 symbols.',
        BxFault.emailTaken =>
          'An account already exists with this email. Try logging in.',
        BxFault.usernameTaken => 'That username was taken. Pick another.',
        BxFault.featureMissing => 'That feature is not available yet.',
        BxFault.outOfSpace =>
          'This phone is out of space. Free some up and try again.',
        BxFault.server => 'Something went wrong on our side. Try again.',
        BxFault.unknown => 'Something went wrong. Please try again.',
      };

  /// The short code screens branch on (an activation gate, a device-lock
  /// card). Faults with no special handling carry none.
  String? get code => switch (this) {
        BxFault.offline || BxFault.serverUnreachable => 'offline',
        BxFault.timeout => 'timeout',
        BxFault.unauthenticated => 'unauthenticated',
        BxFault.forbidden => 'forbidden',
        BxFault.notActivated => 'not_activated',
        BxFault.frozen => 'frozen',
        BxFault.deviceLocked => 'device_locked',
        BxFault.timeUp => 'time_up',
        BxFault.maintenance => 'maintenance',
        BxFault.badCredentials => 'bad_credentials',
        BxFault.emailTaken => 'email_taken',
        BxFault.usernameTaken => 'username_taken',
        BxFault.featureMissing => 'rpc_missing',
        BxFault.outOfSpace => 'out_of_space',
        _ => null,
      };

  BxError get error => BxError(message, code: code);
}

/// Anything a server sent us that looks like machinery rather than a
/// sentence. A message is only ever shown to a student if it survives
/// this — see [safeServerMessage].
final RegExp _machinery = RegExp(
  r'(https?:|://|uri=|\.supabase\.|supabase\.co|PGRST|SQLSTATE|'
  r'Exception|Error:|errno|stack|localhost|127\.0\.0\.1|\bat \w+\.|'
  r'relation |column |constraint |schema cache|service_role|'
  r'eyJ[A-Za-z0-9_-]{6,}|Bearer )',
  caseSensitive: false,
);

/// Admin-authored text — a freeze reason, a maintenance notice — is
/// worth showing. Machine text is not. This is the only door a
/// server-supplied string may come through, and it is deliberately
/// narrow: short, single-line, and free of anything that looks
/// technical.
String? safeServerMessage(Object? raw) {
  if (raw is! String) return null;
  final m = raw.trim();
  if (m.isEmpty || m.length > 160) return null;
  if (m.contains('\n') || m.contains('{') || m.contains('<')) return null;
  if (_machinery.hasMatch(m)) return null;
  return m;
}

/// Turns any thrown object into a fault.
///
/// [hasConnection] lets the caller separate "this phone has no signal"
/// from "our server did not answer" — two different sentences, and the
/// student can only act on one of them. Null means we do not know, and
/// the wording stays neutral.
BxFault classify(Object e, {bool? hasConnection}) {
  // ---- transport first, always ----
  // A network failure often arrives wearing another library's clothes,
  // so this runs before any type check that could mistake it for an
  // auth or database problem.
  if (e is SocketException ||
      e is http.ClientException ||
      e is HandshakeException ||
      e is HttpException) {
    return hasConnection == false ? BxFault.offline : BxFault.serverUnreachable;
  }
  if (e is TimeoutException) return BxFault.timeout;
  if (e is AuthRetryableFetchException) {
    return hasConnection == false ? BxFault.offline : BxFault.serverUnreachable;
  }

  final text = e.toString().toLowerCase();
  if (_looksLikeTransport(text)) {
    return hasConnection == false ? BxFault.offline : BxFault.serverUnreachable;
  }
  if (text.contains('timeout') || text.contains('timed out')) {
    return BxFault.timeout;
  }

  // ---- named business faults, whichever layer raised them ----
  if (text.contains('not_activated')) return BxFault.notActivated;
  if (text.contains('account_frozen') || text.contains('frozen')) {
    return BxFault.frozen;
  }
  if (text.contains('device_locked')) return BxFault.deviceLocked;
  if (text.contains('time_up')) return BxFault.timeUp;

  // ---- database ----
  if (e is PostgrestException) {
    final code = e.code ?? '';
    if (code == 'PGRST202' || text.contains('could not find the function')) {
      return BxFault.featureMissing;
    }
    if (code == '42501' || text.contains('permission denied')) {
      return BxFault.forbidden;
    }
    if (code == 'PGRST301' || code == '401') return BxFault.unauthenticated;
    if (code == 'PGRST116') return BxFault.notFound;
    return BxFault.server;
  }
  if (e is StorageException) return BxFault.server;

  // ---- auth, only once transport has been ruled out ----
  if (e is AuthException) {
    if (text.contains('invalid login') ||
        text.contains('invalid credentials') ||
        text.contains('invalid_grant')) {
      return BxFault.badCredentials;
    }
    if (text.contains('email not confirmed')) return BxFault.emailNotConfirmed;
    if (text.contains('password') &&
        (text.contains('weak') || text.contains('at least'))) {
      return BxFault.weakPassword;
    }
    if (text.contains('already registered') ||
        text.contains('already been registered') ||
        text.contains('user already exists')) {
      return BxFault.emailTaken;
    }
    if (text.contains('rate limit') || text.contains('too many')) {
      return BxFault.rateLimited;
    }
    final status = int.tryParse(e.statusCode ?? '');
    if (status == 401 || status == 403) return BxFault.unauthenticated;
    if (status != null && status >= 500) return BxFault.server;
    return BxFault.unknown;
  }

  // Storage. Only a genuine ENOSPC is reported as "free up space" —
  // the app used to say that for ANY failed save, so a brand new phone
  // with 256 GB free was told to clear room because of an unrelated
  // write error.
  if (e is FileSystemException) {
    final code = e.osError?.errorCode;
    final msg = e.osError?.message.toLowerCase() ?? '';
    if (code == 28 || msg.contains('no space left') || msg.contains('disk full')) {
      return BxFault.outOfSpace;
    }
    return BxFault.server;
  }

  if (e is FormatException) return BxFault.server;
  return BxFault.unknown;
}

bool _looksLikeTransport(String text) =>
    text.contains('socketexception') ||
    text.contains('clientexception') ||
    text.contains('failed host lookup') ||
    text.contains('connection closed') ||
    text.contains('connection refused') ||
    text.contains('connection reset') ||
    text.contains('network is unreachable') ||
    text.contains('software caused connection abort') ||
    text.contains('handshake') ||
    text.contains('failed to fetch') ||
    text.contains('xmlhttprequest');

/// Maps an HTTP status onto a fault. [errorCode] is the server's own
/// short code from the response body, when it sent one.
BxFault faultForStatus(int status, {String? errorCode}) {
  if (errorCode == 'not_activated') return BxFault.notActivated;
  if (errorCode == 'device_locked') return BxFault.deviceLocked;
  if (errorCode == 'time_up') return BxFault.timeUp;
  if (errorCode == 'username_taken') return BxFault.usernameTaken;
  if (errorCode == 'email_taken' || errorCode == 'email_exists') {
    return BxFault.emailTaken;
  }
  return switch (status) {
    401 => BxFault.unauthenticated,
    403 => BxFault.forbidden,
    404 => BxFault.notFound,
    408 => BxFault.timeout,
    409 => BxFault.server,
    423 => BxFault.frozen,
    429 => BxFault.rateLimited,
    503 => BxFault.maintenance,
    _ when status >= 500 => BxFault.server,
    _ => BxFault.unknown,
  };
}
