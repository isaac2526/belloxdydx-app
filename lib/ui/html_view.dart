import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../data/offline/offline_store.dart';
import 'ui.dart';

/// ============================================================
/// RICH TEXT
///
/// Every question body, explanation, option and note in the app goes
/// through here. It was `HtmlWidget` used bare in thirteen places, and
/// that meant four separate defects, all of them visible to a student:
///
///   1. **`<audio>` rendered as nothing at all.** The core package
///      supports no media elements whatsoever — no `<audio>`, no
///      `<video>`, no `<iframe>`. A voice note embedded in a note body
///      did not fail to play; it was not on the page. Now it becomes a
///      real player.
///
///   2. **Pictures were always fetched from the network.** Even after a
///      sync had put the file on the phone. `imageProviderFromNetwork`
///      is overridden below so a saved picture is drawn from disk, which
///      is what makes an offline question with a diagram actually work.
///
///   3. **A failed picture drew `❌`, or the alt text, or nothing.**
///      That is the package's default, and it is how a raw URL ends up
///      on screen where a diagram should be. It now draws a labelled
///      placeholder in the app's own colours, and says whether the
///      problem is the connection.
///
///   4. **A loading picture collapsed the layout**, so the text jumped
///      when it arrived.
/// ============================================================

class BxHtml extends StatelessWidget {
  final String html;
  final TextStyle? textStyle;

  /// Renders `<audio>` as a player. Off inside an option chip, where
  /// there is no room and no such markup.
  final bool media;

  /// Handles a tapped link. Returning true means it was dealt with.
  final FutureOr<bool> Function(String url)? onTapUrl;

  const BxHtml(
    this.html, {
    super.key,
    this.textStyle,
    this.media = true,
    this.onTapUrl,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return HtmlWidget(
      html,
      textStyle: textStyle,
      onTapUrl: onTapUrl,
      factoryBuilder: () => _BxWidgetFactory(),
      customWidgetBuilder: media ? (element) => _custom(element, c) : null,
      onLoadingBuilder: (_, __, ___) => _Placeholder(
        colors: c,
        icon: Icons.image_outlined,
        label: 'Loading picture…',
        busy: true,
      ),
      onErrorBuilder: (_, __, ___) => _Placeholder(
        colors: c,
        icon: Icons.image_not_supported_outlined,
        label: 'Picture could not load',
        hint: 'Open this once with data and it saves for offline.',
      ),
    );
  }

  Widget? _custom(dynamic element, BxColors c) {
    final tag = '${element.localName ?? ''}'.toLowerCase();

    if (tag == 'audio') {
      final src = _srcOf(element);
      if (src.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: BxSpace.xs),
        child: BxAudio(url: src, label: _labelOf(element, 'Voice note')),
      );
    }

    // Video and embeds are not playable inside a note body. Rather than
    // rendering nothing — which is what happened before, leaving a
    // silent hole in the middle of a lesson — say so.
    if (tag == 'video' || tag == 'iframe' || tag == 'embed') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: BxSpace.xs),
        child: _Placeholder(
          colors: c,
          icon: Icons.smart_display_outlined,
          label: 'Video',
          hint: 'Open this material from the Watch tab to play it.',
        ),
      );
    }

    return null;
  }

  static String _srcOf(dynamic element) {
    final direct = '${element.attributes['src'] ?? ''}';
    if (direct.isNotEmpty) return direct;
    // <audio><source src="…"></audio>
    try {
      for (final child in element.children) {
        final s = '${child.attributes['src'] ?? ''}';
        if (s.isNotEmpty) return s;
      }
    } catch (_) {}
    return '';
  }

  static String _labelOf(dynamic element, String fallback) {
    final title = '${element.attributes['title'] ?? ''}'.trim();
    if (title.isNotEmpty) return title;
    final aria = '${element.attributes['aria-label'] ?? ''}'.trim();
    return aria.isNotEmpty ? aria : fallback;
  }
}

/// How many pixels wide a picture is worth decoding to.
///
/// This is the single biggest thing standing between this app and a
/// cheap phone. Flutter decodes an image at its FULL resolution unless
/// it is told otherwise, and holds the result as raw RGBA — so one
/// 3000x2000 photograph out of a lecture slide costs 24 MB of heap, and
/// a note with six diagrams in it costs 144 MB. On a 1 GB Tecno that is
/// not slow, it is a kill.
///
/// Capped at the screen's own pixel width: nothing can be drawn larger
/// than that, so decoding larger is spending a student's memory on
/// detail their screen cannot show. The 2048 ceiling covers a tablet
/// without letting a mis-tagged panorama through.
int bxDecodeWidth(BuildContext context, [double? logicalWidth]) {
  final mq = MediaQuery.maybeOf(context);
  final dpr = (mq?.devicePixelRatio ?? 1.0).clamp(1.0, 3.0);
  final screen = mq?.size.width ?? 400;
  final want = (logicalWidth != null &&
          logicalWidth.isFinite &&
          logicalWidth > 0 &&
          logicalWidth < screen)
      ? logicalWidth
      : screen;
  return (want * dpr).round().clamp(64, 2048);
}

/// The same ceiling for a picture drawn with no context to measure —
/// the HTML factory's synchronous hook. It has no BuildContext at all,
/// so it reads the platform view directly.
int bxDecodeWidthForPlatform() {
  try {
    final view = PlatformDispatcher.instance.implicitView;
    if (view == null) return 1080;
    final px = view.physicalSize.width;
    if (!px.isFinite || px <= 0) return 1080;
    return px.round().clamp(64, 2048);
  } catch (_) {
    return 1080;
  }
}

/// The hook that makes offline pictures possible.
///
/// `imageProviderFromNetwork` is called synchronously while the tree is
/// being built, with no BuildContext, so the lookup has to be answerable
/// from memory. It is: the offline catalogue is loaded once at boot and
/// held there, and this is a map read.
class _BxWidgetFactory extends WidgetFactory {
  @override
  ImageProvider? imageProviderFromNetwork(String url) {
    if (url.isEmpty) return null;
    final width = bxDecodeWidthForPlatform();
    final local = Offline.pathFor(url);
    if (local != null) {
      final f = File(local);
      // existsSync is a stat on a path we wrote ourselves; it is cheap
      // and it is the difference between a picture and a grey box.
      if (f.existsSync()) {
        // Wrapped, so a full-page diagram out of a lecture slide is
        // decoded at the width of the phone rather than at whatever the
        // scanner produced.
        return ResizeImage(FileImage(f), width: width, allowUpscaling: false);
      }
    }
    final network = super.imageProviderFromNetwork(url);
    if (network == null) return null;
    return ResizeImage(network, width: width, allowUpscaling: false);
  }
}

class _Placeholder extends StatelessWidget {
  final BxColors colors;
  final IconData icon;
  final String label;
  final String? hint;
  final bool busy;

  const _Placeholder({
    required this.colors,
    required this.icon,
    required this.label,
    this.hint,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.all(BxSpace.sm),
      decoration: BoxDecoration(
        color: colors.ground,
        borderRadius: BorderRadius.circular(BxRadius.sm),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox(
              width: 20,
              height: 20,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: colors.gold),
            )
          else
            Icon(icon, size: 26, color: colors.muted),
          const SizedBox(height: BxSpace.xxs),
          Text(label,
              style: BxType.smallStrong(colors.inkSoft),
              textAlign: TextAlign.center),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!,
                style: BxType.tiny(colors.muted), textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

/// A picture that is not inside HTML — a question diagram, a material
/// thumbnail. Same rules: disk first, then the network, and never a URL
/// on screen when it fails.
class BxNetworkImage extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? radius;

  /// Shown instead of the picture when there is nothing to show.
  final Widget? empty;

  const BxNetworkImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.radius,
    this.empty,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final raw = url?.trim() ?? '';
    if (raw.isEmpty) return empty ?? const SizedBox.shrink();

    final local = Offline.pathFor(raw);
    // Decoded at the size it will be DRAWN, never at the size it was
    // uploaded. See bxDecodeWidth: this is what keeps a note full of
    // lecture-slide diagrams inside the heap of a cheap phone.
    final cacheWidth = bxDecodeWidth(context, width);
    Widget image;
    if (local != null && File(local).existsSync()) {
      image = Image.file(
        File(local),
        width: width,
        height: height,
        fit: fit,
        cacheWidth: cacheWidth,
        errorBuilder: (_, __, ___) => _broken(c),
      );
    } else {
      image = Image.network(
        raw,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: cacheWidth,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : _loading(c),
        errorBuilder: (_, __, ___) => _broken(c),
      );
    }

    final r = radius;
    return r == null ? image : ClipRRect(borderRadius: r, child: image);
  }

  Widget _loading(BxColors c) => Container(
        width: width,
        height: height ?? 120,
        alignment: Alignment.center,
        color: c.ground,
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: c.gold),
        ),
      );

  Widget _broken(BxColors c) => Container(
        width: width,
        height: height ?? 120,
        alignment: Alignment.center,
        color: c.ground,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_outlined, size: 22, color: c.muted),
            const SizedBox(height: 4),
            Text('Picture unavailable', style: BxType.tiny(c.muted)),
          ],
        ),
      );
}

/// A drop-in for `CachedNetworkImage` that looks on disk first.
///
/// `CachedNetworkImage` keeps its own disk cache, which helps a student
/// who has already SEEN a picture. It cannot help one who has only
/// synced it — the sync writes into the offline root, and the package
/// knows nothing about that. Every question diagram in the app went
/// through it, so a synced picture was still fetched over the network,
/// and with the radio off it simply did not appear.
///
/// This keeps the same call shape so each screen's own placeholder and
/// error widget survive; it only changes where the bytes come from.
class BxImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, Object)? errorWidget;

  const BxImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final cacheWidth = bxDecodeWidth(context, width);
    final local = Offline.pathFor(imageUrl);
    if (local != null) {
      final file = File(local);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          cacheWidth: cacheWidth,
          errorBuilder: (ctx, e, __) =>
              errorWidget?.call(ctx, imageUrl, e) ?? const SizedBox.shrink(),
        );
      }
    }
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      memCacheWidth: cacheWidth,
      placeholder: placeholder,
      errorWidget: errorWidget,
    );
  }
}
