import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../reel_item_state.dart';
import '../widgets/reel_heart_burst.dart';
import 'reel_image_view.dart';
import 'reel_media.dart';
import 'reel_video_pool.dart';
import 'reel_video_view.dart';

/// How a post with several pictures or videos shows which one is current.
enum ReelIndicatorStyle {
  /// A row of small dots at the bottom.
  dots,

  /// A row of bars across the top, like stories.
  segments,

  /// No indicator.
  none,
}

/// Shows the pictures and videos of one post, full-bleed. A post with several
/// is a swipeable carousel.
///
/// Inside a [ReelsFeed] it needs nothing else: it reads whether its post is the
/// active one, and plays, pauses, preloads and releases videos accordingly.
///
/// ```dart
/// ReelMediaCarousel(
///   media: post.media,
///   onDoubleTap: (_) => likePost(post),
/// )
/// ```
///
/// It also gives the viewer: tap to pause or resume, press and hold to pause
/// while held, a mute button shared by every video, a scrubbable progress bar,
/// and a heart that bursts at a double-tap.
class ReelMediaCarousel extends StatefulWidget {
  /// Creates a carousel for [media].
  const ReelMediaCarousel({
    super.key,
    required this.media,
    this.active,
    this.initialPage = 0,
    this.onPageChanged,
    this.onTap,
    this.onDoubleTap,
    this.tapToPause = true,
    this.holdToPause = true,
    this.fit,
    this.indicator = ReelIndicatorStyle.dots,
    this.indicatorPadding = const EdgeInsets.all(12),
    this.showMuteButton = true,
    this.muteAlignment = Alignment.topRight,
    this.mutePadding = const EdgeInsets.all(12),
    this.showProgressBar = true,
    this.progressPadding = EdgeInsets.zero,
    this.showPauseIcon = true,
    this.restartOnActive = false,
    this.heartBurst,
    this.imageBuilder,
    this.errorBuilder,
    this.backgroundColor = Colors.black,
  }) : assert(initialPage >= 0);

  /// The pictures and videos of the post.
  final List<ReelMedia> media;

  /// Overrides whether the post is playing. Leave `null` inside a [ReelsFeed],
  /// where it follows the feed. Outside one, `null` means playing.
  final bool? active;

  /// The media shown first.
  final int initialPage;

  /// Called when the viewer swipes to another media in the post.
  final ValueChanged<int>? onPageChanged;

  /// Called on a single tap.
  final VoidCallback? onTap;

  /// Called on a double tap with the tap position. Setting it also shows the
  /// heart burst; a single tap then waits briefly to tell the two apart.
  final ValueChanged<Offset>? onDoubleTap;

  /// Whether a tap pauses and resumes the current video.
  final bool tapToPause;

  /// Whether pressing and holding pauses the video until release.
  final bool holdToPause;

  /// How media fills the screen. When `null`, tall media fills it and wide media
  /// fits inside it.
  final BoxFit? fit;

  /// How a post with several media shows the current one.
  final ReelIndicatorStyle indicator;

  /// Space around the indicator.
  final EdgeInsets indicatorPadding;

  /// Whether to show the mute button on videos.
  final bool showMuteButton;

  /// Where the mute button sits.
  final Alignment muteAlignment;

  /// Space around the mute button.
  final EdgeInsets mutePadding;

  /// Whether to show the progress bar on videos.
  final bool showProgressBar;

  /// Space around the progress bar.
  final EdgeInsets progressPadding;

  /// Whether to show a play icon over a paused video.
  final bool showPauseIcon;

  /// Whether a video starts over each time its post becomes the active one. By
  /// default it resumes where it was, which is instant because it is already
  /// buffered. Starting over needs a seek, and seeking a paused video decoder can
  /// hang on some phones, so turn this on only if you need it.
  final bool restartOnActive;

  /// Replaces the heart that bursts on a double tap.
  final Widget? heartBurst;

  /// Loads pictures with your own loader or cache instead of Flutter's image
  /// cache.
  final ReelImageBuilder? imageBuilder;

  /// Replaces the message shown when a video cannot be opened.
  final ReelErrorBuilder? errorBuilder;

  /// Behind the media.
  final Color backgroundColor;

  @override
  State<ReelMediaCarousel> createState() => _ReelMediaCarouselState();
}

class _ReelMediaCarouselState extends State<ReelMediaCarousel> {
  late final PageController _pages;
  late int _page;
  final GlobalKey<ReelHeartBurstState> _burst = GlobalKey<ReelHeartBurstState>();
  final ValueNotifier<bool> _holding = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _localMuted = ValueNotifier<bool>(kIsWeb);
  final ValueNotifier<bool> _localPaused = ValueNotifier<bool>(false);
  ReelVideoPool? _ownPool;
  Offset _doubleTapAt = Offset.zero;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage.clamp(0, widget.media.isEmpty ? 0 : widget.media.length - 1);
    _pages = PageController(initialPage: _page);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheNeighbour();
  }

  @override
  void didUpdateWidget(covariant ReelMediaCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_page >= widget.media.length && widget.media.isNotEmpty) {
      _page = widget.media.length - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.hasClients) _pages.jumpToPage(_page);
      });
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    _holding.dispose();
    _localMuted.dispose();
    _localPaused.dispose();
    _ownPool?.dispose();
    super.dispose();
  }

  ReelItemPhase _phase(BuildContext context) {
    final override = widget.active;
    if (override != null) return override ? ReelItemPhase.active : ReelItemPhase.idle;
    return ReelItemScope.maybeOf(context)?.phase ?? ReelItemPhase.active;
  }

  ReelsFeedScope? _scope(BuildContext context) => ReelsFeedScope.maybeOf(context);

  ReelVideoPool _pool(BuildContext context) => _scope(context)?.pool ?? (_ownPool ??= ReelVideoPool());

  ValueListenable<bool> _muted(BuildContext context) {
    final scope = _scope(context);
    return scope == null ? _localMuted : scope.controller.muted;
  }

  ValueListenable<bool> _paused(BuildContext context) {
    final scope = _scope(context);
    return scope == null ? _localPaused : scope.controller.paused;
  }

  void _setPaused(bool value) {
    final scope = _scope(context);
    if (scope == null) {
      _localPaused.value = value;
    } else {
      scope.controller.setPaused(value);
    }
  }

  void _toggleMute() {
    final scope = _scope(context);
    if (scope == null) {
      _localMuted.value = !_localMuted.value;
    } else {
      scope.controller.toggleMute();
    }
  }

  void _precacheNeighbour() {
    final next = _page + 1;
    if (next >= widget.media.length || _phase(context) == ReelItemPhase.idle) return;
    final media = widget.media[next];
    if (media.type == ReelMediaType.image && widget.imageBuilder == null) {
      unawaited(precacheImage(media.source.toImageProvider(), context, onError: (_, _) {}));
    }
  }

  bool get _currentIsVideo => widget.media.isNotEmpty && widget.media[_page].isVideo;

  void _handleTap() {
    widget.onTap?.call();
    if (widget.tapToPause && _currentIsVideo) {
      _setPaused(!_paused(context).value);
    }
  }

  void _handleDoubleTap() {
    _burst.currentState?.burst(_doubleTapAt);
    widget.onDoubleTap?.call(_doubleTapAt);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.media.isEmpty) return ColoredBox(color: widget.backgroundColor);

    final phase = _phase(context);
    final pool = _pool(context);
    final muted = _muted(context);
    final paused = _paused(context);

    final Widget content = widget.media.length == 1
        ? _mediaPage(0, phase, pool, muted, paused)
        : PageView.builder(
            controller: _pages,
            itemCount: widget.media.length,
            onPageChanged: (index) {
              setState(() => _page = index);
              _setPaused(false);
              widget.onPageChanged?.call(index);
              _precacheNeighbour();
            },
            itemBuilder: (context, index) => _mediaPage(index, phase, pool, muted, paused),
          );

    return ColoredBox(
      color: widget.backgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleTap,
            onDoubleTapDown: widget.onDoubleTap == null
                ? null
                : (details) => _doubleTapAt = details.localPosition,
            onDoubleTap: widget.onDoubleTap == null ? null : _handleDoubleTap,
            onLongPressStart: widget.holdToPause && _currentIsVideo
                ? (_) => _holding.value = true
                : null,
            onLongPressEnd: widget.holdToPause ? (_) => _holding.value = false : null,
            onLongPressCancel: widget.holdToPause ? () => _holding.value = false : null,
            child: content,
          ),
          if (widget.onDoubleTap != null) ReelHeartBurst(key: _burst, child: widget.heartBurst),
          if (widget.media.length > 1 && widget.indicator != ReelIndicatorStyle.none) _indicator(),
        ],
      ),
    );
  }

  Widget _mediaPage(
    int index,
    ReelItemPhase phase,
    ReelVideoPool pool,
    ValueListenable<bool> muted,
    ValueListenable<bool> paused,
  ) {
    final media = widget.media[index];
    final current = index == _page;
    if (!media.isVideo) {
      return ReelImageView(media: media, fit: widget.fit, imageBuilder: widget.imageBuilder);
    }
    return ReelVideoView(
      media: media,
      pool: pool,
      hold: current && phase != ReelItemPhase.idle,
      play: current && phase == ReelItemPhase.active,
      muted: muted,
      paused: paused,
      holding: _holding,
      onToggleMute: _toggleMute,
      fit: widget.fit,
      showMuteButton: widget.showMuteButton,
      muteAlignment: widget.muteAlignment,
      mutePadding: widget.mutePadding,
      showProgressBar: widget.showProgressBar,
      progressPadding: widget.progressPadding,
      showPauseIcon: widget.showPauseIcon,
      restartOnActive: widget.restartOnActive,
      errorBuilder: widget.errorBuilder,
    );
  }

  Widget _indicator() {
    final count = widget.media.length;
    final label = 'Item ${_page + 1} of $count';
    switch (widget.indicator) {
      case ReelIndicatorStyle.segments:
        return SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: widget.indicatorPadding,
              child: Semantics(
                label: label,
                child: Row(
                  children: [
                    for (var i = 0; i < count; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 3,
                            decoration: BoxDecoration(
                              color: i <= _page ? Colors.white : Colors.white30,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      case ReelIndicatorStyle.dots:
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: widget.indicatorPadding + const EdgeInsets.only(bottom: 6),
              child: Semantics(
                label: label,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < count; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _page ? 16 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _page ? Colors.white : Colors.white54,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      case ReelIndicatorStyle.none:
        return const SizedBox.shrink();
    }
  }
}
