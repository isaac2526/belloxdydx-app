import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../data/offline/offline_store.dart';
import 'ui.dart';

/// ============================================================
/// VOICE NOTES
///
/// One player, used everywhere a voice note appears: practice, exams,
/// results, mistakes, note attachments, and `<audio>` inside a note body.
///
/// It replaces four near-identical copies that each got the same things
/// wrong:
///
///   · **No offline playback.** Every copy called `setUrl`, so a voice
///     note the app had already downloaded was fetched again — and on a
///     plane, in a lecture hall with no signal, simply did not play.
///     This one asks the offline store first and plays the file from
///     disk when it is there.
///   · **No seeking.** There was a play button and nothing else. You
///     could not skip back five seconds to hear a word again, which is
///     the single thing anyone wants from a voice note.
///   · **No duration.** A student had no idea whether they were about to
///     start a nine-second clip or a nine-minute one.
///   · **Two could play at once.** Each row owned its own player with
///     nothing coordinating them, so opening an explanation while the
///     question audio was running gave you both at the same time. A
///     process-wide handle now stops the previous one.
///   · **A dead network hung the button forever.** `setUrl` has no
///     timeout of its own; an unreachable host left the spinner turning.
///     Loading is bounded, and a failure is recoverable — tap again to
///     retry rather than being locked out for the life of the screen.
/// ============================================================

/// Whoever is currently making noise. Starting a clip stops the last one.
_BxAudioState? _current;

class BxAudio extends StatefulWidget {
  /// The remote URL. May be empty when [localPath] is given.
  final String url;

  /// What the student is about to hear.
  final String label;

  /// Compact draws a single row; expanded adds the scrubber.
  final bool compact;

  const BxAudio({
    super.key,
    required this.url,
    this.label = 'Voice note',
    this.compact = false,
  });

  @override
  State<BxAudio> createState() => _BxAudioState();
}

enum _Stage { idle, loading, ready, failed }

class _BxAudioState extends State<BxAudio> {
  AudioPlayer? _player;
  final _subs = <StreamSubscription<dynamic>>[];

  _Stage _stage = _Stage.idle;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double? _scrubbing;
  bool _fromDisk = false;
  String _failure = '';

  @override
  void dispose() {
    if (identical(_current, this)) _current = null;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    unawaited(_player?.dispose());
    super.dispose();
  }

  /// Where the bytes should come from. A saved copy always wins: it is
  /// instant, it costs nothing, and it works with the radio off.
  Future<({String? path, String? url})> _source() async {
    final local = Offline.pathFor(widget.url);
    if (local != null) {
      try {
        if (await File(local).exists()) return (path: local, url: null);
      } catch (_) {}
    }
    return (path: null, url: widget.url.isEmpty ? null : widget.url);
  }

  Future<bool> _prepare() async {
    if (_player != null && _stage == _Stage.ready) return true;

    setState(() {
      _stage = _Stage.loading;
      _failure = '';
    });

    final src = await _source();
    if (src.path == null && src.url == null) {
      if (mounted) {
        setState(() {
          _stage = _Stage.failed;
          _failure = 'This voice note is missing.';
        });
      }
      return false;
    }

    final player = _player ?? AudioPlayer();
    _player = player;

    // Attached BEFORE the source is set, so a failure that arrives on
    // the stream rather than from the call is caught too. just_audio
    // reports a bad codec and a mid-stream drop this way, and an
    // unhandled error on this stream takes the whole zone down.
    if (_subs.isEmpty) {
      _subs.add(player.playerStateStream.listen(
        (s) {
          if (!mounted) return;
          final finished = s.processingState == ProcessingState.completed;
          setState(() => _playing = s.playing && !finished);
          if (finished) {
            // Rewind so the next tap starts the clip again rather than
            // sitting silently at the end.
            unawaited(player.pause());
            unawaited(player.seek(Duration.zero));
            if (mounted) setState(() => _position = Duration.zero);
          }
        },
        onError: (Object e) => _fail(e),
      ));
      _subs.add(player.positionStream.listen((p) {
        if (mounted && _scrubbing == null) setState(() => _position = p);
      }, onError: (_) {}));
      _subs.add(player.durationStream.listen((d) {
        if (mounted && d != null) setState(() => _duration = d);
      }, onError: (_) {}));
    }

    try {
      final d = src.path != null
          ? await player
              .setFilePath(src.path!)
              .timeout(const Duration(seconds: 20))
          : await player
              .setUrl(src.url!)
              .timeout(const Duration(seconds: 25));
      if (!mounted) return false;
      setState(() {
        _duration = d ?? _duration;
        _fromDisk = src.path != null;
        _stage = _Stage.ready;
      });
      return true;
    } catch (e) {
      // A saved copy that will not open is worse than none: fall back to
      // the network once before giving up.
      if (src.path != null && widget.url.isNotEmpty) {
        try {
          final d = await player
              .setUrl(widget.url)
              .timeout(const Duration(seconds: 25));
          if (!mounted) return false;
          setState(() {
            _duration = d ?? _duration;
            _fromDisk = false;
            _stage = _Stage.ready;
          });
          return true;
        } catch (e2) {
          _fail(e2);
          return false;
        }
      }
      _fail(e);
      return false;
    }
  }

  void _fail(Object e) {
    debugPrint('[audio] ${widget.url}: $e');
    if (!mounted) return;
    setState(() {
      _stage = _Stage.failed;
      _playing = false;
      // Never the exception. A student gets a sentence, and one they can
      // act on.
      _failure = Offline.holds(widget.url)
          ? 'This voice note would not play.'
          : 'This voice note needs data to play.';
    });
  }

  Future<void> _toggle() async {
    if (_stage == _Stage.loading) return;

    final player = _player;
    if (_stage == _Stage.ready && player != null) {
      if (player.playing) {
        await player.pause();
      } else {
        _takeTheFloor();
        unawaited(player.play());
      }
      return;
    }

    // Idle, or a previous attempt failed — try again from the top.
    if (await _prepare()) {
      _takeTheFloor();
      unawaited(_player?.play());
    }
  }

  void _takeTheFloor() {
    final other = _current;
    if (other != null && !identical(other, this)) other._yield();
    _current = this;
  }

  void _yield() {
    unawaited(_player?.pause());
  }

  Future<void> _seekBy(Duration delta) async {
    final p = _player;
    if (p == null || _stage != _Stage.ready) return;
    var target = _position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (_duration > Duration.zero && target > _duration) target = _duration;
    await p.seek(target);
    if (mounted) setState(() => _position = target);
  }

  static String _clock(Duration d) {
    final total = d.inSeconds;
    final m = (total ~/ 60).toString();
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final failed = _stage == _Stage.failed;
    final loading = _stage == _Stage.loading;
    final ready = _stage == _Stage.ready;

    final maxMs = _duration.inMilliseconds;
    final posMs = _position.inMilliseconds.clamp(0, maxMs <= 0 ? 1 : maxMs);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: BxSpace.sm,
        vertical: widget.compact ? BxSpace.xs : BxSpace.sm,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(BxRadius.sm),
        border: Border.all(color: failed ? c.line : c.gold.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Semantics(
                button: true,
                label: _playing ? 'Pause ${widget.label}' : 'Play ${widget.label}',
                child: InkWell(
                  onTap: _toggle,
                  borderRadius: BorderRadius.circular(BxRadius.pill),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: loading
                          ? Padding(
                              padding: const EdgeInsets.all(4),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: c.gold),
                            )
                          : Icon(
                              failed
                                  ? Icons.refresh_rounded
                                  : (_playing
                                      ? Icons.pause_circle_filled_rounded
                                      : Icons.play_circle_fill_rounded),
                              size: 30,
                              color: failed ? c.muted : c.goldDeep,
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: BxSpace.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      failed ? _failure : widget.label,
                      style: BxType.smallStrong(failed ? c.muted : c.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!failed && (ready || _duration > Duration.zero))
                      Text(
                        _duration > Duration.zero
                            ? '${_clock(_position)} / ${_clock(_duration)}'
                            : _clock(_position),
                        style: BxType.tiny(c.muted),
                      )
                    else if (failed)
                      Text('Tap to try again', style: BxType.tiny(c.muted)),
                  ],
                ),
              ),
              if (_fromDisk && !failed)
                Tooltip(
                  message: 'Saved on this phone',
                  child: Icon(Icons.offline_pin_rounded,
                      size: 16, color: c.goldDeep),
                ),
              if (ready && !widget.compact) ...[
                const SizedBox(width: BxSpace.xxs),
                _Nudge(
                  icon: Icons.replay_5_rounded,
                  label: 'Back five seconds',
                  onTap: () => _seekBy(const Duration(seconds: -5)),
                ),
                _Nudge(
                  icon: Icons.forward_10_rounded,
                  label: 'Forward ten seconds',
                  onTap: () => _seekBy(const Duration(seconds: 10)),
                ),
              ],
            ],
          ),
          if (ready && !widget.compact && maxMs > 0)
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                activeTrackColor: c.gold,
                inactiveTrackColor: c.line,
                thumbColor: c.goldDeep,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: (_scrubbing ?? posMs.toDouble())
                    .clamp(0, maxMs.toDouble()),
                max: maxMs.toDouble(),
                onChanged: (v) => setState(() => _scrubbing = v),
                onChangeEnd: (v) async {
                  final target = Duration(milliseconds: v.round());
                  await _player?.seek(target);
                  if (!mounted) return;
                  setState(() {
                    _position = target;
                    _scrubbing = null;
                  });
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Nudge extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Nudge({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BxRadius.pill),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 20, color: c.inkSoft),
        ),
      ),
    );
  }
}
