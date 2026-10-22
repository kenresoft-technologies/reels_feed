import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A stand-in for the native video player that records what it is asked to do.
class FakeVideoPlatform extends VideoPlayerPlatform with MockPlatformInterfaceMixin {
  /// Addresses that fail to open.
  final Set<String> failing = <String>{};

  /// Addresses that fail to open only the next time, then work.
  final Set<String> failingOnce = <String>{};

  /// Every address a player was created for, in order.
  final List<String> created = <String>[];

  /// Calls received, as `"<verb> <playerId>"` or `"<verb> <playerId> <arg>"`.
  final List<String> calls = <String>[];

  final Map<int, StreamController<VideoEvent>> _events = <int, StreamController<VideoEvent>>{};
  final Map<int, String> _uris = <int, String>{};
  final Set<int> disposed = <int>{};
  int _nextId = 1;

  /// How many times [verb] was called for the player showing [uri].
  int count(String verb, String uri) {
    final ids = _uris.entries.where((e) => e.value == uri).map((e) => e.key).toSet();
    return calls.where((c) {
      final parts = c.split(' ');
      return parts[0] == verb && ids.contains(int.parse(parts[1]));
    }).length;
  }

  /// The last volume set for the player showing [uri], or `null`.
  double? volumeOf(String uri) {
    final ids = _uris.entries.where((e) => e.value == uri).map((e) => e.key).toSet();
    for (final c in calls.reversed) {
      final parts = c.split(' ');
      if (parts[0] == 'volume' && ids.contains(int.parse(parts[1]))) return double.parse(parts[2]);
    }
    return null;
  }

  /// Makes the open player for [uri] report a runtime error, as when its
  /// connection drops.
  void breakPlayer(String uri) {
    for (final e in _uris.entries.where((e) => e.value == uri)) {
      _events[e.key]!.addError(PlatformException(code: 'broken', message: 'connection lost'));
    }
  }

  /// Whether every created player has been disposed.
  bool get allDisposed => disposed.length == _uris.length;

  /// How many players are open (created and not disposed).
  int get openCount => _uris.length - disposed.length;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final uri = options.dataSource.uri ?? options.dataSource.asset ?? '';
    final id = _nextId++;
    _uris[id] = uri;
    created.add(uri);
    final controller = StreamController<VideoEvent>();
    _events[id] = controller;
    final failNow = failing.contains(uri) || failingOnce.remove(uri);
    if (failNow) {
      scheduleMicrotask(
        () => controller.addError(PlatformException(code: 'fail', message: 'cannot open')),
      );
    } else {
      scheduleMicrotask(() {
        controller.add(
          VideoEvent(
            eventType: VideoEventType.initialized,
            duration: const Duration(seconds: 20),
            size: const Size(1080, 1920),
          ),
        );
      });
    }
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    calls.add('dispose $playerId');
    await _events[playerId]?.close();
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async => calls.add('loop $playerId $looping');

  @override
  Future<void> play(int playerId) async => calls.add('play $playerId');

  @override
  Future<void> pause(int playerId) async => calls.add('pause $playerId');

  @override
  Future<void> setVolume(int playerId, double volume) async => calls.add('volume $playerId $volume');

  @override
  Future<void> seekTo(int playerId, Duration position) async => calls.add('seek $playerId');

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(int playerId, bool value) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox.expand();

  @override
  Widget buildView(int playerId) => const SizedBox.expand();
}
