import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import 'reel_source.dart';

/// Builds the player for a video [source]. Pass your own to [ReelVideoPool] to
/// add caching, custom headers or a different player.
typedef ReelVideoControllerFactory = VideoPlayerController Function(ReelSource source);

/// How far along a pooled video is.
enum ReelVideoStatus {
  /// The player is still opening the video.
  initializing,

  /// The video is ready to play.
  ready,

  /// The video could not be opened. Call [ReelVideoEntry.retry].
  failed,
}

/// One video held by a [ReelVideoPool]: its player and whether it is ready.
///
/// It notifies listeners when [status] changes or after [retry] replaces the
/// [controller].
class ReelVideoEntry extends ChangeNotifier {
  ReelVideoEntry._(this.source, this._factory) {
    _open();
  }

  /// The video this entry plays.
  final ReelSource source;

  final ReelVideoControllerFactory _factory;
  late VideoPlayerController _controller;
  ReelVideoStatus _status = ReelVideoStatus.initializing;
  Object? _error;
  bool _disposed = false;
  int _references = 0;
  int _lastUsed = 0;

  /// The player. Changes after [retry].
  VideoPlayerController get controller => _controller;

  /// How far along the video is.
  ReelVideoStatus get status => _status;

  /// Why the video failed to open, when [status] is [ReelVideoStatus.failed].
  Object? get error => _error;

  void _open() {
    final controller = _factory(source);
    _controller = controller;
    _status = ReelVideoStatus.initializing;
    _error = null;
    unawaited(_initialize(controller));
  }

  Future<void> _initialize(VideoPlayerController controller) async {
    try {
      await controller.initialize();
      if (_disposed || !identical(controller, _controller)) return;
      _status = ReelVideoStatus.ready;
    } catch (error) {
      if (_disposed || !identical(controller, _controller)) return;
      _error = error;
      _status = ReelVideoStatus.failed;
    }
    notifyListeners();
  }

  /// Opens the video again after a failure.
  void retry() {
    if (_disposed || _status != ReelVideoStatus.failed) return;
    final old = _controller;
    _open();
    notifyListeners();
    unawaited(old.dispose());
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_controller.dispose());
    super.dispose();
  }
}

/// Opens, shares and recycles video players for a feed.
///
/// A video player holds a hardware decoder, so a feed cannot keep one per post.
/// The pool keeps only the videos that are in use (the visible one and the ones
/// being preloaded), holds up to [maxIdle] recently used ones for a quick swipe
/// back, and disposes the rest.
///
/// [ReelsFeed] creates and disposes a pool for you. Create one yourself to
/// share it between feeds or to add a [controllerFactory].
class ReelVideoPool {
  /// Creates a pool.
  ///
  /// [maxIdle] is how many unused videos stay open. [mixWithOthers] lets the
  /// videos play alongside audio from other apps. [controllerFactory] replaces
  /// how players are built.
  ReelVideoPool({
    this.maxIdle = 1,
    this.mixWithOthers = false,
    ReelVideoControllerFactory? controllerFactory,
  }) : assert(maxIdle >= 0),
       _factory =
           controllerFactory ??
           ((source) => createReelVideoController(source, mixWithOthers: mixWithOthers));

  /// How many videos that nothing is using stay open.
  final int maxIdle;

  /// Whether videos play alongside audio from other apps.
  final bool mixWithOthers;

  final ReelVideoControllerFactory _factory;
  final Map<String, ReelVideoEntry> _entries = <String, ReelVideoEntry>{};
  int _clock = 0;
  bool _disposed = false;

  /// How many videos are open right now, in use or idle.
  int get length => _entries.length;

  /// Whether [source] is open right now.
  bool contains(ReelSource source) => _entries.containsKey(source.key);

  /// Takes a video for use, opening it if it is not open yet. Pair every call
  /// with [release].
  ReelVideoEntry acquire(ReelSource source) {
    assert(!_disposed, 'This pool has been disposed.');
    final entry = _entries.putIfAbsent(source.key, () => ReelVideoEntry._(source, _factory));
    entry
      .._references += 1
      .._lastUsed = ++_clock;
    return entry;
  }

  /// Gives a video back. Once nothing uses it, it stays open as an idle video
  /// until the pool needs the room.
  void release(ReelVideoEntry entry) {
    if (_disposed || entry._disposed) return;
    if (entry._references > 0) entry._references -= 1;
    if (entry._references == 0) entry._lastUsed = ++_clock;
    _trim();
  }

  void _trim() {
    final idle = _entries.values.where((e) => e._references == 0).toList()
      ..sort((a, b) => a._lastUsed.compareTo(b._lastUsed));
    var excess = idle.length - maxIdle;
    for (final entry in idle) {
      if (excess <= 0) break;
      _entries.remove(entry.source.key);
      entry.dispose();
      excess -= 1;
    }
  }

  /// Disposes every video. The pool cannot be used afterwards.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final entry in _entries.values) {
      entry.dispose();
    }
    _entries.clear();
  }
}
