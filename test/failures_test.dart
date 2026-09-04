import 'dart:async';
import 'dart:io';

import 'package:belloxdydx/data/failures.dart';
import 'package:belloxdydx/data/models.dart' show BxError;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// The guarantee this file exists to enforce: **nothing a student is
/// shown may contain machinery.** Not a hostname, not a URL, not a
/// Postgres code, not a table or column name, not a token, not a stack
/// frame.
///
/// The app shipped once without this. Supabase's auth client reports a
/// dropped connection as an AuthException whose message is the whole
/// failed request, and the sign-in handler printed it — so a student on
/// bad data was shown the project's Supabase URL. Every realistic
/// exception below is fed through classify() and its sentence checked
/// against a blocklist, so that class of leak cannot come back quietly.
void main() {
  anAlreadyClassifiedErrorKeepsItsIdentity();
  // Written out in the shape the libraries actually produce them.
  const supabaseHost = 'ziprpmqnxeylxywmesbb.supabase.co';

  final leaky = <String, Object>{
    'auth wrapping a DNS failure': AuthRetryableFetchException(
      message: "ClientException with SocketException: Failed host lookup: "
          "'$supabaseHost' (OS Error: No address associated with hostname, "
          "errno = 7), uri=https://$supabaseHost/auth/v1/token"
          "?grant_type=password",
    ),
    'auth wrapping a 500 body': AuthException(
      '<!DOCTYPE html><html><body>500 Internal Server Error at '
      'upstream https://$supabaseHost/auth/v1/token</body></html>',
      statusCode: '500',
    ),
    'raw http client failure': http.ClientException(
      'Connection closed before full header was received',
      Uri.parse('https://$supabaseHost/rest/v1/rpc/bx_dashboard'),
    ),
    'socket failure': const SocketException(
      "Failed host lookup: '$supabaseHost'",
    ),
    'timeout': TimeoutException(
      'Future not completed',
      const Duration(seconds: 25),
    ),
    'missing rpc': PostgrestException(
      message: 'Could not find the function public.bx_dashboard(p_level) '
          'in the schema cache',
      code: 'PGRST202',
      details: 'Not Found',
    ),
    'rls refusal': PostgrestException(
      message: 'permission denied for table profiles',
      code: '42501',
    ),
    'constraint violation': PostgrestException(
      message: 'null value in column "user_id" of relation "attempts" '
          'violates not-null constraint',
      code: '23502',
      details: 'Failing row contains (null, 3, 2026-09-02).',
    ),
    'expired jwt': PostgrestException(
      message: 'JWT expired',
      code: 'PGRST301',
    ),
    'a leaked bearer token': Exception(
      'request failed with Authorization: Bearer '
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.abcdefghijklmnop',
    ),
    'a stack trace': StateError(
      'Bad state: No element\n#0  main.<anonymous> (package:belloxdydx/x.dart:12)',
    ),
  };

  // Anything in here appearing in a student-facing sentence is a leak.
  final forbidden = <RegExp>[
    RegExp('supabase', caseSensitive: false),
    RegExp(r'https?:', caseSensitive: false),
    RegExp('uri=', caseSensitive: false),
    RegExp('PGRST'),
    RegExp('errno', caseSensitive: false),
    RegExp('exception', caseSensitive: false),
    RegExp(r'\brelation\b', caseSensitive: false),
    RegExp(r'\bcolumn\b', caseSensitive: false),
    RegExp('schema cache', caseSensitive: false),
    RegExp('bearer', caseSensitive: false),
    RegExp(r'eyJ[A-Za-z0-9_-]{6,}'),
    RegExp('#0'),
    RegExp('<html', caseSensitive: false),
  ];

  group('classify never leaks machinery', () {
    leaky.forEach((name, error) {
      test(name, () {
        for (final connected in <bool?>[true, false, null]) {
          final message = classify(error, hasConnection: connected).message;
          expect(message, isNotEmpty);
          expect(message.contains('\n'), isFalse,
              reason: 'a student-facing sentence is one line');
          for (final pattern in forbidden) {
            expect(pattern.hasMatch(message), isFalse,
                reason: '"$message" leaks ${pattern.pattern} (from $name)');
          }
        }
      });
    });
  });

  group('classify still says the right thing', () {
    test('a dropped connection is reported as connection trouble', () {
      const dropped = SocketException('Failed host lookup');
      expect(classify(dropped, hasConnection: false), BxFault.offline);
      expect(classify(dropped, hasConnection: true), BxFault.serverUnreachable);
    });

    test('auth-shaped network failures are transport, not bad passwords', () {
      // The exact bug: this used to reach the student as a raw URL, and
      // must never be mistaken for a credentials problem either.
      final e = AuthRetryableFetchException(
        message: 'ClientException with SocketException: Failed host lookup',
      );
      expect(classify(e, hasConnection: false), BxFault.offline);
      expect(classify(e), isNot(BxFault.badCredentials));
    });

    test('a genuinely wrong password is still a wrong password', () {
      final e = AuthException('Invalid login credentials', statusCode: '400');
      expect(classify(e), BxFault.badCredentials);
      expect(classify(e).message, contains('Wrong username or password'));
    });

    test('an unconfirmed email keeps its own instruction', () {
      final e = AuthException('Email not confirmed', statusCode: '400');
      expect(classify(e), BxFault.emailNotConfirmed);
    });

    test('a missing rpc reads as a missing feature, not a crash', () {
      final e = PostgrestException(
        message: 'Could not find the function public.bx_daily',
        code: 'PGRST202',
      );
      expect(classify(e), BxFault.featureMissing);
    });

    test('business faults survive whichever layer raised them', () {
      expect(classify(Exception('not_activated')), BxFault.notActivated);
      expect(classify(Exception('device_locked')), BxFault.deviceLocked);
      expect(classify(Exception('time_up')), BxFault.timeUp);
    });

    test('every fault has a sentence and none of them shout', () {
      for (final f in BxFault.values) {
        expect(f.message, isNotEmpty);
        expect(f.message.endsWith('.'), isTrue,
            reason: '${f.name} should read as a sentence');
        expect(f.message, isNot(contains('  ')));
      }
    });
  });

  group('storage failures are classified honestly', () {
    // The app used to tell a student on a brand new 256 GB phone to
    // "free up a little space" because saveToVault returned null for
    // ANY exception and the caller assumed a full disk.
    test('a real out-of-space error says so', () {
      const e = FileSystemException(
        'Cannot write file',
        '/data/user/0/app/vault/x.pdf',
        OSError('No space left on device', 28),
      );
      expect(classify(e), BxFault.outOfSpace);
      expect(classify(e).message, contains('out of space'));
    });

    test('any other write failure does NOT blame the student\'s storage', () {
      const denied = FileSystemException(
        'Cannot open file',
        '/data/user/0/app/vault/x.pdf',
        OSError('Permission denied', 13),
      );
      expect(classify(denied), isNot(BxFault.outOfSpace));
      expect(classify(denied).message, isNot(contains('space')));

      const missing = FileSystemException(
        'Cannot create file',
        '/nope/x.pdf',
        OSError('No such file or directory', 2),
      );
      expect(classify(missing), isNot(BxFault.outOfSpace));
    });

    test('a storage failure still never leaks the path', () {
      const e = FileSystemException(
        'Cannot write',
        '/data/user/0/tech.isaacarinola.belloxdydx/app_flutter/vault/x.pdf',
        OSError('No space left on device', 28),
      );
      expect(classify(e).message, isNot(contains('/data/')));
      expect(classify(e).message, isNot(contains('belloxdydx')));
    });
  });

  group('faultForStatus', () {
    test('maps the statuses the website actually returns', () {
      expect(faultForStatus(401), BxFault.unauthenticated);
      expect(faultForStatus(423), BxFault.frozen);
      expect(faultForStatus(503), BxFault.maintenance);
      expect(faultForStatus(429), BxFault.rateLimited);
      expect(faultForStatus(502), BxFault.server);
    });

    test('a server error code outranks the status', () {
      expect(faultForStatus(403, errorCode: 'not_activated'),
          BxFault.notActivated);
      expect(faultForStatus(409, errorCode: 'device_locked'),
          BxFault.deviceLocked);
    });
  });

  group('safeServerMessage', () {
    test('lets a sentence Tutor Bello wrote through', () {
      expect(safeServerMessage('Your account was frozen for sharing.'),
          'Your account was frozen for sharing.');
    });

    test('blocks anything that looks like machinery', () {
      const blocked = [
        'Failed to fetch https://ziprpmqnxeylxywmesbb.supabase.co/rest/v1',
        'PGRST202: Could not find the function',
        'permission denied for relation profiles',
        'Error: connect ECONNREFUSED 127.0.0.1:54321',
        '{"error":"bad_target"}',
        '<html><body>502</body></html>',
        'line one\nline two',
      ];
      for (final m in blocked) {
        expect(safeServerMessage(m), isNull, reason: 'should block: $m');
      }
    });

    test('blocks anything too long to be a message', () {
      expect(safeServerMessage('x' * 200), isNull);
      expect(safeServerMessage(''), isNull);
      expect(safeServerMessage(null), isNull);
      expect(safeServerMessage(42), isNull);
    });
  });
}

/// ============================================================
/// "SOMETHING WENT WRONG. PLEASE TRY AGAIN."
///
/// The single most useless sentence the app owns, and it was being
/// reached from errors that already knew exactly what had happened.
///
/// BxError is what the data layer throws once it has worked out the
/// answer — "we could not find that", "activate your account", a freeze
/// reason Tutor Bello typed himself. classify() did not recognise the
/// type, so none of its text branches matched and it fell out of the
/// bottom as `unknown`. Every screen that wrapped a repository call in
/// classify() — the course Download button among them — replaced a
/// precise answer with a shrug.
/// ============================================================
void anAlreadyClassifiedErrorKeepsItsIdentity() {
  group('an error that already knows what it is', () {
    test('is not downgraded to "something went wrong"', () {
      const known = BxError('We could not find that.', code: 'not_found');
      expect(classify(known), BxFault.notFound);
      expect(classify(known).message, isNot(contains('Something went wrong')));
    });

    test('keeps its identity for every code the data layer sets', () {
      const cases = <String, BxFault>{
        'not_activated': BxFault.notActivated,
        'frozen': BxFault.frozen,
        'device_locked': BxFault.deviceLocked,
        'offline': BxFault.offline,
        'timeout': BxFault.timeout,
        'maintenance': BxFault.maintenance,
        'out_of_space': BxFault.outOfSpace,
        'rpc_missing': BxFault.featureMissing,
        'not_found': BxFault.notFound,
        'server': BxFault.server,
      };
      cases.forEach((code, fault) {
        expect(classify(BxError('msg', code: code)), fault,
            reason: 'a BxError carrying "$code" must classify as $fault');
      });
    });

    test('every fault the data layer can name survives the round trip', () {
      // The reverse map must not fall behind the forward one. A fault
      // with a code that faultForCode does not know would silently
      // become "something went wrong" all over again.
      for (final f in BxFault.values) {
        final code = f.code;
        if (code == null) continue;
        expect(faultForCode(code), isNotNull,
            reason: '$f has code "$code" but faultForCode cannot read it '
                'back — that is exactly how this bug happened');
      }
    });

    test('a genuinely unknown error is still unknown', () {
      // The fix must not turn every error into a false positive.
      expect(classify(const BxError('mystery')), BxFault.unknown);
      expect(classify(Exception('nothing recognisable here')),
          BxFault.unknown);
    });
  });
}
