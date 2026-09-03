import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/models.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';
import 'auth_brand.dart';

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
  BxError? _error;

  /// Which of the three steps the student is on.
  int _step = 0;

  /// Steps the student has tried to leave. Errors appear only for those,
  /// so nothing is red before it has been attempted — and a mistake is
  /// reported next to the two or three fields just filled in rather than
  /// eight fields further down.
  final Set<int> _tried = <int>{};

  static const _stepCount = 3;
  static const _fieldsByStep = <int, List<String>>{
    0: ['surname', 'firstName'],
    1: ['email', 'phone'],
    2: ['username', 'password', 'repeat'],
  };

  static final _toUpper = TextInputFormatter.withFunction(
    (_, next) => next.copyWith(text: next.text.toUpperCase()),
  );
  static final _toLower = TextInputFormatter.withFunction(
    (_, next) => next.copyWith(text: next.text.toLowerCase()),
  );

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
  int _stepOf(String field) {
    for (final e in _fieldsByStep.entries) {
      if (e.value.contains(field)) return e.key;
    }
    return 0;
  }

  /// Shown only once the student has tried to leave that step.
  String? _errorFor(String field) =>
      _tried.contains(_stepOf(field)) ? _validate(field) : null;

  /// The rules themselves, with no regard for what has been attempted.
  String? _validate(String field) {
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

  bool _stepBlocked(int step) =>
      (_fieldsByStep[step] ?? const <String>[])
          .any((f) => _validate(f) != null);

  /// Advances, or submits on the last step. Validation is per step, so a
  /// student is never told about a field they have not reached.
  Future<void> _next() async {
    FocusScope.of(context).unfocus();
    setState(() => _tried.add(_step));
    if (_stepBlocked(_step)) return;

    if (_step < _stepCount - 1) {
      setState(() {
        _step += 1;
        _error = null;
      });
      return;
    }
    await _submit();
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _step -= 1);
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _tried.addAll(List.generate(_stepCount, (i) => i));
      _error = null;
    });

    final firstBad = List.generate(_stepCount, (i) => i)
        .where(_stepBlocked)
        .firstOrNull;
    if (firstBad != null) {
      FocusScope.of(context).unfocus();
      setState(() => _step = firstBad);
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
    final last = _step == _stepCount - 1;

    return Scaffold(
      backgroundColor: c.ground,
      // Back walks the wizard rather than leaving it, so a student who
      // mistypes their email on step two does not lose the name they
      // already entered on step one.
      body: PopScope(
        canPop: _step == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: SafeArea(
          child: Column(
            children: [
              _chrome(c),
              Expanded(
                child: BxPage(
                  padding: const EdgeInsets.fromLTRB(
                      BxSpace.lg, BxSpace.md, BxSpace.lg, BxSpace.lg),
                  child: BxSwitcher(
                    child: KeyedSubtree(
                      key: ValueKey(_step),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_error != null) ...[
                            BxBanner(
                              title: 'Could not create your account',
                              message: _error!.message,
                              icon: Icons.error_outline_rounded,
                              accent: BxAccent.danger,
                            ),
                            const SizedBox(height: BxSpace.md),
                          ],
                          ..._stepBody(c),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _action(c, last),
            ],
          ),
        ),
      ),
    );
  }

  /// Fixed chrome: the mark, then the progress, then nothing else. The
  /// three "Step N · …" eyebrows that used to sit inside the form are
  /// gone — progress belongs here, once.
  Widget _chrome(BxColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          BxSpace.sm, BxSpace.xs, BxSpace.lg, 0),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _busy ? null : _back,
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back',
              ),
              const Spacer(),
              Text('Step ${_step + 1} of $_stepCount',
                  style: BxType.small(c.muted)),
            ],
          ),
          const SizedBox(height: BxSpace.xs),
          const BxAuthBrand(size: 64, showWordmark: true),
          const SizedBox(height: BxSpace.lg),
          Padding(
            padding: const EdgeInsets.only(left: BxSpace.xs),
            child: BxStepBar(step: _step, total: _stepCount),
          ),
        ],
      ),
    );
  }

  /// The primary action is pinned. On a form this long it is the one
  /// control that must never be below the fold.
  Widget _action(BxColors c, bool last) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          BxSpace.lg, BxSpace.sm, BxSpace.lg, BxSpace.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BxButton(
            last ? 'Create my account' : 'Continue',
            icon: last
                ? Icons.check_rounded
                : Icons.arrow_forward_rounded,
            large: true,
            expand: true,
            loading: _busy,
            loadingLabel: 'Setting you up…',
            onPressed: _busy ? null : _next,
          ),
          if (_step == 0) ...[
            const SizedBox(height: BxSpace.xxs),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Already have an account?', style: BxType.small(c.muted)),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => context.pushReplacement(Routes.login),
                  child: Text('Log in', style: BxType.label(c.goldDeep)),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: BxSpace.xs),
            Text(
              last
                  ? 'Creating an account is free. Activation comes after.'
                  : 'Nothing is saved until the last step.',
              textAlign: TextAlign.center,
              style: BxType.tiny(c.muted),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _stepBody(BxColors c) => switch (_step) {
        0 => _stepName(c),
        1 => _stepReach(c),
        _ => _stepLogin(c),
      };

  Widget _heading(BxColors c, String title, String blurb) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: BxType.h2(c.ink)),
          const SizedBox(height: BxSpace.xxs),
          Text(blurb, style: BxType.body(c.muted)),
          const SizedBox(height: BxSpace.lg),
        ],
      );

  List<Widget> _stepName(BxColors c) => [
        _heading(c, 'What should we call you?',
            'This is the name that prints on your result sheets.'),
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
        const SizedBox(height: BxSpace.md),
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
        const SizedBox(height: BxSpace.md),
        BxField(
          label: 'Matric number (optional)',
          controller: _matric,
          hint: '123456',
          enabled: !_busy,
          helper: 'Only if you have it already. It sits on your papers as a '
              'watermark.',
          keyboardType: TextInputType.text,
        ),
      ];

  List<Widget> _stepReach(BxColors c) => [
        _heading(c, 'How does Tutor Bello reach you?',
            'Your activation key and your reset link both come this way.'),
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
        const SizedBox(height: BxSpace.md),
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
          helper: 'The number on WhatsApp — that is where your activation '
              'key lands.',
          error: _errorFor('phone'),
          onChanged: (_) => setState(() {}),
        ),
      ];

  List<Widget> _stepLogin(BxColors c) => [
        _heading(c, 'Choose how you sign in',
            'Pick a username you will remember and a password you will not '
            'share.'),
        BxField(
          label: 'Username',
          controller: _username,
          hint: 'tolu_a',
          enabled: !_busy,
          autofillHint: AutofillHints.newUsername,
          formatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')),
            LengthLimitingTextInputFormatter(20),
            _toLower,
          ],
          helper: _checkHelper,
          error: _check == _NameCheck.taken || _check == _NameCheck.invalid
              ? _checkHelper
              : _errorFor('username'),
          suffix: _checkMark(c),
          onChanged: _onUsernameChanged,
        ),
        const SizedBox(height: BxSpace.md),
        BxPasswordField(
          label: 'Password',
          controller: _password,
          autofillHint: AutofillHints.newPassword,
          error: _errorFor('password'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: BxSpace.md),
        BxPasswordField(
          label: 'Repeat password',
          controller: _repeat,
          hint: 'Type it once more',
          autofillHint: AutofillHints.newPassword,
          error: _errorFor('repeat'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: BxSpace.sm),
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
        const SizedBox(height: BxSpace.md),
        BxField(
          label: 'Referral code (optional)',
          controller: _referral,
          hint: 'ABC1234',
          enabled: !_busy,
          textAlign: TextAlign.start,
          style: BxType.mono(c.ink, size: 15, weight: 600),
          formatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            LengthLimitingTextInputFormatter(7),
            _toUpper,
          ],
          helper: 'A coursemate invited you? Their code earns them '
              '₦${BxConfig.referralRewardNgn} when you activate.',
        ),
        const SizedBox(height: BxSpace.lg),
        const BxBanner(
          title: 'One account, one phone',
          message: 'Your account locks to the first phone you log in on. '
              'That is what keeps one key from spreading round a whole class. '
              'Changed device? Tutor Bello moves the lock in a minute.',
          icon: Icons.phonelink_lock_rounded,
          accent: BxAccent.info,
        ),
      ];

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
