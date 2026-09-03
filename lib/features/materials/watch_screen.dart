import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/models.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';

/// ============================================================
/// THE VIDEO SCREEN
///
/// YouTube's terms only permit playback through their own player, so
/// this one screen embeds it: the lesson is on YouTube, and hiding that
/// behind a scraped stream would put the channel at risk. It is the
/// player and nothing else — the page around it is Flutter, and the
/// player is never covered, because covering it is exactly what those
/// terms forbid.
/// ============================================================

/// Every shape a Belloxdydx video link has ever arrived in.
final _videoPatterns = <RegExp>[
  RegExp(r'youtu\.be/([A-Za-z0-9_-]{6,})'),
  RegExp(r'youtube\.com/watch\?(?:[^ ]*&)?v=([A-Za-z0-9_-]{6,})'),
  RegExp(r'youtube(?:-nocookie)?\.com/embed/([A-Za-z0-9_-]{6,})'),
  RegExp(r'youtube\.com/shorts/([A-Za-z0-9_-]{6,})'),
  RegExp(r'youtube\.com/live/([A-Za-z0-9_-]{6,})'),
  RegExp(r'youtube\.com/v/([A-Za-z0-9_-]{6,})'),
];

final _listPattern = RegExp(r'[?&]list=([A-Za-z0-9_-]{6,})');
final _bareIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

String? youtubeVideoId(String raw) {
  final url = raw.trim();
  if (url.isEmpty) return null;
  if (_bareIdPattern.hasMatch(url)) return url;
  for (final p in _videoPatterns) {
    final m = p.firstMatch(url);
    if (m != null) return m.group(1);
  }
  return null;
}

String? youtubeListId(String raw) => _listPattern.firstMatch(raw.trim())?.group(1);

class WatchScreen extends ConsumerStatefulWidget {
  final String id;
  const WatchScreen({super.key, required this.id});

  @override
  ConsumerState<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends ConsumerState<WatchScreen> {
  YoutubePlayerController? _controller;
  String? _preparedFor;
  bool _unplayable = false;
  bool _opened = false;

  @override
  void dispose() {
    // The controller owns a webview; closing it releases the platform
    // view and stops audio the moment the student leaves.
    unawaited(_controller?.close());
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(materialProvider(widget.id));
    await ref.read(materialProvider(widget.id).future);
  }

  void _gate() =>
      showActivationGate(context, () => context.push(Routes.activate));

  void _prepare(StudyMaterial m) {
    final videoId = youtubeVideoId(m.url);
    final listId = youtubeListId(m.url);

    if (videoId == null && listId == null) {
      setState(() => _unplayable = true);
      return;
    }

    final controller = YoutubePlayerController(
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        strictRelatedVideos: true,
        playsInline: true,
      ),
    );

    // Cue rather than load: a lesson starts when the student presses
    // play, not when the screen opens on their data.
    if (videoId != null) {
      unawaited(controller.cueVideoById(videoId: videoId));
    } else {
      unawaited(controller.cuePlaylist(
        list: [listId!],
        listType: ListType.playlist,
      ));
    }

    setState(() => _controller = controller);
  }

  Future<void> _openInYouTube(StudyMaterial m) async {
    final videoId = youtubeVideoId(m.url);
    final target = m.url.startsWith('http')
        ? m.url
        : (videoId == null
            ? ''
            : 'https://www.youtube.com/watch?v=$videoId');
    final uri = target.isEmpty ? null : Uri.tryParse(target);
    var ok = false;
    if (uri != null) {
      try {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        ok = false;
      }
    }
    if (!ok && mounted) {
      bxToast(context, 'YouTube would not open on this phone.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(materialProvider(widget.id));
    final activated = ref.watch(profileProvider).isActivated;
    final material = async.valueOrNull;

    final code = material == null
        ? null
        : ref
            .watch(contentProvider)
            .valueOrNull
            ?.courseById(material.courseId)
            ?.code;

    if (material != null && activated && _preparedFor != material.id) {
      _preparedFor = material.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _prepare(material);
      });
    }
    if (material != null && activated && !_opened) {
      _opened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(contentRepoProvider).markOpened(widget.id);
      });
    }

    final controller = _controller;
    if (controller == null || material == null) {
      return Scaffold(
        appBar: BxAppBar(title: material?.title ?? 'Video', subtitle: code),
        body: BxPage(
          onRefresh: _refresh,
          child: _placeholder(async, material, activated),
        ),
      );
    }

    // The scaffold wraps the whole page so the player can take the screen
    // when the student turns the phone.
    return YoutubePlayerScaffold(
      controller: controller,
      aspectRatio: 16 / 9,
      builder: (context, player) => Scaffold(
        appBar: BxAppBar(title: material.title, subtitle: code),
        body: BxPage(
          onRefresh: _refresh,
          child: _content(material, code, player),
        ),
      ),
    );
  }

  Widget _placeholder(
      AsyncValue<StudyMaterial> async, StudyMaterial? material, bool activated) {
    if (material == null) {
      if (async.hasError) {
        final e = async.error;
        return BxErrorState(
          title: 'This video did not open',
          message: e is BxError
              ? e.message
              : 'Check your data or Wi-Fi, then try again.',
          onRetry: _refresh,
        );
      }
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BxSkeleton(height: 200, radius: BxRadius.md),
          SizedBox(height: BxSpace.md),
          BxSkeleton(width: 240, height: 20),
          SizedBox(height: BxSpace.xs),
          BxSkeleton(width: 160, height: 12),
        ],
      );
    }

    if (!activated) {
      return BxEmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'This video opens with activation',
        message: 'Your key opens every video, note, slide and past question '
            'for your level. Small daily reading beats midnight panic.',
        actionLabel: 'Activate my account',
        onAction: _gate,
      );
    }

    if (_unplayable) {
      return BxEmptyState(
        icon: Icons.smart_display_outlined,
        title: 'This one has to open in YouTube',
        message: 'The link on this lesson is not a shape the in-app player '
            'understands, so YouTube itself will take it.',
        actionLabel: 'Open in YouTube',
        onAction: () => _openInYouTube(material),
      );
    }

    return const Padding(
      padding: EdgeInsets.only(top: BxSpace.xxl),
      child: BxThinking(message: 'Getting the lesson ready…'),
    );
  }

  Widget _content(StudyMaterial m, String? code, Widget player) {
    final c = context.bx;
    final meta = [
      if (code != null && code.isNotEmpty) code,
      if (m.topic.isNotEmpty) m.topic,
      if (m.durationLabel.isNotEmpty) m.durationLabel,
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BxRadius.card,
          child: AspectRatio(aspectRatio: 16 / 9, child: player),
        ),
        const SizedBox(height: BxSpace.lg),
        Text(m.title, style: BxType.h2(c.ink)),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: BxSpace.xxs),
          Text(meta, style: BxType.small(c.muted)),
        ],
        const SizedBox(height: BxSpace.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: BxButton.secondary(
            'Open in YouTube',
            icon: Icons.open_in_new_rounded,
            onPressed: () => _openInYouTube(m),
          ),
        ),
        const SizedBox(height: BxSpace.lg),
        const BxDivider(),
        const SizedBox(height: BxSpace.xs),
        Text(
          'Lessons play through YouTube’s own player because that is what '
          'their terms require. Watch here or on YouTube — either way the '
          'view counts for the channel.',
          style: BxType.tiny(c.muted),
        ),
      ],
    );
  }
}
