import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Reads and drives a [ReelsFeed]: which post is showing, moving between posts,
/// and the pause and mute state shared by every video in the feed.
///
/// Create one when you need to react to or control the feed from outside:
///
/// ```dart
/// final controller = ReelsFeedController();
/// // ...
/// ReelsFeed(controller: controller, ...);
/// controller.currentIndex.addListener(() => print(controller.currentIndex.value));
/// controller.animateToIndex(3);
/// ```
///
/// A controller you create is yours to [dispose]. A feed that has no controller
/// makes and disposes its own.
class ReelsFeedController {
  /// Creates a controller. [initialIndex] is the post shown first. [startMuted]
  /// sets the first mute state (a browser only allows autoplay with sound off,
  /// so it defaults to muted there).
  ReelsFeedController({int initialIndex = 0, bool? startMuted})
    : assert(initialIndex >= 0),
      _pageController = PageController(initialPage: initialIndex),
      _currentIndex = ValueNotifier<int>(initialIndex),
      _muted = ValueNotifier<bool>(startMuted ?? kIsWeb),
      _paused = ValueNotifier<bool>(false);

  final PageController _pageController;
  final ValueNotifier<int> _currentIndex;
  final ValueNotifier<bool> _muted;
  final ValueNotifier<bool> _paused;

  /// The page controller behind the feed. Attached by [ReelsFeed].
  PageController get pageController => _pageController;

  /// The index of the post showing now. Updates when a swipe passes the halfway
  /// point.
  ValueListenable<int> get currentIndex => _currentIndex;

  /// Whether sound is off. Shared by every video in the feed, so unmuting once
  /// unmutes them all.
  ValueListenable<bool> get muted => _muted;

  /// Whether the viewer paused the current post. Resets to `false` on every
  /// swipe.
  ValueListenable<bool> get paused => _paused;

  /// Turns sound off or on.
  void setMuted(bool value) => _muted.value = value;

  /// Flips between muted and unmuted.
  void toggleMute() => _muted.value = !_muted.value;

  /// Pauses or resumes the current post.
  void setPaused(bool value) => _paused.value = value;

  /// Flips between paused and playing.
  void togglePause() => _paused.value = !_paused.value;

  /// Shows post [index] immediately.
  void jumpToIndex(int index) {
    if (_pageController.hasClients) _pageController.jumpToPage(index);
  }

  /// Scrolls to post [index].
  Future<void> animateToIndex(
    int index, {
    Duration duration = const Duration(milliseconds: 350),
    Curve curve = Curves.easeOutCubic,
  }) async {
    if (_pageController.hasClients) {
      await _pageController.animateToPage(index, duration: duration, curve: curve);
    }
  }

  /// Scrolls to the next post.
  Future<void> next({
    Duration duration = const Duration(milliseconds: 350),
    Curve curve = Curves.easeOutCubic,
  }) => animateToIndex(_currentIndex.value + 1, duration: duration, curve: curve);

  /// Scrolls to the previous post.
  Future<void> previous({
    Duration duration = const Duration(milliseconds: 350),
    Curve curve = Curves.easeOutCubic,
  }) => animateToIndex(
    _currentIndex.value - 1 < 0 ? 0 : _currentIndex.value - 1,
    duration: duration,
    curve: curve,
  );

  /// Called by [ReelsFeed] to publish the current post and clear the pause. You
  /// do not need to call it; use [jumpToIndex] or [animateToIndex] to move.
  void updateIndex(int index) {
    _currentIndex.value = index;
    _paused.value = false;
  }

  /// Releases the controller. Do not use it afterwards.
  void dispose() {
    _pageController.dispose();
    _currentIndex.dispose();
    _muted.dispose();
    _paused.dispose();
  }
}
