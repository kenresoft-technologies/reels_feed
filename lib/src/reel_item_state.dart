import 'package:flutter/widgets.dart';

import 'media/reel_video_pool.dart';
import 'reels_feed_controller.dart';

/// How close a post is to being shown.
enum ReelItemPhase {
  /// The post on screen. Its video plays.
  active,

  /// A post next to the active one. Its first video is opened and paused so the
  /// swipe starts instantly.
  preload,

  /// A post too far away to matter. It holds no video.
  idle,
}

/// What a post in a [ReelsFeed] should be doing right now. Read it with
/// [ReelItemScope.of] inside an `itemBuilder`.
@immutable
class ReelItemState {
  /// Creates the state of the post at [index].
  const ReelItemState({required this.index, required this.phase});

  /// The post's position in the feed.
  final int index;

  /// How close the post is to being shown.
  final ReelItemPhase phase;

  /// Whether this post is on screen and the feed is live (not paused by the app
  /// going to the background, a covering route or `ReelsFeed.active`).
  bool get isActive => phase == ReelItemPhase.active;

  /// Whether this post is active or preloading.
  bool get isNear => phase != ReelItemPhase.idle;

  @override
  bool operator ==(Object other) =>
      other is ReelItemState && other.index == index && other.phase == phase;

  @override
  int get hashCode => Object.hash(index, phase);
}

/// Tells the widgets inside one post what the post should be doing.
class ReelItemScope extends InheritedWidget {
  /// Creates a scope for one post.
  const ReelItemScope({super.key, required this.state, required super.child});

  /// The post's state.
  final ReelItemState state;

  /// The state of the post that [context] is inside. Throws when there is none.
  static ReelItemState of(BuildContext context) {
    final state = maybeOf(context);
    assert(state != null, 'No ReelItemScope found. Use this inside a ReelsFeed item.');
    return state!;
  }

  /// The state of the post that [context] is inside, or `null` outside a feed.
  static ReelItemState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReelItemScope>()?.state;

  @override
  bool updateShouldNotify(ReelItemScope oldWidget) => oldWidget.state != state;
}

/// Shares the feed-wide pieces (controller, video pool) with the widgets inside
/// every post. Not needed by apps; the media widgets read it.
class ReelsFeedScope extends InheritedWidget {
  /// Creates the feed scope.
  const ReelsFeedScope({super.key, required this.controller, required this.pool, required super.child});

  /// The feed's controller.
  final ReelsFeedController controller;

  /// The feed's video pool.
  final ReelVideoPool pool;

  /// The scope around [context], or `null` outside a feed.
  static ReelsFeedScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ReelsFeedScope>();

  @override
  bool updateShouldNotify(ReelsFeedScope oldWidget) =>
      oldWidget.controller != controller || oldWidget.pool != pool;
}
