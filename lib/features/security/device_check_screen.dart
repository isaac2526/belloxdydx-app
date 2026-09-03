import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models.dart';
import '../../ui/ui.dart';
import '../auth/auth_brand.dart';

/// ============================================================
/// A PHONE THIS ACCOUNT HAS NEVER USED
///
/// The password alone stops nobody who has been given the password.
/// That is the whole shape of the problem here — one student pays, ten
/// friends log in.
///
/// So a phone the account has never been opened on has to prove one
/// more thing: that whoever is holding it can read the account's email.
/// A shared password does not come with a shared inbox.
///
/// What this deliberately is NOT:
///
///   · It is not the account password again. They typed that a moment
///     ago; asking twice proves nothing and teaches nothing but
///     impatience.
///   · It is not a fingerprint. A fingerprint on a phone the account
///     has never seen proves only that somebody enrolled a finger on
///     that phone — which the friend borrowing the login did, on their
///     own phone, last week. Biometrics guard a session that is already
///     established; they cannot establish one.
///   · It is not a wall. If the code cannot be sent — and Supabase's
///     mailer has a real hourly limit — the student is told plainly and
///     given the WhatsApp line, and Tutor Bello can trust the phone
///     from the admin panel.
/// ============================================================

class DeviceCheckScreen extends ConsumerStatefulWidget {
  const DeviceCheckScreen({super.key});

  @override
  ConsumerState<DeviceCheckScreen> createState() => _DeviceCheckScreenState();
}

class _DeviceCheckScreenState extends ConsumerState<DeviceCheckScreen> {
  final _code = TextEditingController();
  bool _sending = false;
  bool _verifying = false;
  bool _sent = false;
  String? _error;
  String? _note;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String get _email => ref.read(sessionProvider).profile?.email ?? '';

  String get _maskedEmail {
    final e = _email;
    final at = e.indexOf('@');
    if (at < 2) return e;
    final head = e.substring(0, at);
    final keep = head.length <= 2 ? head : head.substring(0, 2);
    return '$keep${'•' * (head.length - keep.length)}${e.substring(at)}';
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
      _note = null;
    });
    try {
      await ref.read(authRepoProvider).sendDeviceCode(_email);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _note = 'Code sent. It lands in a minute or so.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is BxError
          ? e.message
          : 'The code could not be sent. Try again in a moment.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verify() async {
    if (_verifying) return;
    final code = _code.text.trim();
    if (code.length < 6) {
      setState(() => _error = 'Enter the six digits from your email.');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final auth = ref.read(authRepoProvider);
      await auth.verifyDeviceCode(_email, code);
      // The session behind this request is now seconds old, which is
      // what the server checks before it will trust the phone.
      final standing = await auth.deviceStanding(verified: true);
      if (!mounted) return;
      if (standing.trusted || standing.indeterminate) {
        await ref.read(sessionProvider.notifier).markDeviceTrusted();
      } else {
        setState(() => _error =
            'That did not go through. Ask for a new code and try again.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error =
          e is BxError ? e.message : 'That code did not match. Try again.');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(BxSpace.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BxAuthBrand(size: 64)),
                  const SizedBox(height: BxSpace.lg),
                  Text('New phone', style: BxType.h1(c.ink)),
                  const SizedBox(height: BxSpace.xs),
                  Text(
                    'This account has not been opened on this phone before. '
                    'Confirm it is you and it will not ask again.',
                    style: BxType.body(c.inkSoft),
                  ),
                  const SizedBox(height: BxSpace.lg),
                  Container(
                    padding: const EdgeInsets.all(BxSpace.sm),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(BxRadius.md),
                      border: Border.all(color: c.line),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.mark_email_read_outlined,
                            size: 18, color: c.goldDeep),
                        const SizedBox(width: BxSpace.sm),
                        Expanded(
                          child: Text(_maskedEmail,
                              style: BxType.smallStrong(c.ink)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: BxSpace.md),
                  if (!_sent)
                    BxButton(
                      'Email me a code',
                      icon: Icons.send_rounded,
                      loading: _sending,
                      loadingLabel: 'Sending…',
                      expand: true,
                      large: true,
                      onPressed: _send,
                    )
                  else ...[
                    BxField(
                      label: 'Six-digit code',
                      controller: _code,
                      keyboardType: TextInputType.number,
                      formatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      hint: '000000',
                      onSubmitted: (_) => _verify(),
                    ),
                    const SizedBox(height: BxSpace.sm),
                    BxButton(
                      'Confirm this phone',
                      icon: Icons.verified_user_outlined,
                      loading: _verifying,
                      loadingLabel: 'Checking…',
                      expand: true,
                      large: true,
                      onPressed: _verify,
                    ),
                    const SizedBox(height: BxSpace.xs),
                    BxButton.ghost(
                      'Send another code',
                      loading: _sending,
                      expand: true,
                      onPressed: _send,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: BxSpace.sm),
                    BxBanner(
                      title: 'Not through yet',
                      message: _error!,
                      icon: Icons.error_outline_rounded,
                      accent: BxAccent.danger,
                    ),
                  ] else if (_note != null) ...[
                    const SizedBox(height: BxSpace.sm),
                    Text(_note!, style: BxType.small(c.muted)),
                  ],
                  const SizedBox(height: BxSpace.lg),
                  Text(
                    'No email coming through? Chat Tutor Bello and he will '
                    'open this phone for you.',
                    style: BxType.tiny(c.muted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: BxSpace.sm),
                  Center(
                    child: TextButton(
                      onPressed: () =>
                          ref.read(sessionProvider.notifier).signOut(),
                      child: Text('Sign out', style: BxType.small(c.muted)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
