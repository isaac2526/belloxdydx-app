import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';

/// ============================================================
/// YOU — IDENTITY, REFERRALS, SETTINGS
///
/// This tab carries a second job. On the website the League, the
/// Millionaire game, My Mistakes, the Offline Vault and the CGPA
/// calculator existed but had no entry in the navigation — students
/// only found them by accident. Here every one of them is a named row
/// under "More", so nothing the platform built stays hidden.
/// ============================================================

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _firstName = TextEditingController();
  final _surname = TextEditingController();
  final _phone = TextEditingController();
  final _matric = TextEditingController();

  bool _saving = false;
  bool _signingOut = false;
  String? _saveError;

  bool _biometric = false;
  bool _bioBusy = false;
  String? _bioNote;

  @override
  void initState() {
    super.initState();
    final p = ref.read(profileProvider);
    _firstName.text = p.firstName;
    _surname.text = p.surname;
    _phone.text = p.phone;
    _matric.text = p.matricNo;
    _biometric = ref.read(localStoreProvider).getBool(BxKeys.biometricOn);
  }

  @override
  void dispose() {
    _firstName.dispose();
    _surname.dispose();
    _phone.dispose();
    _matric.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------- actions

  Future<void> _refresh() => ref.read(sessionProvider.notifier).refreshProfile();

  bool _dirty(Profile p) =>
      _firstName.text.trim() != p.firstName ||
      _surname.text.trim() != p.surname ||
      _phone.text.trim() != p.phone ||
      _matric.text.trim() != p.matricNo;

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();

    final first = _firstName.text.trim();
    final sur = _surname.text.trim();
    if (first.isEmpty || sur.isEmpty) {
      setState(() => _saveError =
          'Your first name and surname both have to be there — they go on your result sheets.');
      return;
    }

    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      await ref.read(authRepoProvider).updateProfile(
            firstName: first,
            surname: sur,
            phone: _phone.text.trim(),
            matric: _matric.text.trim(),
          );
      await ref.read(sessionProvider.notifier).refreshProfile();
      if (!mounted) return;
      setState(() => _saving = false);
      bxToast(context, 'Saved. Your details are up to date.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = e is BxError
            ? e.message
            : 'That did not save. Check your data and try again.';
      });
    }
  }

  Future<void> _copyReferral(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    bxToast(context, 'Code copied. Paste it in your course group chat.');
  }

  Future<void> _shareReferral(String code) async {
    final link = '${BxConfig.siteUrl}/register?ref=$code';
    try {
      await Share.share(
        'Join me on Belloxdydx and smash 100 level. Register with my code $code: $link',
        subject: 'Belloxdydx',
      );
    } catch (_) {
      if (!mounted) return;
      bxToast(context, 'The share sheet did not open. Copy your code instead.',
          error: true);
    }
  }

  Future<void> _openLink(String url) async {
    try {
      final ok =
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (ok || !mounted) return;
      bxToast(context, 'Nothing on this phone could open that link.',
          error: true);
    } catch (_) {
      if (!mounted) return;
      bxToast(context, 'Nothing on this phone could open that link.',
          error: true);
    }
  }

  /// Quick unlock is only offered when the phone can actually do it, and
  /// the student is told plainly when it cannot.
  Future<void> _setBiometric(bool on) async {
    if (_bioBusy) return;
    final store = ref.read(localStoreProvider);

    if (!on) {
      setState(() {
        _biometric = false;
        _bioNote = null;
      });
      await store.setBool(BxKeys.biometricOn, false);
      return;
    }

    setState(() {
      _bioBusy = true;
      _bioNote = null;
    });

    try {
      final auth = LocalAuthentication();
      final supported = await auth.isDeviceSupported();
      if (!supported) {
        if (!mounted) return;
        setState(() {
          _bioBusy = false;
          _biometric = false;
          _bioNote =
              'This device has no fingerprint or face unlock set up, so we will keep asking for your password.';
        });
        return;
      }

      final ok = await auth.authenticate(
        localizedReason: 'Confirm it is you before turning on quick unlock.',
        options: const AuthenticationOptions(stickyAuth: true),
      );
      if (!mounted) return;
      setState(() {
        _bioBusy = false;
        _biometric = ok;
        _bioNote = ok ? null : 'We could not confirm it was you. Nothing changed.';
      });
      await store.setBool(BxKeys.biometricOn, ok);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _bioBusy = false;
        _biometric = false;
        _bioNote =
            'Your device did not let us check that. Quick unlock stays off.';
      });
      await store.setBool(BxKeys.biometricOn, false);
    }
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    final sure = await bxConfirm(
      context,
      title: 'Sign out?',
      message:
          'Your streak, your saved material and your results all stay exactly '
          'where they are. You will just need your password to come back.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (!sure || !mounted) return;
    setState(() => _signingOut = true);
    await ref.read(sessionProvider.notifier).signOut();
    if (mounted) setState(() => _signingOut = false);
  }

  // ---------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final p = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: BxSpace.md,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const BxEyebrow('Your account'),
            const SizedBox(height: 2),
            Text('You', style: BxType.h3(c.ink)),
          ],
        ),
      ),
      body: BxPage(
        onRefresh: _refresh,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _identity(p),
            const SizedBox(height: BxSpace.md),
            _referral(p),
            const SizedBox(height: BxSpace.xl),
            const BxSectionHeader(
              title: 'Your account',
              eyebrow: 'Details',
              subtitle: 'Keep these right — they print on your result sheets.',
            ),
            _accountForm(p),
            const SizedBox(height: BxSpace.xl),
            const BxSectionHeader(
              title: 'More',
              eyebrow: 'Everything else',
              subtitle: 'The corners of Belloxdydx that are easy to miss.',
            ),
            _more(),
            const SizedBox(height: BxSpace.xl),
            const BxSectionHeader(title: 'Settings', eyebrow: 'How it behaves'),
            _settings(),
            const SizedBox(height: BxSpace.xl),
            const BxSectionHeader(title: 'About', eyebrow: 'This app'),
            _about(),
            const SizedBox(height: BxSpace.xl),
            BxButton.danger(
              'Sign out',
              icon: Icons.logout_rounded,
              expand: true,
              loading: _signingOut,
              loadingLabel: 'Signing out…',
              onPressed: _signOut,
            ),
            const SizedBox(height: BxSpace.xl),
            Text(
              BxConfig.brandFooter,
              style: BxType.tiny(c.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------- pieces

  Widget _identity(Profile p) {
    final c = context.bx;
    return BxCard(
      padding: const EdgeInsets.all(BxSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BxAvatar(p.username.isEmpty ? p.fullName : p.username, size: 56),
          const SizedBox(width: BxSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  p.fullName.isEmpty ? 'Your name' : p.fullName,
                  style: BxType.h2(c.ink),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(p.handle, style: BxType.mono(c.muted)),
                if (p.matricNo.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(p.matricNo, style: BxType.mono(c.inkSoft, size: 12)),
                ],
                const SizedBox(height: BxSpace.sm),
                Wrap(
                  spacing: BxSpace.xs,
                  runSpacing: BxSpace.xs,
                  children: [
                    if (p.isActivated)
                      const BxChip('Activated',
                          accent: BxAccent.success,
                          icon: Icons.verified_rounded)
                    else
                      BxChip(
                        'Preview mode',
                        accent: BxAccent.gold,
                        icon: Icons.lock_open_rounded,
                        onTap: () => context.push(Routes.activate),
                      ),
                    BxChip('${p.currentLevel} level',
                        icon: Icons.school_outlined),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _referral(Profile p) {
    final c = context.bx;
    final code = p.referralCode.trim();

    return BxCard(
      accent: BxAccent.gold,
      padding: const EdgeInsets.all(BxSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BxEyebrow('Bring a coursemate'),
          const SizedBox(height: BxSpace.sm),
          if (code.isEmpty)
            Text(
              'Your invite code lands here the moment your account finishes '
              'setting up. Pull down to refresh.',
              style: BxType.small(c.inkSoft),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    code,
                    style: BxType.mono(c.goldDeep, size: 26, weight: 700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => _copyReferral(code),
                  icon: Icon(Icons.copy_rounded, size: 19, color: c.goldDeep),
                  tooltip: 'Copy code',
                ),
              ],
            ),
            const SizedBox(height: BxSpace.xs),
            Text(
              'When a coursemate registers with your code and activates, you '
              'earn ₦${BxConfig.referralRewardNgn} plus '
              '${BxPoints.referralActivated} points on the league table.',
              style: BxType.small(c.inkSoft),
            ),
            const SizedBox(height: BxSpace.md),
            Row(
              children: [
                BxButton(
                  'Share my code',
                  icon: Icons.ios_share_rounded,
                  onPressed: () => _shareReferral(code),
                ),
                const SizedBox(width: BxSpace.xs),
                BxButton.ghost('Copy', onPressed: () => _copyReferral(code)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _accountForm(Profile p) {
    final c = context.bx;
    final dirty = _dirty(p);

    return BxCard(
      padding: const EdgeInsets.all(BxSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BxField(
            label: 'First name',
            controller: _firstName,
            capitalization: TextCapitalization.words,
            autofillHint: AutofillHints.givenName,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: BxSpace.sm),
          BxField(
            label: 'Surname',
            controller: _surname,
            capitalization: TextCapitalization.words,
            autofillHint: AutofillHints.familyName,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: BxSpace.sm),
          BxField(
            label: 'Phone',
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHint: AutofillHints.telephoneNumber,
            helper: 'How Tutor Bello reaches you about your activation.',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: BxSpace.sm),
          BxField(
            label: 'Matric number',
            controller: _matric,
            capitalization: TextCapitalization.characters,
            helper: 'Optional. It appears on the material you open.',
            onChanged: (_) => setState(() {}),
          ),
          if (_saveError != null) ...[
            const SizedBox(height: BxSpace.sm),
            Text(_saveError!, style: BxType.small(c.danger)),
          ],
          const SizedBox(height: BxSpace.md),
          BxButton(
            'Save changes',
            icon: Icons.check_rounded,
            expand: true,
            loading: _saving,
            loadingLabel: 'Saving…',
            onPressed: dirty ? _save : null,
          ),
          const BxDivider(height: BxSpace.xl),
          BxKeyValue('Username', p.handle,
              valueWidget: Text(p.handle, style: BxType.mono(c.ink))),
          BxKeyValue('Email', p.email.isEmpty ? 'Not set' : p.email),
          const SizedBox(height: BxSpace.xs),
          Text(
            'Your username and email are locked to your account. If one of '
            'them is wrong, chat Tutor Bello and he will change it for you.',
            style: BxType.tiny(c.muted),
          ),
        ],
      ),
    );
  }

  Widget _more() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _link(
          icon: Icons.download_done_rounded,
          accent: BxAccent.info,
          title: 'Offline Vault',
          subtitle: 'Everything you saved to read with your data off',
          route: Routes.vault,
        ),
        const SizedBox(height: BxSpace.xs),
        _link(
          icon: Icons.campaign_outlined,
          accent: BxAccent.gold,
          title: 'Announcements',
          subtitle: 'Every notice Tutor Bello has posted',
          route: Routes.announcements,
        ),
        const SizedBox(height: BxSpace.xs),
        _link(
          icon: Icons.error_outline_rounded,
          accent: BxAccent.danger,
          title: 'My Mistakes',
          subtitle: 'The questions you got wrong, waiting to be fixed',
          route: Routes.mistakes,
        ),
        const SizedBox(height: BxSpace.xs),
        _link(
          icon: Icons.military_tech_outlined,
          accent: BxAccent.violet,
          title: 'The League',
          subtitle: 'Points, positions and the millionaire crown',
          route: Routes.league,
        ),
        const SizedBox(height: BxSpace.xs),
        _link(
          icon: Icons.diamond_outlined,
          accent: BxAccent.warning,
          title: 'Millionaire',
          subtitle: 'Fifteen questions, one seat, no lifelines wasted',
          route: Routes.millionaire,
        ),
        const SizedBox(height: BxSpace.xs),
        _link(
          icon: Icons.calculate_outlined,
          accent: BxAccent.success,
          title: 'CGPA Calculator',
          subtitle: 'Work out your GPA and print a clean result sheet',
          route: Routes.cgpa,
        ),
      ],
    );
  }

  Widget _link({
    required IconData icon,
    required BxAccent accent,
    required String title,
    required String subtitle,
    required String route,
  }) {
    return BxListRow(
      title: title,
      subtitle: subtitle,
      leading: _mark(icon, accent),
      onTap: () => context.push(route),
    );
  }

  Widget _mark(IconData icon, BxAccent accent) {
    final c = context.bx;
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.fill(c),
        borderRadius: BorderRadius.circular(BxRadius.sm),
        border: Border.all(color: accent.stroke(c)),
      ),
      child: Icon(icon, size: 17, color: accent.ink(c)),
    );
  }

  Widget _settings() {
    final c = context.bx;
    final mode = ref.watch(themeProvider);

    return BxCard(
      padding: const EdgeInsets.all(BxSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Appearance', style: BxType.bodyStrong(c.ink)),
          const SizedBox(height: 2),
          Text('Dark reads easier at night. System follows your phone.',
              style: BxType.tiny(c.muted)),
          const SizedBox(height: BxSpace.sm),
          BxSegmented<ThemeMode>(
            value: mode,
            options: const [
              BxOption(ThemeMode.system, 'System'),
              BxOption(ThemeMode.light, 'Light'),
              BxOption(ThemeMode.dark, 'Dark'),
            ],
            onChanged: (m) => ref.read(themeProvider.notifier).set(m),
          ),
          const BxDivider(height: BxSpace.xl),
          SwitchListTile.adaptive(
            value: _biometric,
            onChanged: _bioBusy ? null : _setBiometric,
            contentPadding: EdgeInsets.zero,
            title: Text('Biometric unlock', style: BxType.bodyStrong(c.ink)),
            subtitle: Text(
              'Open the app with your fingerprint or face instead of typing '
              'your password.',
              style: BxType.tiny(c.muted),
            ),
            secondary: _mark(Icons.fingerprint_rounded, BxAccent.info),
            activeThumbColor: c.gold,
          ),
          if (_bioNote != null)
            Padding(
              padding: const EdgeInsets.only(top: BxSpace.xxs),
              child: Text(_bioNote!, style: BxType.tiny(c.danger)),
            ),
        ],
      ),
    );
  }

  Widget _about() {
    final c = context.bx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BxCard(
          padding: const EdgeInsets.all(BxSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BxKeyValue(
                'Version',
                '${BxConfig.appVersionName} (${BxConfig.appVersionCode})',
                valueWidget: Text(
                  '${BxConfig.appVersionName} (${BxConfig.appVersionCode})',
                  style: BxType.mono(c.ink),
                ),
              ),
              BxKeyValue(
                'Connection',
                '',
                valueWidget: const Align(
                  alignment: Alignment.centerLeft,
                  child: BackendModePill(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: BxSpace.xs),
        BxListRow(
          title: 'Get help on WhatsApp',
          subtitle: 'Tutor Bello answers account questions himself',
          leading: _mark(Icons.chat_bubble_outline_rounded, BxAccent.success),
          onTap: () => _openLink(BxConfig.waHelp('my account')),
        ),
        const SizedBox(height: BxSpace.xs),
        BxListRow(
          title: 'Support & about',
          subtitle: 'What Belloxdydx is and who built it',
          leading: _mark(Icons.info_outline_rounded, BxAccent.neutral),
          onTap: () => _openLink(BxConfig.supportUrl),
        ),
      ],
    );
  }
}
