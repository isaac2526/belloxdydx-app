import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/models.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';

/// ============================================================
/// A SECTION OF ONE COURSE
///
/// Notes, slides, videos or past questions — the same list, the same
/// row, the same rules the website uses (a search box only once there
/// is enough to search).
/// ============================================================

class _SectionSpec {
  final String label;
  final IconData icon;
  final Set<MaterialKind> kinds;

  const _SectionSpec(this.label, this.icon, this.kinds);
}

const _specs = <String, _SectionSpec>{
  'notes': _SectionSpec(
      'Explanatory Notes', Icons.menu_book_rounded, {MaterialKind.note}),
  'slides':
      _SectionSpec('Slides', Icons.slideshow_rounded, {MaterialKind.slide}),
  'videos': _SectionSpec(
    'Videos & Series',
    Icons.play_circle_outline_rounded,
    {MaterialKind.video, MaterialKind.series},
  ),
  'pqs': _SectionSpec(
      'Past Questions', Icons.history_edu_rounded, {MaterialKind.pq}),
};

class SectionScreen extends ConsumerStatefulWidget {
  final String code;
  final String section;

  const SectionScreen({super.key, required this.code, required this.section});

  @override
  ConsumerState<SectionScreen> createState() => _SectionScreenState();
}

class _SectionScreenState extends ConsumerState<SectionScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// The website only shows a search box once a list passes three items.
  static const _searchThreshold = 3;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  _SectionSpec? get _spec => _specs[widget.section.toLowerCase()];

  String _friendly(Object e) => e is BxError
      ? e.message
      : 'That did not load. Check your connection and pull down to try again.';

  Future<void> _refresh() async {
    try {
      await refreshContent(ref);
    } catch (e) {
      if (!mounted) return;
      bxToast(context, _friendly(e), error: true);
    }
  }

  Course? _resolve(List<Course> courses, String code) {
    String squash(String s) =>
        s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    final want = squash(code);
    for (final c in courses) {
      if (squash(c.code) == want) return c;
    }
    return null;
  }

  String _subtitleFor(StudyMaterial m) {
    final parts = <String>[
      if (m.topic.trim().isNotEmpty) m.topic.trim(),
      if (m.durationLabel.trim().isNotEmpty) m.durationLabel.trim(),
      if (m.createdAt != null) DateFormat('d MMM yyyy').format(m.createdAt!),
    ];
    return parts.join(' · ');
  }

  String _destinationFor(StudyMaterial m) => switch (m.kind) {
        MaterialKind.note => Routes.note(m.id),
        MaterialKind.video || MaterialKind.series => Routes.watch(m.id),
        _ => Routes.view(m.id),
      };

  BxAccent _accentFor(MaterialKind kind) => switch (kind) {
        MaterialKind.note => BxAccent.gold,
        MaterialKind.slide => BxAccent.violet,
        MaterialKind.video || MaterialKind.series => BxAccent.info,
        MaterialKind.pq => BxAccent.warning,
        MaterialKind.unknown => BxAccent.neutral,
      };

  IconData _iconFor(MaterialKind kind) => switch (kind) {
        MaterialKind.note => Icons.menu_book_rounded,
        MaterialKind.slide => Icons.slideshow_rounded,
        MaterialKind.video => Icons.play_circle_outline_rounded,
        MaterialKind.series => Icons.playlist_play_rounded,
        MaterialKind.pq => Icons.history_edu_rounded,
        MaterialKind.unknown => Icons.description_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final spec = _spec;
    final content = ref.watch(contentProvider);
    final repo = content.valueOrNull;
    final course =
        repo == null ? null : _resolve(repo.courses, widget.code);
    final activated = ref.watch(profileProvider).isActivated;

    final items = (repo == null || course == null || spec == null)
        ? const <StudyMaterial>[]
        : repo.materialsFor(course.id, spec.kinds);

    final q = _query.trim().toLowerCase();
    final visible = q.isEmpty
        ? items
        : items
            .where((m) =>
                m.title.toLowerCase().contains(q) ||
                _subtitleFor(m).toLowerCase().contains(q))
            .toList();

    return Scaffold(
      appBar: BxAppBar(
        title: spec?.label ?? 'Course materials',
        subtitle: course == null
            ? widget.code.toUpperCase()
            : '${course.code.toUpperCase()} · ${course.title}',
        actions: [
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: BxSpace.xxs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [BxChip('${items.length}', dense: true)],
              ),
            ),
        ],
      ),
      body: BxPage(
        onRefresh: _refresh,
        child: BxSwitcher(
          child: content.when(
            loading: () => const BxSkeletonList(key: ValueKey('loading')),
            error: (e, _) => BxErrorState(
              key: const ValueKey('error'),
              title: 'This section did not load',
              message: _friendly(e),
              onRetry: _refresh,
            ),
            data: (_) => _body(context, spec, course, items, visible, activated),
          ),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    _SectionSpec? spec,
    Course? course,
    List<StudyMaterial> items,
    List<StudyMaterial> visible,
    bool activated,
  ) {
    if (spec == null) {
      return BxEmptyState(
        key: const ValueKey('no-section'),
        icon: Icons.help_outline_rounded,
        title: 'That section does not exist',
        message: 'Open the course and pick a section from there.',
        actionLabel: 'Back to the course',
        onAction: () => context.go(Routes.course(
          Uri.encodeComponent(course?.code ?? widget.code),
        )),
      );
    }

    if (course == null) {
      return BxEmptyState(
        key: const ValueKey('no-course'),
        icon: Icons.search_off_rounded,
        title: 'Course not found',
        message:
            'This course is not on your level right now. Open the shelf and '
            'pick one from there.',
        actionLabel: 'Back to my courses',
        onAction: () => context.go(Routes.courses),
      );
    }

    if (items.isEmpty) {
      return BxEmptyState(
        key: const ValueKey('empty'),
        icon: spec.icon,
        title: 'Nothing here yet',
        message: 'Tutor Bello is loading it.',
        actionLabel: 'Back to the course',
        onAction: () =>
            context.go(Routes.course(Uri.encodeComponent(course.code))),
      );
    }

    // One subtree from here on, so typing in the search box never rebuilds
    // the field itself and never drops the caret.
    return Column(
      key: const ValueKey('list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!activated) ...[
          BxBanner(
            title: 'You are in preview mode',
            message:
                'You can see everything on the shelf. Your key opens it to read.',
            icon: Icons.vpn_key_rounded,
            actionLabel: 'Activate',
            onAction: () => context.push(Routes.activate),
          ),
          const SizedBox(height: BxSpace.md),
        ],
        if (items.length > _searchThreshold) ...[
          _searchField(),
          const SizedBox(height: BxSpace.md),
        ],
        if (visible.isEmpty)
          BxEmptyState(
            icon: Icons.search_off_rounded,
            title: 'Nothing matches that',
            message: 'Try one word from the topic instead.',
            actionLabel: 'Clear search',
            onAction: () {
              _search.clear();
              setState(() => _query = '');
            },
          )
        else
          for (final m in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: BxSpace.sm),
              child: BxListRow(
                title: m.title,
                subtitle: _subtitleFor(m),
                locked: !activated,
                leading: _mark(context, m.kind),
                onTap: activated
                    ? () => context.push(_destinationFor(m))
                    : () => showActivationGate(
                          context,
                          () => context.push(Routes.activate),
                        ),
              ),
            ),
      ],
    );
  }

  Widget _searchField() => BxSearchField(
        controller: _search,
        hint: 'Search this section',
        onChanged: (v) => setState(() => _query = v),
      );

  Widget _mark(BuildContext context, MaterialKind kind) {
    final c = context.bx;
    final accent = _accentFor(kind);
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.fill(c),
        borderRadius: BorderRadius.circular(BxRadius.sm),
        border: Border.all(color: accent.stroke(c)),
      ),
      child: Icon(_iconFor(kind), size: 19, color: accent.ink(c)),
    );
  }
}
