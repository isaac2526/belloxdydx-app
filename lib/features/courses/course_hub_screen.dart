import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';
import 'course_download_card.dart';

/// ============================================================
/// THE COURSE HUB
///
/// One course, four sections, one practice button and the tests that
/// close the loop. This is where a study session actually starts, so
/// the fastest thing on the screen is the one that makes you think.
/// ============================================================

class _SectionSpec {
  final String slug;
  final String label;
  final String hint;
  final IconData icon;
  final Set<MaterialKind> kinds;
  final BxAccent accent;

  const _SectionSpec({
    required this.slug,
    required this.label,
    required this.hint,
    required this.icon,
    required this.kinds,
    required this.accent,
  });
}

const _sections = <_SectionSpec>[
  _SectionSpec(
    slug: 'notes',
    label: 'Explanatory Notes',
    hint: 'Written simply, with diagrams and voice notes inside.',
    icon: Icons.menu_book_rounded,
    kinds: {MaterialKind.note},
    accent: BxAccent.gold,
  ),
  _SectionSpec(
    slug: 'slides',
    label: 'Slides',
    hint: 'Lecture slides, viewed inside the app.',
    icon: Icons.slideshow_rounded,
    kinds: {MaterialKind.slide},
    accent: BxAccent.violet,
  ),
  _SectionSpec(
    slug: 'videos',
    label: 'Videos & Series',
    hint: 'Tutor Bello on video, playing right here.',
    icon: Icons.play_circle_outline_rounded,
    kinds: {MaterialKind.video, MaterialKind.series},
    accent: BxAccent.info,
  ),
  _SectionSpec(
    slug: 'pqs',
    label: 'Past Questions',
    hint: 'Real past questions, viewed inside the app.',
    icon: Icons.history_edu_rounded,
    kinds: {MaterialKind.pq},
    accent: BxAccent.warning,
  ),
];

class CourseHubScreen extends ConsumerStatefulWidget {
  final String code;
  const CourseHubScreen({super.key, required this.code});

  @override
  ConsumerState<CourseHubScreen> createState() => _CourseHubScreenState();
}

class _CourseHubScreenState extends ConsumerState<CourseHubScreen> {
  final TextEditingController _testSearch = TextEditingController();
  String _testQuery = '';
  bool _startingPractice = false;
  String? _busyTestId;

  @override
  void dispose() {
    _testSearch.dispose();
    super.dispose();
  }

  String _friendly(Object e) => e is BxError
      ? e.message
      : 'That did not go through. Check your connection and try again.';

  bool get _activated => ref.read(profileProvider).isActivated;

  void _gate() =>
      showActivationGate(context, () => context.push(Routes.activate));

  /// Tolerates a course code that arrived with different spacing or case
  /// from a deep link or a shared screenshot.
  Course? _resolve(ContentRepository repo, String code) {
    final direct = repo.courseByCode(code);
    if (direct != null) return direct;
    String squash(String s) =>
        s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    final want = squash(code);
    for (final c in repo.courses) {
      if (squash(c.code) == want) return c;
    }
    return null;
  }

  Future<void> _refresh(String? courseId) async {
    if (courseId != null) ref.invalidate(testsForCourseProvider(courseId));
    try {
      await refreshContent(ref);
    } catch (e) {
      if (!mounted) return;
      bxToast(context, _friendly(e), error: true);
    }
  }

  Future<void> _startPractice(Course course) async {
    if (!_activated) {
      _gate();
      return;
    }
    if (_startingPractice) return;

    setState(() => _startingPractice = true);
    try {
      // Falls back to this phone's own bank when the server cannot be
      // reached — which is the whole reason the Download button below
      // exists.
      final attemptId = await ref
          .read(assessmentRepoProvider)
          .startPracticeOrOffline(course.id);
      if (!mounted) return;
      await context.push(Routes.practice(attemptId));
    } catch (e) {
      if (!mounted) return;
      bxToast(context, _friendly(e), error: true);
    } finally {
      if (mounted) setState(() => _startingPractice = false);
    }
  }

  Future<void> _openTest(Course course, StudyTest test) async {
    if (!_activated) {
      _gate();
      return;
    }
    if (_busyTestId != null) return;

    final resume = test.inProgressAttemptId;
    if (resume != null && resume.isNotEmpty) {
      await context.push(Routes.cbt(resume));
      if (mounted) ref.invalidate(testsForCourseProvider(course.id));
      return;
    }

    setState(() => _busyTestId = test.id);
    try {
      final attemptId =
          await ref.read(assessmentRepoProvider).startTest(test.id);
      if (!mounted) return;
      await context.push(Routes.cbt(attemptId));
      if (mounted) ref.invalidate(testsForCourseProvider(course.id));
    } catch (e) {
      if (!mounted) return;
      bxToast(context, _friendly(e), error: true);
    } finally {
      if (mounted) setState(() => _busyTestId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = ref.watch(contentProvider);

    return content.when(
      loading: () => Scaffold(
        appBar: BxAppBar(title: widget.code.toUpperCase()),
        body: const BxPage(child: BxSkeletonList(count: 4, itemHeight: 96)),
      ),
      error: (e, _) => Scaffold(
        appBar: BxAppBar(title: widget.code.toUpperCase()),
        body: BxPage(
          child: BxErrorState(
            title: 'This course did not load',
            message: _friendly(e),
            onRetry: () => _refresh(null),
          ),
        ),
      ),
      data: (repo) {
        final course = _resolve(repo, widget.code);
        if (course == null) {
          return Scaffold(
            appBar: BxAppBar(title: widget.code.toUpperCase()),
            body: BxPage(
              child: BxEmptyState(
                icon: Icons.search_off_rounded,
                title: 'Course not found',
                message:
                    'This course is not on your level right now. Open the shelf '
                    'and pick one from there.',
                actionLabel: 'Back to my courses',
                onAction: () => context.go(Routes.courses),
              ),
            ),
          );
        }
        return _hub(context, repo, course);
      },
    );
  }

  Widget _hub(BuildContext context, ContentRepository repo, Course course) {
    final activated = ref.watch(profileProvider).isActivated;
    final live = _sections
        .where((s) => repo.countFor(course.id, s.kinds) > 0)
        .toList();

    return Scaffold(
      appBar: BxAppBar(
        title: course.code.toUpperCase(),
        subtitle: course.title,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: BxSpace.xxs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BxChip(_semesterLabel(course.semester), dense: true),
                if (!activated) ...[
                  const SizedBox(width: BxSpace.xxs),
                  const BxChip(
                    'Preview',
                    accent: BxAccent.warning,
                    icon: Icons.lock_outline_rounded,
                    dense: true,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      body: BxPage(
        onRefresh: () => _refresh(course.id),
        child: BxStagger(
          spacing: BxSpace.lg,
          children: [
            if (!activated)
              BxBanner(
                title: 'You are in preview mode',
                message:
                    'The shelf is open so you can see what is here. Your key '
                    'opens every note, video and test on this course.',
                icon: Icons.vpn_key_rounded,
                actionLabel: 'Activate',
                onAction: () => context.push(Routes.activate),
              ),
            _practicePanel(context, course, activated),
            if (activated) CourseDownloadCard(course: course),
            if (live.isNotEmpty)
              _sectionGrid(context, repo, course, live, activated)
            else
              const BxEmptyState(
                icon: Icons.inbox_rounded,
                title: 'No materials yet',
                message:
                    'Tutor Bello is still uploading this course. The questions '
                    'below still work while you wait.',
              ),
            _testsPanel(context, course, activated),
          ],
        ),
      ),
    );
  }

  Widget _practicePanel(BuildContext context, Course course, bool activated) {
    final c = context.bx;
    return BxCard(
      accent: BxAccent.gold,
      padding: const EdgeInsets.all(BxSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BxEyebrow('Practice'),
          const SizedBox(height: BxSpace.xs),
          Text(
            'Questions with instant corrections and explanations.',
            style: BxType.body(c.inkSoft),
          ),
          const SizedBox(height: BxSpace.xxs),
          Text(
            'Small daily reading beats midnight panic.',
            style: BxType.tiny(c.muted),
          ),
          const SizedBox(height: BxSpace.md),
          BxButton(
            activated ? 'Practice 20 questions' : 'Activate to practise',
            icon: activated ? Icons.bolt_rounded : Icons.lock_outline_rounded,
            expand: true,
            loading: _startingPractice,
            loadingLabel: 'Picking your questions…',
            onPressed: () => _startPractice(course),
          ),
        ],
      ),
    );
  }

  Widget _sectionGrid(
    BuildContext context,
    ContentRepository repo,
    Course course,
    List<_SectionSpec> live,
    bool activated,
  ) {
    final rows = <Widget>[];
    for (var i = 0; i < live.length; i += 2) {
      final left = live[i];
      final right = i + 1 < live.length ? live[i + 1] : null;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: BxSpace.sm),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _SectionTile(
                    spec: left,
                    count: repo.countFor(course.id, left.kinds),
                    locked: !activated,
                    onTap: () => _openSection(course, left),
                  ),
                ),
                const SizedBox(width: BxSpace.sm),
                Expanded(
                  child: right == null
                      ? const SizedBox.shrink()
                      : _SectionTile(
                          spec: right,
                          count: repo.countFor(course.id, right.kinds),
                          locked: !activated,
                          onTap: () => _openSection(course, right),
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BxSectionHeader(
          title: 'Study this course',
          eyebrow: 'Sections',
          padding: EdgeInsets.only(bottom: BxSpace.sm),
        ),
        ...rows,
      ],
    );
  }

  void _openSection(Course course, _SectionSpec spec) {
    context.push(
      Routes.section(Uri.encodeComponent(course.code), spec.slug),
    );
  }

  Widget _testsPanel(BuildContext context, Course course, bool activated) {
    final tests = ref.watch(testsForCourseProvider(course.id));

    return tests.when(
      loading: () => const BxSkeletonList(count: 2, itemHeight: 104),
      error: (e, _) => BxErrorState(
        title: 'Tests did not load',
        message: _friendly(e),
        onRetry: () => ref.invalidate(testsForCourseProvider(course.id)),
      ),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();

        final q = _testQuery.trim().toLowerCase();
        final visible = q.isEmpty
            ? list
            : list.where((t) => t.title.toLowerCase().contains(q)).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BxSectionHeader(
              title: 'Tests & exams',
              eyebrow: '${list.length} waiting for you',
              padding: const EdgeInsets.only(bottom: BxSpace.sm),
            ),
            if (list.length > 3) ...[
              BxSearchField(
                controller: _testSearch,
                hint: 'Search a test',
                onChanged: (v) => setState(() => _testQuery = v),
              ),
              const SizedBox(height: BxSpace.sm),
            ],
            if (visible.isEmpty)
              BxEmptyState(
                icon: Icons.search_off_rounded,
                title: 'No test matches that',
                message: 'Try a shorter word from the title.',
                actionLabel: 'Clear search',
                onAction: () {
                  _testSearch.clear();
                  setState(() => _testQuery = '');
                },
              )
            else
              for (final t in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: BxSpace.sm),
                  child: _TestCard(
                    test: t,
                    locked: !activated,
                    busy: _busyTestId == t.id,
                    onPressed: () => _openTest(course, t),
                  ),
                ),
          ],
        );
      },
    );
  }

  static String _semesterLabel(int semester) => switch (semester) {
        1 => 'First semester',
        2 => 'Second semester',
        _ => 'Semester $semester',
      };
}

class _SectionTile extends StatelessWidget {
  final _SectionSpec spec;
  final int count;
  final bool locked;
  final VoidCallback onTap;

  const _SectionTile({
    required this.spec,
    required this.count,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return BxCard(
      onTap: onTap,
      padding: const EdgeInsets.all(BxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: spec.accent.fill(c),
                  borderRadius: BorderRadius.circular(BxRadius.sm),
                  border: Border.all(color: spec.accent.stroke(c)),
                ),
                child: Icon(spec.icon, size: 19, color: spec.accent.ink(c)),
              ),
              const Spacer(),
              if (locked)
                Icon(Icons.lock_outline_rounded, size: 16, color: c.muted)
              else
                BxChip('$count', dense: true),
            ],
          ),
          const SizedBox(height: BxSpace.sm),
          Text(
            spec.label,
            style: BxType.h3(c.ink),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            spec.hint,
            style: BxType.tiny(c.muted),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _TestCard extends StatelessWidget {
  final StudyTest test;
  final bool locked;
  final bool busy;
  final VoidCallback onPressed;

  const _TestCard({
    required this.test,
    required this.locked,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final resume = test.inProgressAttemptId;
    final inProgress = resume != null && resume.isNotEmpty;

    final facts = <String>[
      if (test.durationMinutes > 0) '${test.durationMinutes} min',
      if (test.questionCount > 0) '${test.questionCount} questions',
    ];

    final String label;
    final IconData icon;
    if (locked) {
      label = 'Activate to start';
      icon = Icons.lock_outline_rounded;
    } else if (inProgress) {
      label = 'Continue';
      icon = Icons.play_arrow_rounded;
    } else if (test.bestPercent != null) {
      label = 'Retake';
      icon = Icons.refresh_rounded;
    } else {
      label = 'Start';
      icon = Icons.arrow_forward_rounded;
    }

    return BxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            test.title,
            style: BxType.h3(c.ink),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: BxSpace.xs),
          Wrap(
            spacing: BxSpace.xs,
            runSpacing: BxSpace.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              BxChip(
                test.isExam ? 'Strict CBT exam' : 'Practice-style test',
                accent: test.isExam ? BxAccent.danger : BxAccent.neutral,
                icon: test.isExam
                    ? Icons.shield_outlined
                    : Icons.assignment_outlined,
                dense: true,
              ),
              if (inProgress)
                const BxChip(
                  'In progress',
                  accent: BxAccent.warning,
                  icon: Icons.timelapse_rounded,
                  dense: true,
                ),
              if (test.bestPercent != null)
                Text(
                  'best ${test.bestPercent}%',
                  style: BxType.mono(c.goldDeep, size: 12.5, weight: 600),
                ),
            ],
          ),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: BxSpace.xs),
            Text(facts.join(' · '), style: BxType.small(c.muted)),
          ],
          const SizedBox(height: BxSpace.md),
          Align(
            alignment: Alignment.centerLeft,
            child: BxButton(
              label,
              icon: icon,
              loading: busy,
              loadingLabel: 'Setting it up…',
              kind: locked ? BxButtonKind.secondary : BxButtonKind.primary,
              onPressed: onPressed,
            ),
          ),
        ],
      ),
    );
  }
}
