import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../core/security.dart';
import '../../data/models.dart';
import '../../ui/ui.dart';
import '../auth/auth_brand.dart';

/// ============================================================
/// THE DRAWER
///
/// An ADDITIONAL layer, not a replacement. The six tabs stay exactly
/// where they are and keep doing exactly what they did; the drawer sits
/// beside them and reaches the things a bottom bar with six slots
/// cannot: practice on any course without walking the shelf, the
/// Millionaire, the league, mistakes, announcements, the CGPA
/// calculator, the vault, and the settings that used to be buried in
/// Profile.
///
/// It lives on the SHELL's Scaffold, not on each tab's. Every tab
/// builds its own Scaffold inside the shell, so `Scaffold.of(context)`
/// from inside a tab finds the inner one and would never see a drawer
/// hung on the outer. The shell's key is published through a provider
/// and the hamburger opens it by that key — which is also why the
/// drawer is reachable from an inner screen without every screen having
/// to carry a copy of it.
/// ============================================================

/// The shell's Scaffold, so any screen can open the drawer.
final shellScaffoldKey = Provider<GlobalKey<ScaffoldState>>(
  (_) => GlobalKey<ScaffoldState>(),
);

/// Opens the drawer from anywhere. Returns false when there is no shell
/// on screen — during auth, for instance — so a caller can hide its
/// button rather than offer one that does nothing.
bool openAppDrawer(WidgetRef ref) {
  final state = ref.read(shellScaffoldKey).currentState;
  if (state == null || !state.hasDrawer) {
    debugPrint('[drawer] no shell scaffold to open '
        '(state: ${state == null ? 'null' : 'present'})');
    return false;
  }
  state.openDrawer();
  return true;
}

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.bx;
    final profile = ref.watch(profileProvider);

    // Captured BEFORE anything closes the drawer.
    //
    // The obvious spelling — `Navigator.of(context).pop(); context.push(…)`
    // — reads fine and is wrong: once the drawer has popped, its own
    // element is being torn down, and looking a Navigator or a Router
    // up through it is an ancestor lookup on a deactivated widget. In a
    // debug build that asserts; in a release build it silently resolves
    // to the wrong tree, which is how a bottom sheet ends up parented
    // inside the drawer that opened it and drawn 274 pixels wide.
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    final rootContext = navigator.context;

    void go(String route) {
      navigator.pop();
      router.push(route);
    }

    void goTab(String route) {
      navigator.pop();
      router.go(route);
    }

    return Drawer(
      backgroundColor: c.ground,
      child: SafeArea(
        child: Column(
          children: [
            _Header(profile: profile),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: BxSpace.xs),
                children: [
                  _SectionLabel('Practice'),
                  _Row(
                    icon: Icons.play_circle_outline_rounded,
                    label: 'Practice a course',
                    hint: 'Pick any course and start a round',
                    onTap: () {
                      navigator.pop();
                      showCoursePicker(rootContext, ref);
                    },
                  ),
                  _Row(
                    icon: Icons.track_changes_outlined,
                    label: 'Smart revision',
                    hint: 'The questions you keep getting wrong',
                    onTap: () => goTab(Routes.revision),
                  ),
                  _Row(
                    icon: Icons.error_outline_rounded,
                    label: 'My mistakes',
                    hint: 'Everything you have missed, in one place',
                    onTap: () => go(Routes.mistakes),
                  ),

                  const _Divider(),
                  _SectionLabel('Study'),
                  _Row(
                    icon: Icons.menu_book_outlined,
                    label: 'All courses',
                    onTap: () => goTab(Routes.courses),
                  ),
                  _Row(
                    icon: Icons.download_done_rounded,
                    label: 'Offline Vault',
                    hint: 'Read with your data off',
                    onTap: () => go(Routes.vault),
                  ),
                  _Row(
                    icon: Icons.auto_awesome_outlined,
                    label: 'Bello AI',
                    onTap: () => goTab(Routes.ai),
                  ),

                  const _Divider(),
                  _SectionLabel('Compete'),
                  _Row(
                    icon: Icons.emoji_events_outlined,
                    label: 'Leaderboard',
                    onTap: () => goTab(Routes.ranks),
                  ),
                  _Row(
                    icon: Icons.shield_moon_outlined,
                    label: 'League',
                    onTap: () => go(Routes.league),
                  ),
                  _Row(
                    icon: Icons.diamond_outlined,
                    label: 'Millionaire',
                    hint: 'Fifteen questions, no second chances',
                    onTap: () => go(Routes.millionaire),
                  ),

                  const _Divider(),
                  _SectionLabel('You'),
                  _Row(
                    icon: Icons.campaign_outlined,
                    label: 'Announcements',
                    onTap: () => go(Routes.announcements),
                  ),
                  _Row(
                    icon: Icons.calculate_outlined,
                    label: 'CGPA calculator',
                    onTap: () => go(Routes.cgpa),
                  ),
                  _Row(
                    icon: Icons.person_outline_rounded,
                    label: 'Profile and settings',
                    onTap: () => goTab(Routes.you),
                  ),
                ],
              ),
            ),
            const _Divider(),
            const _Foot(),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  final Profile profile;
  const _Header({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.bx;
    final name = profile.firstName.isEmpty ? 'Student' : profile.firstName;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
          BxSpace.md, BxSpace.md, BxSpace.md, BxSpace.sm),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BxAuthBrand(
            size: 44,
            showWordmark: false,
            align: CrossAxisAlignment.start,
          ),
          const SizedBox(height: BxSpace.sm),
          Text(name, style: BxType.h3(c.ink)),
          Text(
            profile.username.isEmpty ? 'Belloxdydx' : '@${profile.username}',
            style: BxType.tiny(c.muted),
          ),
          const SizedBox(height: BxSpace.xs),
          Wrap(
            spacing: BxSpace.xxs,
            children: [
              BxChip(
                '${profile.currentLevel} level',
                accent: BxAccent.gold,
              ),
              BxChip(
                profile.isActivated ? 'Activated' : 'Not activated',
                accent:
                    profile.isActivated ? BxAccent.success : BxAccent.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Foot extends ConsumerWidget {
  const _Foot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.bx;
    final sync = ref.watch(syncStatusProvider);
    final lock = ref.watch(appLockProvider);

    return Padding(
      padding: const EdgeInsets.all(BxSpace.sm),
      child: Row(
        children: [
          Expanded(
            child: BxButton.secondary(
              sync.isRunning ? 'Syncing…' : 'Sync now',
              icon: Icons.sync_rounded,
              loading: sync.isRunning,
              onPressed: sync.isRunning
                  ? null
                  : () {
                      final level =
                          ref.read(sessionProvider).profile?.currentLevel;
                      ref
                          .read(syncStatusProvider.notifier)
                          .start(now: true, level: level);
                    },
            ),
          ),
          if (lock != BxLockState.unavailable) ...[
            const SizedBox(width: BxSpace.xs),
            IconButton(
              tooltip: 'Lock now',
              onPressed: () {
                Navigator.of(context).pop();
                // Read from the provider, not from `context`, precisely
                // because the drawer is on its way out.
                ref.read(appLockProvider.notifier).lock();
              },
              icon: Icon(Icons.lock_outline_rounded, size: 20, color: c.inkSoft),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            BxSpace.md, BxSpace.sm, BxSpace.md, BxSpace.xxs),
        child: BxEyebrow(text),
      );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: BxSpace.xxs),
        child: Divider(height: 1, color: context.bx.line),
      );
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? hint;
  final VoidCallback onTap;

  const _Row({
    required this.icon,
    required this.label,
    required this.onTap,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return ListTile(
      dense: hint == null,
      leading: Icon(icon, size: 21, color: c.goldDeep),
      title: Text(label, style: BxType.bodyStrong(c.ink)),
      subtitle: hint == null ? null : Text(hint!, style: BxType.tiny(c.muted)),
      onTap: onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Practice → course → go. The shelf a bottom bar has no room for.
///
/// It also offers the offline pool: on a phone with no signal, the
/// server cannot mint an attempt, but the questions already on the
/// device can still be practised.
Future<void> showCoursePicker(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _CoursePicker(),
  );
}

class _CoursePicker extends ConsumerStatefulWidget {
  const _CoursePicker();

  @override
  ConsumerState<_CoursePicker> createState() => _CoursePickerState();
}

class _CoursePickerState extends ConsumerState<_CoursePicker> {
  String? _busy;

  Future<void> _start(Course course) async {
    if (_busy != null) return;
    setState(() => _busy = course.id);
    final assessment = ref.read(assessmentRepoProvider);
    try {
      final id = await assessment.startPractice(course.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      context.push(Routes.practice(id));
    } catch (e) {
      // No signal is not the end of the round. Whatever is already on
      // the phone can still be practised.
      try {
        final id = await assessment.startOfflinePractice(courseId: course.id);
        if (!mounted) return;
        Navigator.of(context).pop();
        context.push(Routes.practice(id));
        return;
      } catch (_) {
        if (!mounted) return;
        bxToast(
          context,
          e is BxError ? e.message : 'Could not start that. Try again.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final content = ref.watch(contentProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: c.ground,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(BxRadius.lg),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: BxSpace.xs),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: c.line,
                borderRadius: BorderRadius.circular(BxRadius.pill),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(BxSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Practice a course', style: BxType.h3(c.ink)),
                  Text('Twenty questions, marked as you go.',
                      style: BxType.tiny(c.muted)),
                ],
              ),
            ),
            Expanded(
              child: content.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: BxSpace.md),
                  child: BxSkeletonList(count: 6),
                ),
                error: (_, __) => Padding(
                  padding: const EdgeInsets.all(BxSpace.md),
                  child: BxErrorState(
                    title: 'The shelf did not open',
                    message: 'Check your connection and pull to refresh.',
                    onRetry: () => ref.invalidate(contentProvider),
                  ),
                ),
                data: (repo) => repo.courses.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(BxSpace.md),
                        child: BxEmptyState(
                          icon: Icons.menu_book_outlined,
                          title: 'No courses yet',
                          message:
                              'Your shelf fills up as Tutor Bello publishes.',
                        ),
                      )
                    : ListView.builder(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(
                            BxSpace.md, 0, BxSpace.md, BxSpace.lg),
                        itemCount: repo.courses.length,
                        itemBuilder: (_, i) {
                          final course = repo.courses[i];
                          return BxListRow(
                            title: course.code,
                            subtitle: course.title,
                            onTap: () => _start(course),
                            trailing: _busy == course.id
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Icon(Icons.chevron_right_rounded,
                                    color: c.muted),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The hamburger, for the six tab screens that build their own AppBar.
///
/// Returns null when there is no shell on screen, so a caller can drop
/// it into `leading:` unconditionally and never end up with a button
/// that opens nothing.
class BxDrawerButton extends ConsumerWidget {
  const BxDrawerButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.menu_rounded),
      tooltip: 'More',
      onPressed: () => openAppDrawer(ref),
    );
  }
}
