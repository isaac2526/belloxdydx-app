import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';
import 'intro_3d.dart';

/// ============================================================
/// CREATE ACCOUNT
///
/// Nine fields, but the student never meets them as a wall: the form is
/// grouped, the username answers back while it is being typed, and the
/// password rules tick themselves off instead of scolding after the
/// fact.
/// ============================================================

enum _NameCheck { idle, checking, free, taken, invalid }

final RegExp _usernameShape = RegExp(r'^[a-z0-9_]{3,20}$');
final RegExp _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _surname = TextEditingController();
  final _firstName = TextEditingController();
  final _matric = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  final _referral = TextEditingController();

  Timer? _debounce;
  _NameCheck _check = _NameCheck.idle;
  bool _busy = false;
  bool _submitted = false;
  BxError? _error;
  late final bool _playIntro;

  static final _toUpper = TextInputFormatter.withFunction(
    (_, next) => next.copyWith(text: next.text.toUpperCase()),
  );
  static final _toLower = TextInputFormatter.withFunction(
    (_, next) => next.copyWith(text: next.text.toLowerCase()),
  );

  @override
  void initState() {
    super.initState();
    final store = ref.read(localStoreProvider);
    _playIntro = !store.getBool(BxKeys.introSeen);
    if (_playIntro) store.setBool(BxKeys.introSeen, true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [
      _surname,
      _firstName,
      _matric,
      _email,
      _phone,
      _username,
      _password,
      _repeat,
      _referral,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---- live password rules ----
  bool get _ruleLength => _password.text.length >= 8;
  bool get _ruleLetters => RegExp(r'[A-Za-z]').hasMatch(_password.text);
  bool get _ruleSymbols =>
      RegExp(r'[^A-Za-z0-9]').allMatches(_password.text).length >= 2;
  bool get _ruleMatch =>
      _password.text.isNotEmpty && _password.text == _repeat.text;
  bool get _passwordReady =>
      _ruleLength && _ruleLetters && _ruleSymbols && _ruleMatch;

  // ---- errors, shown only after the first attempt ----
  String? _errorFor(String field) {
    if (!_submitted) return null;
    switch (field) {
      case 'surname':
        return _surname.text.trim().isEmpty ? 'Enter your surname.' : null;
      case 'firstName':
        return _firstName.text.trim().isEmpty ? 'Enter your first name.' : null;
      case 'email':
        return _emailShape.hasMatch(_email.text.trim())
            ? null
            : 'Enter the email you actually check.';
      case 'phone':
        return _phone.text.trim().length < 10
            ? 'Enter your phone number, 11 digits.'
            : null;
      case 'username':
        if (!_usernameShape.hasMatch(_username.text.trim().toLowerCase())) {
          return '3 to 20 characters: small letters, numbers, underscore.';
        }
        return _check == _NameCheck.taken
            ? 'Taken already. Try another.'
            : null;
      case 'password':
        return _ruleLength && _ruleLetters && _ruleSymbols
            ? null
            : 'At least 8 characters, letters, and 2 symbols.';
      case 'repeat':
        return _ruleMatch ? null : 'The two passwords do not match yet.';
    }
    return null;
  }

  void _onUsernameChanged(String value) {
    _debounce?.cancel();
    final u = value.trim().toLowerCase();

    if (u.isEmpty) {
      setState(() => _check = _NameCheck.idle);
      return;
    }
    if (!_usernameShape.hasMatch(u)) {
      setState(() => _check = _NameCheck.invalid);
      return;
    }

    setState(() => _check = _NameCheck.checking);
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final free = await ref.read(authRepoProvider).isUsernameFree(u);
      if (!mounted) return;
      // A later keystroke may have overtaken this answer.
      if (_username.text.trim().toLowerCase() != u) return;
      setState(() => _check = free ? _NameCheck.free : _NameCheck.taken);
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _submitted = true;
      _error = null;
    });

    final blocked = [
      'surname',
      'firstName',
      'email',
      'phone',
      'username',
      'password',
      'repeat'
    ].any((f) => _errorFor(f) != null);
    if (blocked) {
      FocusScope.of(context).unfocus();
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _busy = true);

    // The router pushes this screen aside the moment the session turns
    // active, so hold the router itself rather than a context that may
    // already be gone.
    final router = GoRouter.of(context);

    try {
      await ref.read(authRepoProvider).signUp(
            surname: _surname.text,
            firstName: _firstName.text,
            email: _email.text,
            phone: _phone.text,
            username: _username.text,
            password: _password.text,
            matric: _matric.text,
            referral: _referral.text,
          );
      await ref.read(sessionProvider.notifier).onSignedIn();
      router.go(Routes.activate);
    } on BxError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = const BxError(
            'Could not create the account. Check your connection and try again.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;

    return Scaffold(
      body: Intro3D(
        play: _playIntro,
        child: SafeArea(
          child: BxPage(
            padding: const EdgeInsets.fromLTRB(
                BxSpace.lg, BxSpace.md, BxSpace.lg, BxSpace.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _RegisterHeader(),
                const SizedBox(height: BxSpace.lg),

                if (_error != null) ...[
                  BxBanner(
                    title: 'Could not create your account',
                    message: _error!.message,
                    icon: Icons.error_outline_rounded,
                    accent: BxAccent.danger,
                  ),
                  const SizedBox(height: BxSpace.md),
                ],

                // ---- who you are ----
                _Group(
                  eyebrow: 'Step 1 · Your name',
                  children: [
                    BxField(
                      label: 'Surname',
                      controller: _surname,
                      hint: 'Adeyemi',
                      enabled: !_busy,
                      capitalization: TextCapitalization.words,
                      autofillHint: AutofillHints.familyName,
                      error: _errorFor('surname'),
                      onChanged: (_) => setState(() {}),
                    ),
                    BxField(
                      label: 'First name',
                      controller: _firstName,
                      hint: 'Tolu',
                      enabled: !_busy,
                      capitalization: TextCapitalization.words,
                      autofillHint: AutofillHints.givenName,
                      error: _errorFor('firstName'),
                      onChanged: (_) => setState(() {}),
                    ),
                    BxField(
                      label: 'Matric number (optional)',
                      controller: _matric,
                      hint: '123456',
                      enabled: !_busy,
                      helper:
                          'Only if you have it already. It sits on your papers '
                          'as a watermark.',
                      keyboardType: TextInputType.text,
                    ),
                  ],
                ),

                // ---- how we reach you ----
                _Group(
                  eyebrow: 'Step 2 · How we reach you',
                  children: [
                    BxField(
                      label: 'Email',
                      controller: _email,
                      hint: 'you@mail.com',
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      autofillHint: AutofillHints.email,
                      formatters: [_toLower],
                      helper: 'Your reset link comes here. Use one you open.',
                      error: _errorFor('email'),
                      onChanged: (_) => setState(() {}),
                    ),
                    BxField(
                      label: 'Phone',
                      controller: _phone,
                      hint: '0801 234 5678',
                      enabled: !_busy,
                      keyboardType: TextInputType.phone,
                      autofillHint: AutofillHints.telephoneNumber,
                      formatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(15),
                      ],
                      helper: 'The number on WhatsApp — that is where your '
                          'activation key lands.',
                      error: _errorFor('phone'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),

                // ---- your login ----
                _Group(
                  eyebrow: 'Step 3 · Your login',
                  children: [
                    BxField(
                      label: 'Username',
                      controller: _username,
                      hint: 'tolu_a',
                      enabled: !_busy,
                      autofillHint: AutofillHints.newUsername,
                      formatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9_]')),
                        LengthLimitingTextInputFormatter(20),
                        _toLower,
                      ],
                      helper: _checkHelper,
                      error: _check == _NameCheck.taken ||
                              _check == _NameCheck.invalid
                          ? _checkHelper
                          : _errorFor('username'),
                      suffix: _checkMark(c),
                      onChanged: _onUsernameChanged,
                    ),
                    BxPasswordField(
                      label: 'Password',
                      controller: _password,
                      autofillHint: AutofillHints.newPassword,
                      error: _errorFor('password'),
                      onChanged: (_) => setState(() {}),
                    ),
                    BxPasswordField(
                      label: 'Repeat password',
                      controller: _repeat,
                      hint: 'Type it once more',
                      autofillHint: AutofillHints.newPassword,
                      error: _errorFor('repeat'),
                      onChanged: (_) => setState(() {}),
                    ),
                    Wrap(
                      spacing: BxSpace.xs,
                      runSpacing: BxSpace.xs,
                      children: [
                        _RuleChip('8+ characters', _ruleLength),
                        _RuleChip('Letters', _ruleLetters),
                        _RuleChip('2 symbols', _ruleSymbols),
                        _RuleChip('Both match', _ruleMatch),
                      ],
                    ),
                    BxField(
                      label: 'Referral code (optional)',
                      controller: _referral,
                      hint: 'ABC1234',
                      enabled: !_busy,
                      textAlign: TextAlign.start,
                      style: BxType.mono(c.ink, size: 15, weight: 600),
                      formatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9]')),
                        LengthLimitingTextInputFormatter(7),
                        _toUpper,
                      ],
                      helper: 'A coursemate invited you? Their code earns them '
                          '₦${BxConfig.referralRewardNgn} when you activate.',
                    ),
                  ],
                ),

                const BxBanner(
                  title: 'One account, one phone',
                  message:
                      'Your account locks to the first phone you log in on. '
                      'That is what keeps one key from spreading round a whole '
                      'class. Changed device? Tutor Bello moves the lock in a '
                      'minute.',
                  icon: Icons.phonelink_lock_rounded,
                  accent: BxAccent.info,
                ),
                const SizedBox(height: BxSpace.lg),

                BxButton(
                  'Create my account',
                  large: true,
                  expand: true,
                  loading: _busy,
                  loadingLabel: 'Setting you up…',
                  onPressed: _submit,
                ),
                const SizedBox(height: BxSpace.sm),
                Text(
                  _passwordReady
                      ? 'Next stop: your activation key.'
                      : 'Creating an account is free. Activation comes after.',
                  textAlign: TextAlign.center,
                  style: BxType.tiny(c.muted),
                ),

                const SizedBox(height: BxSpace.md),
                const BxDivider(height: BxSpace.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Already have an account?',
                        style: BxType.small(c.muted)),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => context.pushReplacement(Routes.login),
                      child: const Text('Log in'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _checkHelper => switch (_check) {
        _NameCheck.idle => 'This is your public name on leaderboards.',
        _NameCheck.checking => 'Checking availability…',
        _NameCheck.free => 'Available. It is yours.',
        _NameCheck.taken => 'Taken already. Try another.',
        _NameCheck.invalid =>
          '3 to 20 characters: small letters, numbers, underscore.',
      };

  Widget? _checkMark(BxColors c) => switch (_check) {
        _NameCheck.idle => null,
        _NameCheck.checking => Padding(
            padding: const EdgeInsets.all(BxSpace.sm + 2),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.gold),
            ),
          ),
        _NameCheck.free =>
          Icon(Icons.check_circle_rounded, size: 19, color: c.success),
        _NameCheck.taken ||
        _NameCheck.invalid =>
          Icon(Icons.cancel_rounded, size: 19, color: c.danger),
      };
}

/// A titled block of fields — the form reads as three short steps
/// instead of one long interrogation.
class _Group extends StatelessWidget {
  final String eyebrow;
  final List<Widget> children;

  const _Group({required this.eyebrow, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BxSpace.md),
      child: BxCard(
        padding: const EdgeInsets.all(BxSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BxEyebrow(eyebrow),
            const SizedBox(height: BxSpace.md),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: BxSpace.md),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _RuleChip extends StatelessWidget {
  final String label;
  final bool met;
  const _RuleChip(this.label, this.met);

  @override
  Widget build(BuildContext context) {
    return BxChip(
      label,
      accent: met ? BxAccent.success : BxAccent.neutral,
      icon: met ? Icons.check_rounded : Icons.circle_outlined,
      dense: true,
    );
  }
}

class _RegisterHeader extends StatelessWidget {
  const _RegisterHeader();

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final canPop = Navigator.of(context).canPop();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canPop)
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
          ),
        const SizedBox(height: BxSpace.xs),
        const BxEyebrow('Join your coursemates'),
        const SizedBox(height: BxSpace.xxs),
        Text('Create your account', style: BxType.h1(c.ink)),
        const SizedBox(height: BxSpace.xxs),
        Text(
          'Two minutes now, then the whole of 100 level opens up.',
          style: BxType.body(c.muted),
        ),
      ],
    );
  }
}
