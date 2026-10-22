import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import 'media/reel_video_pool.dart';
import 'reel_item_state.dart';
import 'reels_feed_controller.dart';

/// How many posts around the visible one are prepared ahead of time.
///
/// Preparing means building the post and opening its first video so that a
/// swipe starts instantly. Each prepared video holds a hardware decoder, so keep
/// the numbers small; the defaults suit most phones.
@immutable
class ReelsPreload {
  /// Creates a preload window of [ahead] posts after and [behind] posts before
  /// the visible one.
  const ReelsPreload({this.ahead = 1, this.behind = 1}) : assert(ahead >= 0), assert(behind >= 0);

  /// No preparation: only the visible post is built.
  const ReelsPreload.none() : this(ahead: 0, behind: 0);

  /// Posts prepared after the visible one.
  final int ahead;

  /// Posts prepared before the visible one.
  final int behind;

  /// How many pages to build off screen on each side.
  int get reach => math.max(ahead, behind);

  /// The phase of the post at [index] when [current] is visible.
  ReelItemPhase phaseOf(int index, int current) {
    final delta = index - current;
    if (delta == 0) return ReelItemPhase.active;
    if (delta > 0 && delta <= ahead) return ReelItemPhase.preload;
    if (delta < 0 && -delta <= behind) return ReelItemPhase.preload;
    return ReelItemPhase.idle;
  }
}

/// A vertical, full-screen feed of posts that snap one at a time, like Reels,
/// Shorts or TikTok.
///
/// The feed knows nothing about your data. Give it an [itemCount] and an
/// [itemBuilder]; inside each post, [ReelMediaCarousel] plays the post's videos
/// and pictures, and the other widgets (ReelActionRail, ReelCaption, ...) add
/// the usual overlays.
///
/// ```dart
/// ReelsFeed(
///   itemCount: posts.length,
///   onEndReached: loadMore,
///   isLoadingMore: loading,
///   onItemViewed: (i) => analytics.view(posts[i].id),
///   itemBuilder: (context, index) => ReelMediaCarousel(media: posts[index].media),
/// )
/// ```
///
/// What it takes care of:
/// * Only the visible post plays; neighbours are preloaded within [preload].
/// * Videos stop when the app goes to the background, when a route covers the
///   feed, or when [active] is `false` (for example in an inactive tab).
/// * [onEndReached] asks for more posts shortly before the end.
/// * [onItemViewed] reports a post once it has been on screen for
///   [viewDuration].
/// * Mouse drag, scroll wheel and keyboard (arrows, space, M) on desktop and
///   web.
class ReelsFeed extends StatefulWidget {
  /// Creates a feed.
  const ReelsFeed({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
    this.initialIndex = 0,
    this.active = true,
    this.preload = const ReelsPreload(),
    this.onPageChanged,
    this.onEndReached,
    this.endReachedThreshold = 3,
    this.isLoadingMore = false,
    this.loadingMoreBuilder,
    this.onItemViewed,
    this.viewDuration = const Duration(seconds: 1),
    this.emptyBuilder,
    this.pool,
    this.physics,
    this.backgroundColor = Colors.black,
    this.keyboardShortcuts = true,
    this.semanticLabel = 'Reels',
  }) : assert(itemCount >= 0),
       assert(endReachedThreshold >= 0);

  /// How many posts there are.
  final int itemCount;

  /// Builds the post at an index. Read what it should be doing with
  /// [ReelItemScope.of].
  final IndexedWidgetBuilder itemBuilder;

  /// Reads and drives the feed. Optional.
  final ReelsFeedController? controller;

  /// The post shown first when no [controller] is given.
  final int initialIndex;

  /// Set to `false` to pause every video, for example when the feed's tab is
  /// not selected.
  final bool active;

  /// How many posts around the visible one are prepared.
  final ReelsPreload preload;

  /// Called when a different post becomes the visible one.
  final ValueChanged<int>? onPageChanged;

  /// Called when the viewer is within [endReachedThreshold] posts of the end, so
  /// you can load more. It does not repeat for the same position; it fires again
  /// when [itemCount] grows or the viewer moves to another post.
  final VoidCallback? onEndReached;

  /// How many posts before the last one [onEndReached] fires.
  final int endReachedThreshold;

  /// Whether more posts are being loaded. Shows [loadingMoreBuilder] and holds
  /// back [onEndReached].
  final bool isLoadingMore;

  /// The loading indicator over the last post while [isLoadingMore]. Defaults
  /// to a small spinner at the bottom.
  final WidgetBuilder? loadingMoreBuilder;

  /// Called once per post after it has been visible for [viewDuration].
  final ValueChanged<int>? onItemViewed;

  /// How long a post must stay visible to count as viewed.
  final Duration viewDuration;

  /// Shown when [itemCount] is zero.
  final WidgetBuilder? emptyBuilder;

  /// The pool that opens and recycles the videos. The feed makes and disposes
  /// its own unless you pass one (then you dispose it).
  final ReelVideoPool? pool;

  /// How the feed scrolls. Defaults to one-page-at-a-time snapping.
  final ScrollPhysics? physics;

  /// Behind the posts.
  final Color backgroundColor;

  /// Whether arrow keys, space and M control the feed on desktop and web.
  final bool keyboardShortcuts;

  /// What a screen reader calls the feed.
  final String semanticLabel;

  @override
  State<ReelsFeed> createState() => _ReelsFeedState();
}

class _ReelsFeedState extends State<ReelsFeed> with WidgetsBindingObserver {
  late ReelsFeedController _controller;
  late bool _ownsController;
  late ReelVideoPool _pool;
  late bool _ownsPool;
  final FocusNode _focusNode = FocusNode(debugLabel: 'ReelsFeed');

  bool _foreground = true;
  bool _tickersEnabled = true;

  // Tells each built post when the active post or the live state changes, so only
  // the item scopes update on a swipe and your itemBuilder is not run again.
  final ValueNotifier<bool> _liveNotifier = ValueNotifier<bool>(true);
  late Listenable _itemChanges;
  Timer? _viewTimer;
  final Set<int> _viewed = <int>{};
  (int, int)? _lastLoadMoreRequest;

  int get _current => _controller.currentIndex.value;
  bool get _live => widget.active && _foreground && _tickersEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attachController();
    _attachPool();
    _scheduleView();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
  }

  void _attachController() {
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? ReelsFeedController(initialIndex: widget.initialIndex);
    _itemChanges = Listenable.merge(<Listenable>[_controller.currentIndex, _liveNotifier]);
  }

  void _attachPool() {
    _ownsPool = widget.pool == null;
    _pool = widget.pool ?? ReelVideoPool();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (enabled != _tickersEnabled) {
      _tickersEnabled = enabled;
      _syncLive();
      _scheduleView();
    }
  }

  @override
  void didUpdateWidget(covariant ReelsFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (_ownsController) _controller.dispose();
      _attachController();
    }
    if (oldWidget.pool != widget.pool) {
      if (_ownsPool) _pool.dispose();
      _attachPool();
    }
    if (oldWidget.active != widget.active) _syncLive();
    if (oldWidget.active != widget.active || oldWidget.viewDuration != widget.viewDuration) {
      _scheduleView();
    }
    if (oldWidget.itemCount != widget.itemCount || oldWidget.isLoadingMore != widget.isLoadingMore) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
    }
    if (widget.itemCount > 0 && _current >= widget.itemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.itemCount == 0 || _current < widget.itemCount) return;
        _controller.jumpToIndex(widget.itemCount - 1);
        _onPageChanged(widget.itemCount - 1);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    _syncLive();
    _scheduleView();
  }

  void _onPageChanged(int index) {
    _controller.updateIndex(index);
    widget.onPageChanged?.call(index);
    _scheduleView();
    _maybeLoadMore();
  }

  void _syncLive() => _liveNotifier.value = _live;

  void _scheduleView() {
    _viewTimer?.cancel();
    final callback = widget.onItemViewed;
    if (callback == null || !_live || widget.itemCount == 0) return;
    final index = _current;
    if (_viewed.contains(index)) return;
    _viewTimer = Timer(widget.viewDuration, () {
      if (!mounted || !_live || _current != index || !_viewed.add(index)) return;
      callback(index);
    });
  }

  void _maybeLoadMore() {
    final onEnd = widget.onEndReached;
    if (!mounted || onEnd == null || widget.isLoadingMore || widget.itemCount == 0) return;
    if (_current < widget.itemCount - 1 - widget.endReachedThreshold) return;
    final request = (widget.itemCount, _current);
    if (request == _lastLoadMoreRequest) return;
    _lastLoadMoreRequest = request;
    onEnd();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewTimer?.cancel();
    _focusNode.dispose();
    _liveNotifier.dispose();
    if (_ownsController) _controller.dispose();
    if (_ownsPool) _pool.dispose();
    super.dispose();
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => <ShortcutActivator, VoidCallback>{
    const SingleActivator(LogicalKeyboardKey.arrowDown): () => unawaited(_controller.next()),
    const SingleActivator(LogicalKeyboardKey.pageDown): () => unawaited(_controller.next()),
    const SingleActivator(LogicalKeyboardKey.keyJ): () => unawaited(_controller.next()),
    const SingleActivator(LogicalKeyboardKey.arrowUp): () => unawaited(_controller.previous()),
    const SingleActivator(LogicalKeyboardKey.pageUp): () => unawaited(_controller.previous()),
    const SingleActivator(LogicalKeyboardKey.keyK): () => unawaited(_controller.previous()),
    const SingleActivator(LogicalKeyboardKey.space): _controller.togglePause,
    const SingleActivator(LogicalKeyboardKey.keyM): _controller.toggleMute,
  };

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) {
      return ColoredBox(
        color: widget.backgroundColor,
        child: widget.emptyBuilder?.call(context) ?? const SizedBox.expand(),
      );
    }

    final reach = widget.preload.reach;
    Widget feed = PageView.builder(
      scrollDirection: Axis.vertical,
      controller: _controller.pageController,
      physics: widget.physics,
      allowImplicitScrolling: reach > 0,
      scrollCacheExtent: ScrollCacheExtent.viewport(reach.toDouble()),
      onPageChanged: _onPageChanged,
      itemCount: widget.itemCount,
      itemBuilder: (context, index) => ListenableBuilder(
        listenable: _itemChanges,
        builder: (context, child) {
          final phase = widget.preload.phaseOf(index, _current);
          final state = ReelItemState(
            index: index,
            phase: phase == ReelItemPhase.active && !_live ? ReelItemPhase.preload : phase,
          );
          return ReelItemScope(state: state, child: child!);
        },
        child: Builder(builder: (context) => widget.itemBuilder(context, index)),
      ),
    );

    // Mouse and trackpad can drag the feed, not only touch.
    feed = ScrollConfiguration(
      behavior: ScrollConfiguration.of(
        context,
      ).copyWith(dragDevices: PointerDeviceKind.values.toSet(), scrollbars: false),
      child: feed,
    );

    if (widget.keyboardShortcuts) {
      feed = CallbackShortcuts(
        bindings: _shortcuts,
        child: Focus(
          focusNode: _focusNode,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _focusNode.requestFocus(),
            child: feed,
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: widget.semanticLabel,
      child: ReelsFeedScope(
        controller: _controller,
        pool: _pool,
        child: ColoredBox(
          color: widget.backgroundColor,
          child: Stack(
            fit: StackFit.expand,
            children: [
              feed,
              if (widget.isLoadingMore)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Center(
                          child:
                              widget.loadingMoreBuilder?.call(context) ??
                              const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
