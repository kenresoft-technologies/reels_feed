import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import 'reel_source.dart';
import 'reel_video_cache.dart';

/// Builds the player for a video [source]. Pass your own to [ReelVideoPool] to
/// add caching, custom headers or a different player.
typedef ReelVideoControllerFactory = VideoPlayerController Function(ReelSource source);

/// How far along a pooled video is.
enum ReelVideoStatus {
  /// Waiting for a free player slot (the pool limits how many players are open).
  waiting,

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
  ReelVideoEntry._(this.source, this._pool);

  /// The video this entry plays.
  final ReelSource source;

  final ReelVideoPool _pool;
  int _autoRetriesUsed = 0;
  Timer? _retryTimer;
  VideoPlayerController? _controller;
  ReelVideoStatus _status = ReelVideoStatus.waiting;
  Object? _error;
  bool _disposed = false;
  bool _active = false;
  int _references = 0;
  int _lastUsed = 0;

  /// The player. Only use it while [status] is [ReelVideoStatus.ready]; it
  /// changes after [retry] and is taken away while the entry is waiting.
  VideoPlayerController get controller => _controller!;

  /// How far along the video is.
  ReelVideoStatus get status => _status;

  /// Why the video failed to open, when [status] is [ReelVideoStatus.failed].
  Object? get error => _error;

  void _open() {
    if (_disposed) return;
    final controller = _pool._factory(source);
    _controller = controller;
    _status = ReelVideoStatus.initializing;
    _error = null;
    _notifyLater();
    unawaited(_initialize(controller));
  }

  Future<void> _initialize(VideoPlayerController controller) async {
    try {
      await controller.initialize();
      if (_disposed || !identical(controller, _controller)) return;
      _status = ReelVideoStatus.ready;
      controller.addListener(_watch);
    } catch (error) {
      if (_disposed || !identical(controller, _controller)) return;
      _fail(error);
      return;
    }
    notifyListeners();
  }

  // A player that opened fine can still fail later, for example when its
  // connection drops while it sits idle, or the system takes its decoder.
  void _watch() {
    if (_disposed || _status != ReelVideoStatus.ready) return;
    final value = _controller!.value;
    if (value.hasError) _fail(value.errorDescription ?? 'The video stopped with an error.');
  }

  void _fail(Object error) {
    if (_autoRetriesUsed < _pool.autoRetries) {
      // Often a dropped connection or a decoder the system took back: open the
      // video again, quietly.
      _autoRetriesUsed += 1;
      if (kDebugMode) debugPrint('reels_feed: retrying $source after: $error');
      _closeController();
      _status = ReelVideoStatus.waiting;
      _error = null;
      notifyListeners();
      _retryTimer = Timer(const Duration(milliseconds: 300), () {
        if (!_disposed) _pool._schedule(this);
      });
      return;
    }
    _error = error;
    _status = ReelVideoStatus.failed;
    if (kDebugMode) debugPrint('reels_feed: could not play $source: $error');
    notifyListeners();
  }

  /// Opens the video again after a failure.
  void retry() {
    if (_disposed || _status != ReelVideoStatus.failed) return;
    _autoRetriesUsed = 0;
    _closeController();
    _status = ReelVideoStatus.waiting;
    notifyListeners();
    _pool._schedule(this);
  }

  // Gives the player's slot to another video; the pool reopens this one when a
  // slot is free again.
  void _suspend() {
    _retryTimer?.cancel();
    _closeController();
    _status = ReelVideoStatus.waiting;
    _notifyLater();
  }

  // The pool can change an entry while some widget is building; its listeners
  // must not rebuild in the middle of that.
  void _notifyLater() {
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  void _closeController() {
    final controller = _controller;
    if (controller == null) return;
    _controller = null;
    controller.removeListener(_watch);
    _pool._closing += 1;
    unawaited(controller.dispose().whenComplete(_pool._closed));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _retryTimer?.cancel();
    _closeController();
    super.dispose();
  }
}

/// Opens, shares and recycles video players for a feed.
///
/// A video player holds a hardware decoder, and a phone has only a few (often 3
/// or 4). When an app asks for more, the system quietly takes one away from a
/// paused player, which then fails or has to reload. So the pool never has more
/// than [maxPlayers] open: the visible video and the ones being preloaded play,
/// up to [maxIdle] recently used ones wait for a quick swipe back, and a video
/// that needs a player while all are taken waits for one to free up (the visible
/// video takes one from a neighbour instead of waiting).
///
/// [ReelsFeed] creates and disposes a pool for you. Create one yourself to
/// share it between feeds or to add a [controllerFactory].
class ReelVideoPool {
  /// Creates a pool.
  ///
  /// [maxPlayers] is the most players open at once. [maxIdle] is how many unused
  /// videos stay open. [mixWithOthers] lets the videos play alongside audio from
  /// other apps. [autoRetries] is how many times a failing video is quietly
  /// reopened before an error shows. [cache] saves network videos to disk.
  /// [controllerFactory] replaces how players are built.
  ReelVideoPool({
    this.maxPlayers = 3,
    this.maxIdle = 1,
    this.mixWithOthers = false,
    this.autoRetries = 1,
    this.cache,
    ReelVideoControllerFactory? controllerFactory,
  }) : assert(maxPlayers >= 1),
       assert(maxIdle >= 0),
       assert(autoRetries >= 0),
       _factory =
           controllerFactory ??
           ((source) => createReelVideoController(source, mixWithOthers: mixWithOthers, cache: cache));

  /// The most video players open at once.
  final int maxPlayers;

  /// Saves network videos to disk so a video seen before plays again without
  /// the network. `null` turns saving off. Not used when you pass your own
  /// [ReelVideoControllerFactory].
  final ReelVideoCache? cache;

  /// How many videos that nothing is using stay open.
  final int maxIdle;

  /// Whether videos play alongside audio from other apps.
  final bool mixWithOthers;

  /// How many times a video that fails is quietly opened again before the viewer
  /// sees an error. A dropped connection is the usual cause, so one retry hides it.
  final int autoRetries;

  final ReelVideoControllerFactory _factory;
  final Map<String, ReelVideoEntry> _entries = <String, ReelVideoEntry>{};
  final List<ReelVideoEntry> _queue = <ReelVideoEntry>[];
  int _closing = 0;
  int _clock = 0;
  bool _disposed = false;

  /// How many videos the pool holds right now, open, waiting or idle.
  int get length => _entries.length;

  /// How many players are open right now, counting ones still shutting down.
  int get openPlayers => _entries.values.where((e) => e._controller != null).length + _closing;

  /// Whether [source] is held right now.
  bool contains(ReelSource source) => _entries.containsKey(source.key);

  /// Takes a video for use, opening it if it is not open yet. Pair every call
  /// with [release]. Pass [active] for the video on screen, which is opened
  /// first and may take a player from a preloaded neighbour.
  ReelVideoEntry acquire(ReelSource source, {bool active = false}) {
    assert(!_disposed, 'This pool has been disposed.');
    final entry = _entries.putIfAbsent(source.key, () => ReelVideoEntry._(source, this));
    entry
      .._references += 1
      .._lastUsed = ++_clock;
    if (active) entry._active = true;
    if (entry._status == ReelVideoStatus.waiting &&
        entry._controller == null &&
        entry._retryTimer?.isActive != true) {
      _schedule(entry);
    }
    return entry;
  }

  /// Marks [entry] as the video on screen (or not). The one on screen is opened
  /// ahead of the rest and cannot lose its player to a neighbour.
  void setActive(ReelVideoEntry entry, bool active) {
    if (_disposed || entry._disposed || entry._active == active) return;
    entry._active = active;
    if (active && entry._status == ReelVideoStatus.waiting && entry._retryTimer?.isActive != true) {
      _schedule(entry);
    }
  }

  /// Gives a video back. Once nothing uses it, it stays open as an idle video
  /// until the pool needs the room.
  void release(ReelVideoEntry entry) {
    if (_disposed || entry._disposed) return;
    if (entry._references > 0) entry._references -= 1;
    if (entry._references > 0) return;
    entry._active = false;
    entry._lastUsed = ++_clock;
    if (entry._controller == null && entry._status != ReelVideoStatus.initializing) {
      // Never got a player (or lost it): nothing worth keeping.
      _queue.remove(entry);
      _entries.remove(entry.source.key);
      entry.dispose();
    }
    _trim();
    _pump();
  }

  bool get _hasRoom => openPlayers < maxPlayers;

  void _schedule(ReelVideoEntry entry) {
    if (_disposed || entry._disposed) return;
    _makeRoom(forActive: entry._active, except: entry);
    // The video on screen never waits: a slot over the limit for a moment is
    // better than a blank screen.
    if (_hasRoom || entry._active) {
      _queue.remove(entry);
      entry._open();
    } else if (!_queue.contains(entry)) {
      _queue.add(entry);
    }
  }

  void _makeRoom({required bool forActive, required ReelVideoEntry except}) {
    // First give up videos nobody is using.
    while (!_hasRoom) {
      final idle =
          _entries.values
              .where((e) => e != except && e._references == 0 && e._controller != null)
              .toList()
            ..sort((a, b) => a._lastUsed.compareTo(b._lastUsed));
      if (idle.isEmpty) break;
      _entries.remove(idle.first.source.key);
      idle.first.dispose();
    }
    if (!forActive) return;
    // Then borrow from the preloaded neighbour that was prepared longest ago.
    while (!_hasRoom) {
      final held =
          _entries.values.where((e) => e != except && !e._active && e._controller != null).toList()
            ..sort((a, b) => a._lastUsed.compareTo(b._lastUsed));
      if (held.isEmpty) break;
      final victim = held.first.._suspend();
      if (!_queue.contains(victim)) _queue.add(victim);
    }
  }

  // Opens waiting videos while there is room, the one on screen first.
  void _pump() {
    while (!_disposed && _hasRoom && _queue.isNotEmpty) {
      _queue.removeWhere((e) => e._disposed || e._references == 0);
      if (_queue.isEmpty) break;
      final next = _queue.firstWhere((e) => e._active, orElse: () => _queue.first);
      _queue.remove(next);
      next._open();
    }
  }

  void _closed() {
    if (_closing > 0) _closing -= 1;
    _pump();
  }

  void _trim() {
    final idle = _entries.values.where((e) => e._references == 0).toList()
      ..sort((a, b) => a._lastUsed.compareTo(b._lastUsed));
    var excess = idle.length - maxIdle;
    for (final entry in idle) {
      if (excess <= 0) break;
      _entries.remove(entry.source.key);
      _queue.remove(entry);
      entry.dispose();
      excess -= 1;
    }
  }

  /// Disposes every video. The pool cannot be used afterwards.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _queue.clear();
    for (final entry in _entries.values) {
      entry.dispose();
    }
    _entries.clear();
  }
}
