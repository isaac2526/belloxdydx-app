import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';
import 'auth_brand.dart';
import 'intro_3d.dart';

/// ============================================================
/// LOG IN
///
/// The form rises out of the briefcase the scholar sets down. Two
/// fields, one gold button, and — where it matters — a card above the
/// form that names the exact wall the student hit and the one person
/// who can move it.
/// ============================================================

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _login = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  bool _noticeDismissed = false;
  BxError? _error;
  late final bool _playIntro;

  @override
  void initState() {
    super.initState();
    // The 3D door plays once per install. After that the form is simply
    // there — nobody wants a cutscene between them and their notes.
    final store = ref.read(localStoreProvider);
    _playIntro = !store.getBool(BxKeys.introSeen);
    if (_playIntro) store.setBool(BxKeys.introSeen, true);
  }

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  String get _typedName => _login.text.trim();

  Future<void> _submit() async {
    if (_busy) return;
    final login = _login.text.trim();
    final password = _password.text;

    if (login.isEmpty || password.isEmpty) {
      setState(() => _error =
          const BxError('Enter your username and your password to continue.'));
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authRepoProvider).signIn(login, password);
      // The session becomes active and the router carries the student to
      // the dashboard on its own.
      await ref.read(sessionProvider.notifier).onSignedIn();
      if (!mounted) return;

      // Unless it does not. If the session failed to settle, this screen
      // is the only thing still on the student's phone and the router
      // will leave them right here — so it has to say what happened.
      // Without this a failure at that stage looked exactly like the
      // button doing nothing at all.
      final session = ref.read(sessionProvider);
      if (!session.isSignedIn) {
        setState(() {
          _busy = false;
          _error = BxError(session.message ??
              'You are signed in, but your account did not load. '
                  'Try again in a moment.');
        });
        return;
      }
      setState(() => _busy = false);
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
            'That did not go through. Check your connection and try again.');
      });
    }
  }

  /// Typing clears an ordinary error, but not the device-lock or frozen
  /// cards — those carry the one action that actually helps, and the
  /// student may be reading them while they retype their name.
  void _clearSoftError() {
    if (_error != null && _error!.code == null) setState(() => _error = null);
  }

  Future<void> _openChat(String url) async {
    try {
      final opened =
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        bxToast(context, 'WhatsApp would not open on this phone.', error: true);
      }
    } catch (_) {
      if (mounted) {
        bxToast(context, 'WhatsApp would not open on this phone.', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final sessionNote = ref.watch(sessionProvider).message;
    final showNote =
        sessionNote != null && sessionNote.isNotEmpty && !_noticeDismissed;

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
                // The mark, then the heading. This screen used to carry
                // no logo at all — the second screen of the product
                // showed none of the product.
                const Center(child: BxAuthBrand(size: 64)),
                const SizedBox(height: BxSpace.xl),
                const _AuthHeader(
                  eyebrow: 'Welcome back',
                  title: 'Log in',
                  subtitle:
                      'Pick up exactly where you stopped. Your streak is waiting.',
                ),
                const SizedBox(height: BxSpace.lg),

                // ---- the session-ended note, if the app closed a login ----
                if (showNote) ...[
                  BxBanner(
                    title: 'This session was closed',
                    message: sessionNote,
                    icon: Icons.logout_rounded,
                    onDismiss: () => setState(() => _noticeDismissed = true),
                  ),
                  const SizedBox(height: BxSpace.md),
                ],

                // ---- the walls that need their own card ----
                BxSwitcher(
                  child: _error == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          key: ValueKey(_error!.message),
                          padding: const EdgeInsets.only(bottom: BxSpace.md),
                          child: _errorCard(_error!),
                        ),
                ),

                AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BxField(
                        label: 'Email or username',
                        controller: _login,
                        hint: 'you@mail.com or yourname',
                        keyboardType: TextInputType.emailAddress,
                        autofillHint: AutofillHints.username,
                        enabled: !_busy,
                        onChanged: (_) => _clearSoftError(),
                        prefix: Icon(Icons.alternate_email_rounded,
                            size: 18, color: c.muted),
                      ),
                      const SizedBox(height: BxSpace.md),
                      BxPasswordField(
                        controller: _password,
                        autofillHint: AutofillHints.password,
                        onSubmitted: (_) => _submit(),
                        onChanged: (_) => _clearSoftError(),
                      ),
                    ],
                  ),
                ),

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy ? null : () => context.push(Routes.forgot),
                    child: const Text('Forgot password?'),
                  ),
                ),
                const SizedBox(height: BxSpace.xs),

                BxButton(
                  'Log in',
                  large: true,
                  expand: true,
                  loading: _busy,
                  loadingLabel: 'Checking your details…',
                  onPressed: _submit,
                ),

                const SizedBox(height: BxSpace.lg),
                const BxDivider(height: BxSpace.xs),
                const SizedBox(height: BxSpace.xs),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('New here?', style: BxType.small(c.muted)),
                    TextButton(
                      onPressed:
                          _busy ? null : () => context.push(Routes.register),
                      child: const Text('Create your account'),
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

  Widget _errorCard(BxError e) {
    switch (e.code) {
      case 'device_locked':
        return BxBanner(
          title: 'This account is locked to another phone',
          message:
              'Your account binds to the first phone you log in on. That is '
              'what stops one key from being passed around a whole class. '
              'Tutor Bello can move the lock to this phone for you.',
          icon: Icons.phonelink_lock_rounded,
          accent: BxAccent.danger,
          actionLabel: 'Chat Tutor Bello',
          onAction: () => _openChat(BxConfig.waDeviceReset(_typedName)),
        );
      case 'frozen':
        return BxBanner(
          title: 'Your account is on hold',
          message: '${e.message} Tutor Bello will tell you what to do next.',
          icon: Icons.ac_unit_rounded,
          accent: BxAccent.danger,
          actionLabel: 'Chat Tutor Bello',
          onAction: () => _openChat(BxConfig.waFrozen(_typedName)),
        );
      default:
        return BxBanner(
          title: 'Could not log you in',
          message: e.message,
          icon: Icons.error_outline_rounded,
          accent: BxAccent.danger,
        );
    }
  }
}

/// The small header both auth forms wear: a way back, the eyebrow and
/// the title.
class _AuthHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;

  const _AuthHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

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
        BxEyebrow(eyebrow),
        const SizedBox(height: BxSpace.xxs),
        Text(title, style: BxType.h1(c.ink)),
        const SizedBox(height: BxSpace.xxs),
        Text(subtitle, style: BxType.body(c.muted)),
      ],
    );
  }
}
