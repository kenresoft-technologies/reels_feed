import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../widgets/reel_progress_bar.dart';
import 'reel_media.dart';
import 'reel_video_pool.dart';

/// Builds what replaces a video that failed to open. [retry] opens it again.
typedef ReelErrorBuilder = Widget Function(BuildContext context, VoidCallback retry);

/// Plays one video full-bleed, taking its player from a [ReelVideoPool].
///
/// It holds a player only while [hold] is `true`, plays only while [play] is
/// `true` and neither [paused] nor [holding] is set, and gives the player back
/// as soon as it is not needed.
class ReelVideoView extends StatefulWidget {
  /// Creates a view for [media], which must be a video.
  const ReelVideoView({
    super.key,
    required this.media,
    required this.pool,
    required this.hold,
    required this.play,
    required this.muted,
    required this.paused,
    required this.holding,
    required this.onToggleMute,
    this.fit,
    this.showMuteButton = true,
    this.muteAlignment = Alignment.topRight,
    this.mutePadding = const EdgeInsets.all(12),
    this.showProgressBar = true,
    this.progressPadding = EdgeInsets.zero,
    this.showPauseIcon = true,
    this.restartOnActive = true,
    this.errorBuilder,
  });

  /// The video.
  final ReelMedia media;

  /// Where the player comes from.
  final ReelVideoPool pool;

  /// Whether to hold a player (open and ready, possibly paused).
  final bool hold;

  /// Whether the video is the one meant to be playing.
  final bool play;

  /// Whether sound is off.
  final ValueListenable<bool> muted;

  /// Whether the viewer paused the video.
  final ValueListenable<bool> paused;

  /// Whether playback is held still by a press or a drag on the progress bar.
  final ValueNotifier<bool> holding;

  /// Called by the mute button.
  final VoidCallback onToggleMute;

  /// How the video fills the space. When `null`, tall videos fill it and wide
  /// videos fit inside it.
  final BoxFit? fit;

  /// Whether to show the mute button.
  final bool showMuteButton;

  /// Where the mute button sits.
  final Alignment muteAlignment;

  /// Space around the mute button.
  final EdgeInsets mutePadding;

  /// Whether to show the progress bar.
  final bool showProgressBar;

  /// Space around the progress bar.
  final EdgeInsets progressPadding;

  /// Whether to show a play icon over a paused video.
  final bool showPauseIcon;

  /// Whether the video starts over each time it becomes the active one.
  final bool restartOnActive;

  /// Replaces the default failure message.
  final ReelErrorBuilder? errorBuilder;

  @override
  State<ReelVideoView> createState() => _ReelVideoViewState();
}

class _ReelVideoViewState extends State<ReelVideoView> {
  ReelVideoEntry? _entry;
  ReelVideoPool? _entryPool;
  VideoPlayerController? _configured;
  bool _wasActive = false;

  @override
  void initState() {
    super.initState();
    _addNotifierListeners(widget);
    _syncEntry();
  }

  @override
  void didUpdateWidget(covariant ReelVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.muted != widget.muted ||
        oldWidget.paused != widget.paused ||
        oldWidget.holding != widget.holding) {
      _removeNotifierListeners(oldWidget);
      _addNotifierListeners(widget);
    }
    if (oldWidget.media.source != widget.media.source || oldWidget.pool != widget.pool) _releaseEntry();
    _syncEntry();
  }

  void _addNotifierListeners(ReelVideoView w) {
    w.muted.addListener(_apply);
    w.paused.addListener(_apply);
    w.holding.addListener(_apply);
  }

  void _removeNotifierListeners(ReelVideoView w) {
    w.muted.removeListener(_apply);
    w.paused.removeListener(_apply);
    w.holding.removeListener(_apply);
  }

  void _syncEntry() {
    if (widget.hold && _entry == null) {
      final entry = widget.pool.acquire(widget.media.source);
      entry.addListener(_onEntryChanged);
      _entry = entry;
      _entryPool = widget.pool;
    } else if (!widget.hold && _entry != null) {
      _releaseEntry();
    }
    _apply();
  }

  void _releaseEntry() {
    final entry = _entry;
    if (entry == null) return;
    entry.removeListener(_onEntryChanged);
    if (entry.status == ReelVideoStatus.ready && entry.controller.value.isPlaying) {
      entry.controller.pause();
    }
    _entryPool?.release(entry);
    _entry = null;
    _entryPool = null;
    _configured = null;
    _wasActive = false;
  }

  void _onEntryChanged() {
    if (!mounted) return;
    _apply();
    setState(() {});
  }

  /// Brings the player in line with what the view should be doing.
  void _apply() {
    final entry = _entry;
    if (entry == null || entry.status != ReelVideoStatus.ready) return;
    final controller = entry.controller;
    if (!identical(_configured, controller)) {
      _configured = controller;
      controller.setLooping(widget.media.loop);
    }
    final volume = widget.muted.value ? 0.0 : 1.0;
    if (controller.value.volume != volume) controller.setVolume(volume);

    final activating = widget.play && !_wasActive;
    _wasActive = widget.play;
    if (activating && widget.restartOnActive && controller.value.position > Duration.zero) {
      controller.seekTo(Duration.zero);
    }

    final shouldPlay = widget.play && !widget.paused.value && !widget.holding.value;
    if (shouldPlay) {
      if (!controller.value.isPlaying) controller.play();
    } else if (controller.value.isPlaying) {
      controller.pause();
    }
  }

  @override
  void dispose() {
    _removeNotifierListeners(widget);
    _releaseEntry();
    super.dispose();
  }

  BoxFit _fitFor(VideoPlayerValue value) {
    if (widget.fit != null) return widget.fit!;
    final aspect = value.isInitialized && value.size != Size.zero
        ? value.aspectRatio
        : widget.media.aspectRatio;
    return (aspect ?? 0.5625) < 1 ? BoxFit.cover : BoxFit.contain;
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    return Semantics(
      label: widget.media.semanticLabel ?? 'Video',
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (entry == null)
            _poster(1)
          else
            ListenableBuilder(
              listenable: entry,
              builder: (context, _) {
                if (entry.status == ReelVideoStatus.failed) return _failure(entry);
                if (entry.status == ReelVideoStatus.initializing) {
                  return _poster(1, spinner: widget.play);
                }
                return _ready(entry);
              },
            ),
        ],
      ),
    );
  }

  Widget _poster(double opacity, {bool spinner = false}) {
    final poster = widget.media.poster;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (poster != null)
          Opacity(
            opacity: opacity,
            child: Image(
              image: poster.toImageProvider(),
              fit:
                  widget.fit ??
                  ((widget.media.aspectRatio ?? 0.5625) < 1 ? BoxFit.cover : BoxFit.contain),
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        if (spinner) const Center(child: _Spinner()),
      ],
    );
  }

  Widget _failure(ReelVideoEntry entry) {
    final builder = widget.errorBuilder;
    if (builder != null) return builder(context, entry.retry);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.white70, size: 40),
          const SizedBox(height: 8),
          const Text("Couldn't play this video", style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: entry.retry,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }

  Widget _ready(ReelVideoEntry entry) {
    final controller = entry.controller;
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (value.hasError) return _failure(entry);
        final started = value.isPlaying || value.position > Duration.zero;
        final size = value.size;
        final video = size.isEmpty
            ? VideoPlayer(controller)
            : FittedBox(
                fit: _fitFor(value),
                clipBehavior: Clip.hardEdge,
                child: SizedBox(width: size.width, height: size.height, child: VideoPlayer(controller)),
              );
        return Stack(
          fit: StackFit.expand,
          children: [
            Center(child: SizedBox.expand(child: video)),
            if (widget.media.poster != null)
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: started ? 0 : 1,
                  duration: const Duration(milliseconds: 180),
                  child: _poster(1),
                ),
              ),
            if (widget.play && value.isBuffering) const Center(child: _Spinner()),
            if (widget.showPauseIcon) _pauseIcon(),
            if (widget.showMuteButton) _muteButton(),
            if (widget.showProgressBar)
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: widget.progressPadding,
                    child: ReelProgressBar(
                      controller: controller,
                      onScrubStart: () => widget.holding.value = true,
                      onScrubEnd: () => widget.holding.value = false,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _pauseIcon() => IgnorePointer(
    child: ValueListenableBuilder<bool>(
      valueListenable: widget.paused,
      builder: (context, paused, _) => AnimatedOpacity(
        opacity: paused && widget.play ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: const Center(
          child: Icon(
            Icons.play_arrow_rounded,
            color: Colors.white70,
            size: 88,
            shadows: [Shadow(blurRadius: 20, color: Colors.black54)],
          ),
        ),
      ),
    ),
  );

  Widget _muteButton() => SafeArea(
    child: Align(
      alignment: widget.muteAlignment,
      child: Padding(
        padding: widget.mutePadding,
        child: ValueListenableBuilder<bool>(
          valueListenable: widget.muted,
          builder: (context, muted, _) => Semantics(
            button: true,
            label: muted ? 'Unmute' : 'Mute',
            child: Material(
              color: Colors.black38,
              shape: const CircleBorder(),
              child: InkResponse(
                onTap: widget.onToggleMute,
                radius: 24,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 28,
    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white70),
  );
}
