import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/models.dart';
import '../../data/offline/course_downloader.dart';
import '../../data/repositories.dart';
import '../../ui/ui.dart';
import '../shell/app_drawer.dart';
import '../shell/app_shell.dart';

/// ============================================================
/// THE COURSE SHELF
///
/// Every course on the student's level, split the way the timetable
/// splits them — first semester, second semester. One tap gets to the
/// course hub; nothing between the student and the material.
/// ============================================================

class CoursesScreen extends ConsumerStatefulWidget {
  const CoursesScreen({super.key});

  @override
  ConsumerState<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends ConsumerState<CoursesScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  bool _switching = false;

  /// The list is only worth searching once it stops fitting on a screen.
  static const _searchThreshold = 6;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _friendly(Object e) => e is BxError
      ? e.message
      : 'That did not go through. Check your connection and try again.';

  Future<void> _refresh() async {
    final level = ref.read(profileProvider).currentLevel;
    try {
      await ref
          .read(contentRepoProvider)
          .loadContent(level: level, force: true);
      ref.invalidate(contentProvider);
      await ref.read(contentProvider.future);
    } catch (e) {
      if (!mounted) return;
      bxToast(context, _friendly(e), error: true);
    }
  }

  Future<void> _switchLevel(StudyLevel level) async {
    if (_switching) return;
    if (level.code == ref.read(profileProvider).currentLevel) return;
    if (!level.owned) {
      showActivationGate(context, () => context.push(Routes.activate));
      return;
    }

    setState(() => _switching = true);
    try {
      await ref.read(authRepoProvider).setLevel(level.code);
      // The shelf is cached in the repository, so it has to be rebuilt for
      // the new level before the provider reads it again.
      await ref
          .read(contentRepoProvider)
          .loadContent(level: level.code, force: true);
      if (!mounted) return;
      ref.read(sessionProvider.notifier).setLevel(level.code);
      ref.invalidate(contentProvider);
      setState(() => _query = '');
      _search.clear();
    } catch (e) {
      if (!mounted) return;
      bxToast(context, _friendly(e), error: true);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final level = ref.watch(profileProvider).currentLevel;
    final content = ref.watch(contentProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const BxDrawerButton(),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Courses', style: BxType.h3(c.ink)),
            const SizedBox(height: 2),
            BxEyebrow(
              level.isEmpty
                  ? 'Both semesters'
                  : '$level Level · both semesters',
            ),
          ],
        ),
      ),
      body: BxPage(
        onRefresh: _refresh,
        child: BxSwitcher(
          child: content.when(
            loading: () => const Padding(
              key: ValueKey('loading'),
              padding: EdgeInsets.only(top: BxSpace.xs),
              child: BxSkeletonList(count: 6),
            ),
            error: (e, _) => Padding(
              key: const ValueKey('error'),
              padding: const EdgeInsets.only(top: BxSpace.xs),
              child: BxErrorState(
                title: 'Your courses did not load',
                message: _friendly(e),
                onRetry: _refresh,
              ),
            ),
            data: (repo) => _shelf(context, repo, level),
          ),
        ),
      ),
    );
  }

  Widget _shelf(BuildContext context, ContentRepository repo, String level) {
    final all = repo.courses;
    final q = _query.trim().toLowerCase();
    final visible = q.isEmpty
        ? all
        : all
            .where((c) =>
                c.code.toLowerCase().contains(q) ||
                c.title.toLowerCase().contains(q))
            .toList();

    final blocks = <Widget>[
      if (repo.levels.length > 1) _levelSwitcher(context, repo.levels, level),
      if (all.length > _searchThreshold)
        BxSearchField(
          controller: _search,
          hint: 'Search a course code or title',
          onChanged: (v) => setState(() => _query = v),
        ),
    ];

    if (all.isEmpty) {
      blocks.add(
        BxEmptyState(
          icon: Icons.menu_book_rounded,
          title: 'No courses on this level yet',
          message:
              'Tutor Bello is still uploading them. Pull down in a moment and '
              'they will be here.',
          actionLabel: 'Check again',
          onAction: _refresh,
        ),
      );
    } else if (visible.isEmpty) {
      blocks.add(
        BxEmptyState(
          icon: Icons.search_off_rounded,
          title: 'No course matches that',
          message: 'Try the course code on its own, like CHM 101.',
          actionLabel: 'Clear search',
          onAction: () {
            _search.clear();
            setState(() => _query = '');
          },
        ),
      );
    } else {
      final groups = <int, List<Course>>{};
      for (final course in visible) {
        groups.putIfAbsent(course.semester, () => <Course>[]).add(course);
      }
      final semesters = groups.keys.toList()..sort();

      for (final s in semesters) {
        final list = groups[s]!
          ..sort((a, b) {
            final o = a.sortOrder.compareTo(b.sortOrder);
            return o != 0 ? o : a.code.compareTo(b.code);
          });
        blocks.add(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BxSectionHeader(
                title: _semesterLabel(s),
                eyebrow: '${list.length} ${list.length == 1 ? 'course' : 'courses'}',
                padding: const EdgeInsets.only(bottom: BxSpace.sm),
              ),
              for (final course in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: BxSpace.sm),
                  child: _CourseCard(
                    course: course,
                    counts: _countsLine(repo, course.id),
                  ),
                ),
            ],
          ),
        );
      }
    }

    // The key is deliberately free of the filter result: changing it while
    // the student types would rebuild the search field and steal the caret.
    return BxStagger(
      key: ValueKey('shelf-$level'),
      spacing: BxSpace.lg,
      children: blocks,
    );
  }

  Widget _levelSwitcher(
    BuildContext context,
    List<StudyLevel> levels,
    String current,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BxEyebrow('Your level'),
        const SizedBox(height: BxSpace.xs),
        Opacity(
          opacity: _switching ? 0.5 : 1,
          child: Wrap(
            spacing: BxSpace.xs,
            runSpacing: BxSpace.xs,
            children: [
              for (final l in levels)
                BxChip(
                  l.title.isEmpty ? '${l.code} Level' : l.title,
                  selected: l.code == current,
                  icon: l.owned ? null : Icons.lock_outline_rounded,
                  onTap: _switching ? null : () => _switchLevel(l),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _semesterLabel(int semester) => switch (semester) {
        1 => 'First semester',
        2 => 'Second semester',
        _ => 'Semester $semester',
      };

  static String _countsLine(ContentRepository repo, String courseId) {
    final parts = <String>[];
    void add(Set<MaterialKind> kinds, String one, String many) {
      final n = repo.countFor(courseId, kinds);
      if (n > 0) parts.add('$n ${n == 1 ? one : many}');
    }

    add(const {MaterialKind.note}, 'note', 'notes');
    add(const {MaterialKind.slide}, 'slide', 'slides');
    add(const {MaterialKind.video, MaterialKind.series}, 'video', 'videos');
    add(const {MaterialKind.pq}, 'past question', 'past questions');
    return parts.isEmpty ? 'Nothing uploaded yet' : parts.join(' · ');
  }
}

class _CourseCard extends ConsumerWidget {
  final Course course;
  final String counts;

  const _CourseCard({required this.course, required this.counts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.bx;
    // Read, not watched into a download: this row only ever REPORTS.
    // Watching the family here is what puts a live badge on a shelf of
    // twenty courses without any of them costing a request.
    final download = ref.watch(courseDownloadProvider(course.id));
    // When TUTOR BELLO last changed this course. Not when the student
    // downloaded it — that is a different question and nobody asks it.
    final stamp = ref.watch(courseStampsProvider)[course.id];
    return BxCard(
      onTap: () => context.push(Routes.course(Uri.encodeComponent(course.code))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  course.code.toUpperCase(),
                  style: BxType.mono(c.goldDeep, size: 16, weight: 600),
                ),
                const SizedBox(height: BxSpace.xxs),
                Text(
                  course.title,
                  style: BxType.bodyStrong(c.ink),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: BxSpace.xxs),
                Text(counts, style: BxType.tiny(c.muted)),
                if (stamp?.updatedAt != null)
                  Text(
                    'Updated ${DateFormat('d MMM').format(stamp!.updatedAt!)}',
                    style: BxType.tiny(c.muted),
                  ),
                if (download.held || download.isRunning) ...[
                  const SizedBox(height: BxSpace.xs),
                  _offlineChip(download),
                ],
              ],
            ),
          ),
          const SizedBox(width: BxSpace.xs),
          Icon(Icons.chevron_right_rounded, size: 22, color: c.muted),
        ],
      ),
    );
  }

  Widget _offlineChip(CourseDownloadState s) {
    if (s.isRunning) {
      return BxChip(
        s.total > 0 ? 'Downloading ${(s.progress * 100).round()}%'
            : 'Downloading',
        icon: Icons.downloading_rounded,
        dense: true,
      );
    }
    if (s.updateAvailable) {
      // Short on purpose. The full sentence lives on the course itself,
      // where there is room for it; here it shares a row with the
      // course code and title on phones as narrow as 320dp.
      return const BxChip(
        'Update ready',
        accent: BxAccent.warning,
        icon: Icons.sync_problem_rounded,
        dense: true,
      );
    }
    return const BxChip(
      'Works offline',
      accent: BxAccent.success,
      icon: Icons.offline_pin_rounded,
      dense: true,
    );
  }
}
