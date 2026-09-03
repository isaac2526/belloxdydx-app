import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models.dart';
import '../../data/offline/course_downloader.dart';
import '../../data/offline/offline_store.dart';
import '../../ui/ui.dart';

/// ============================================================
/// THE DOWNLOAD BUTTON
///
/// One per course, and it says the truth at every moment:
///
///   not held yet      "Download CHM 101"  + what it will bring down
///   downloading       a real progress bar, the file being fetched,
///                     and a Stop
///   held and current  "Downloaded" + what is on the phone
///   held and stale    "There's a change in this course" + Update
///   held but partial  what did not land, and Update to fetch only that
///
/// The last two are the point. Before this, the only way a student
/// learned that Tutor Bello had added a question was to open the app on
/// data and hope the background sync had noticed.
/// ============================================================

class CourseDownloadCard extends ConsumerWidget {
  final Course course;
  const CourseDownloadCard({super.key, required this.course});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.bx;
    final state = ref.watch(courseDownloadProvider(course.id));
    final stamp = ref.watch(courseStampsProvider)[course.id];
    final store = ref.watch(offlineStoreProvider);

    if (store == null) return const SizedBox.shrink();

    final running = state.isRunning;
    final stale = state.updateAvailable && state.held;

    return BxCard(
      accent: stale ? BxAccent.warning : BxAccent.gold,
      padding: const EdgeInsets.all(BxSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BxEyebrow('Offline'),
              const Spacer(),
              if (state.held && !running)
                BxChip(
                  stale ? 'Update waiting' : 'On this phone',
                  accent: stale ? BxAccent.warning : BxAccent.success,
                  icon: stale
                      ? Icons.sync_problem_rounded
                      : Icons.offline_pin_rounded,
                  dense: true,
                ),
            ],
          ),
          const SizedBox(height: BxSpace.xs),
          Text(_headline(state), style: BxType.h3(c.ink)),
          const SizedBox(height: BxSpace.xxs),
          Text(
            running ? state.label : _body(state, stamp),
            style: BxType.body(c.inkSoft),
          ),
          if (running) ...[
            const SizedBox(height: BxSpace.md),
            BxProgressBar(state.progress),
            const SizedBox(height: BxSpace.xxs),
            Text(
              state.total > 0
                  ? '${state.done} of ${state.total} · '
                      '${formatBytes(state.bytes)}'
                  : 'Working out what to fetch…',
              style: BxType.tiny(c.muted),
            ),
          ],
          if (!running && state.held) ...[
            const SizedBox(height: BxSpace.xs),
            Text(_held(state), style: BxType.tiny(c.muted)),
          ],
          if (!running && state.message != null) ...[
            const SizedBox(height: BxSpace.xs),
            Text(state.message!, style: BxType.tiny(c.danger)),
          ],
          const SizedBox(height: BxSpace.md),
          if (running)
            BxButton.secondary(
              'Stop',
              icon: Icons.stop_rounded,
              expand: true,
              onPressed: () =>
                  ref.read(courseDownloadProvider(course.id).notifier).cancel(),
            )
          else
            BxButton(
              _action(state),
              icon: state.held && !stale
                  ? Icons.refresh_rounded
                  : Icons.download_rounded,
              kind: state.held && !stale
                  ? BxButtonKind.secondary
                  : BxButtonKind.primary,
              expand: true,
              onPressed: () =>
                  ref.read(courseDownloadProvider(course.id).notifier).start(),
            ),
        ],
      ),
    );
  }

  String _headline(CourseDownloadState s) {
    if (s.isRunning) return 'Downloading ${_code()}';
    if (s.phase == CourseDownloadPhase.cancelled) return 'Download stopped';
    if (s.updateAvailable && s.held) {
      return 'There is a change in ${_code()}';
    }
    if (s.held) return '${_code()} works without data';
    return 'Take ${_code()} offline';
  }

  String _code() => course.code.toUpperCase();

  String _body(CourseDownloadState s, CourseStamp? stamp) {
    if (s.phase == CourseDownloadPhase.cancelled) {
      return 'Nothing was lost. Tap again and it carries on from what is '
          'already on the phone.';
    }
    if (s.updateAvailable && s.held) {
      return 'Tutor Bello has added or changed something here since you last '
          'downloaded it. Update and it is yours offline again.';
    }
    if (s.held) {
      return 'Every note, file, picture and question on this course is on '
          'this phone. Practise with your data off.';
    }
    final bits = <String>[];
    if ((stamp?.materials ?? 0) > 0) {
      bits.add('${stamp!.materials} '
          '${stamp.materials == 1 ? 'material' : 'materials'}');
    }
    if ((stamp?.questions ?? 0) > 0) {
      bits.add('${stamp!.questions} '
          '${stamp.questions == 1 ? 'question' : 'questions'}');
    }
    if (bits.isEmpty) {
      return 'Every note, file, picture and question on this course, saved '
          'to this phone so it works with your data off.';
    }
    return '${bits.join(' and ')}, with every picture and voice note inside '
        'them, saved to this phone.';
  }

  String _held(CourseDownloadState s) {
    final bits = <String>[
      if (s.questions > 0) '${s.questions} questions',
      if (s.materials > 0) '${s.materials} files',
      if (s.assets > 0) '${s.assets} pictures',
      if (s.bytes > 0) formatBytes(s.bytes),
    ];
    if (bits.isEmpty) return 'Saved on this phone.';
    return 'On this phone: ${bits.join(' · ')}';
  }

  String _action(CourseDownloadState s) {
    if (s.updateAvailable && s.held) return 'Download the change';
    if (s.held) return 'Check for anything new';
    return 'Download this course';
  }
}
