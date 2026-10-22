import 'package:flutter_test/flutter_test.dart';
import 'package:reels_feed/reels_feed.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'fake_video_platform.dart';

const _a = ReelSource.network('https://cdn/a.mp4');
const _b = ReelSource.network('https://cdn/b.mp4');
const _c = ReelSource.network('https://cdn/c.mp4');

Future<void> settle() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeVideoPlatform platform;

  setUp(() {
    platform = FakeVideoPlatform();
    VideoPlayerPlatform.instance = platform;
  });

  test('acquiring the same source twice opens one player', () async {
    final pool = ReelVideoPool();
    addTearDown(pool.dispose);
    final first = pool.acquire(_a);
    final second = pool.acquire(_a);
    await settle();
    expect(identical(first, second), isTrue);
    expect(platform.created, ['https://cdn/a.mp4']);
    expect(pool.length, 1);
  });

  test('an entry becomes ready once the player opens', () async {
    final pool = ReelVideoPool();
    addTearDown(pool.dispose);
    final entry = pool.acquire(_a);
    expect(entry.status, ReelVideoStatus.initializing);
    await settle();
    expect(entry.status, ReelVideoStatus.ready);
    expect(entry.controller.value.isInitialized, isTrue);
  });

  test('a released video stays open as an idle one up to maxIdle', () async {
    final pool = ReelVideoPool(maxIdle: 1);
    addTearDown(pool.dispose);
    final a = pool.acquire(_a);
    final b = pool.acquire(_b);
    await settle();
    pool.release(a);
    expect(pool.contains(_a), isTrue);
    pool.release(b);
    // Two idle videos, room for one: the older (a) goes.
    expect(pool.contains(_a), isFalse);
    expect(pool.contains(_b), isTrue);
  });

  test('with maxIdle 0 a released video is disposed at once', () async {
    final pool = ReelVideoPool(maxIdle: 0);
    addTearDown(pool.dispose);
    final a = pool.acquire(_a);
    await settle();
    pool.release(a);
    expect(pool.length, 0);
    await settle();
    expect(platform.allDisposed, isTrue);
  });

  test('a video still in use is never evicted', () async {
    final pool = ReelVideoPool(maxIdle: 0);
    addTearDown(pool.dispose);
    final a = pool.acquire(_a);
    final b = pool.acquire(_b);
    final c = pool.acquire(_c);
    await settle();
    pool.release(b);
    expect(pool.contains(_a), isTrue);
    expect(pool.contains(_b), isFalse);
    expect(pool.contains(_c), isTrue);
    pool.release(a);
    pool.release(c);
    expect(pool.length, 0);
  });

  test('acquiring twice needs two releases', () async {
    final pool = ReelVideoPool(maxIdle: 0);
    addTearDown(pool.dispose);
    final a = pool.acquire(_a);
    pool.acquire(_a);
    await settle();
    pool.release(a);
    expect(pool.contains(_a), isTrue);
    pool.release(a);
    expect(pool.contains(_a), isFalse);
  });

  test('reacquiring an idle video reuses its player', () async {
    final pool = ReelVideoPool(maxIdle: 1);
    addTearDown(pool.dispose);
    final a = pool.acquire(_a);
    await settle();
    pool.release(a);
    final again = pool.acquire(_a);
    expect(identical(a, again), isTrue);
    expect(platform.created, hasLength(1));
  });

  test('a video that cannot open fails and can be retried', () async {
    platform.failing.add('https://cdn/a.mp4');
    final pool = ReelVideoPool(autoRetries: 0);
    addTearDown(pool.dispose);
    final entry = pool.acquire(_a);
    await settle();
    expect(entry.status, ReelVideoStatus.failed);
    expect(entry.error, isNotNull);

    platform.failing.clear();
    entry.retry();
    expect(entry.status, ReelVideoStatus.initializing);
    await settle();
    expect(entry.status, ReelVideoStatus.ready);
    expect(platform.created, hasLength(2));
  });

  test('a player that breaks after opening fails and can be retried', () async {
    final pool = ReelVideoPool(autoRetries: 0);
    addTearDown(pool.dispose);
    final entry = pool.acquire(_a);
    await settle();
    expect(entry.status, ReelVideoStatus.ready);

    platform.breakPlayer('https://cdn/a.mp4');
    await settle();
    expect(entry.status, ReelVideoStatus.failed);

    entry.retry();
    await settle();
    expect(entry.status, ReelVideoStatus.ready);
    expect(platform.created, hasLength(2));
  });

  test('a failing video is quietly reopened once before it shows as failed', () async {
    platform.failingOnce.add('https://cdn/a.mp4');
    final pool = ReelVideoPool();
    addTearDown(pool.dispose);
    final entry = pool.acquire(_a);
    await settle();
    // Between the failure and the quiet retry it still looks like it is loading.
    expect(entry.status, ReelVideoStatus.waiting);

    await Future<void>.delayed(const Duration(milliseconds: 350));
    await settle();
    expect(entry.status, ReelVideoStatus.ready);
    expect(platform.created, hasLength(2));
  });

  test('a video that keeps failing ends up failed after the quiet retries', () async {
    platform.failing.add('https://cdn/a.mp4');
    final pool = ReelVideoPool(autoRetries: 2);
    addTearDown(pool.dispose);
    final entry = pool.acquire(_a);
    for (var i = 0; i < 3; i++) {
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    await settle();
    expect(entry.status, ReelVideoStatus.failed);
    expect(platform.created, hasLength(3));
  });

  test('disposing the pool disposes every player', () async {
    final pool = ReelVideoPool();
    pool.acquire(_a);
    pool.acquire(_b);
    await settle();
    pool.dispose();
    await settle();
    expect(platform.allDisposed, isTrue);
    expect(pool.length, 0);
  });

  group('the player limit', () {
    const s1 = ReelSource.network('https://cdn/1.mp4');
    const s2 = ReelSource.network('https://cdn/2.mp4');
    const s3 = ReelSource.network('https://cdn/3.mp4');
    const s4 = ReelSource.network('https://cdn/4.mp4');
    const s5 = ReelSource.network('https://cdn/5.mp4');

    test('never opens more than maxPlayers players, the rest wait', () async {
      final pool = ReelVideoPool(maxPlayers: 3, maxIdle: 0);
      addTearDown(pool.dispose);

      final entries = [s1, s2, s3, s4, s5].map(pool.acquire).toList();
      await settle();

      expect(platform.openCount, 3);
      expect(entries[3].status, ReelVideoStatus.waiting);
      expect(entries[4].status, ReelVideoStatus.waiting);
    });

    test('a waiting video opens as soon as a player is given back', () async {
      final pool = ReelVideoPool(maxPlayers: 2, maxIdle: 0);
      addTearDown(pool.dispose);
      final a = pool.acquire(s1);
      pool.acquire(s2);
      final c = pool.acquire(s3);
      await settle();
      expect(c.status, ReelVideoStatus.waiting);

      pool.release(a);
      await settle();

      expect(c.status, ReelVideoStatus.ready);
      expect(platform.openCount, 2);
    });

    test('the video on screen takes a player from a preloaded neighbour instead of waiting', () async {
      final pool = ReelVideoPool(maxPlayers: 2, maxIdle: 0);
      addTearDown(pool.dispose);
      final a = pool.acquire(s1, active: true);
      final b = pool.acquire(s2);
      await settle();
      expect(b.status, ReelVideoStatus.ready);

      final c = pool.acquire(s3, active: true);
      await settle();

      expect(c.status, ReelVideoStatus.ready);
      expect(b.status, ReelVideoStatus.waiting, reason: 'the neighbour gave up its player');
      expect(a.status, ReelVideoStatus.ready, reason: 'another video on screen keeps its player');
    });

    test('a neighbour that gave up its player gets one back when a slot frees', () async {
      final pool = ReelVideoPool(maxPlayers: 2, maxIdle: 0);
      addTearDown(pool.dispose);
      final a = pool.acquire(s1, active: true);
      final b = pool.acquire(s2);
      await settle();
      final c = pool.acquire(s3, active: true);
      await settle();
      expect(b.status, ReelVideoStatus.waiting);

      pool.setActive(a, false);
      pool.release(a);
      await settle();

      expect(b.status, ReelVideoStatus.ready);
      expect(c.status, ReelVideoStatus.ready);
    });

    test('unused videos are given up before anything waits', () async {
      final pool = ReelVideoPool(maxPlayers: 2, maxIdle: 2);
      addTearDown(pool.dispose);
      final a = pool.acquire(s1);
      final b = pool.acquire(s2);
      await settle();
      pool.release(a);
      pool.release(b);

      final c = pool.acquire(s3);
      await settle();

      expect(c.status, ReelVideoStatus.ready);
      expect(platform.openCount, lessThanOrEqualTo(2));
    });

    test('the video on screen is opened before others that are waiting', () async {
      final pool = ReelVideoPool(maxPlayers: 1, maxIdle: 0);
      addTearDown(pool.dispose);
      final a = pool.acquire(s1);
      final b = pool.acquire(s2);
      final c = pool.acquire(s3);
      await settle();
      expect(a.status, ReelVideoStatus.ready);

      pool.setActive(c, true);
      pool.release(a);
      await settle();

      expect(c.status, ReelVideoStatus.ready);
      expect(b.status, ReelVideoStatus.waiting);
    });

    test('a video released while waiting never opens', () async {
      final pool = ReelVideoPool(maxPlayers: 1, maxIdle: 0);
      addTearDown(pool.dispose);
      final a = pool.acquire(s1);
      final b = pool.acquire(s2);
      await settle();

      pool.release(b);
      pool.release(a);
      await settle();

      expect(platform.created, ['https://cdn/1.mp4']);
      expect(pool.length, 0);
    });
  });

  group('with a video cache', () {
    test('a video that is not saved streams and is queued for saving', () async {
      final cache = _FakeCache();
      final pool = ReelVideoPool(cache: cache);
      addTearDown(pool.dispose);

      pool.acquire(_a);
      await settle();

      expect(platform.created, ['https://cdn/a.mp4']);
      expect(cache.prefetched, ['https://cdn/a.mp4']);
    });

    test('a saved video plays from its file, not the network', () async {
      final cache = _FakeCache()..saved['https://cdn/a.mp4'] = '/cache/a.mp4';
      final pool = ReelVideoPool(cache: cache);
      addTearDown(pool.dispose);

      pool.acquire(_a);
      await settle();

      expect(platform.created.single, contains('cache/a.mp4'));
      expect(platform.created.single, isNot(contains('https:')));
      expect(cache.prefetched, isEmpty);
    });

    test('the cache is ignored for assets and when it is unsupported', () async {
      final cache = _FakeCache(supported: false);
      final pool = ReelVideoPool(cache: cache);
      addTearDown(pool.dispose);

      pool.acquire(_a);
      await settle();

      expect(platform.created, ['https://cdn/a.mp4']);
      expect(cache.prefetched, isEmpty);
    });
  });

  test('a custom factory replaces how players are built', () async {
    var built = 0;
    final pool = ReelVideoPool(
      controllerFactory: (source) {
        built += 1;
        return createReelVideoController(source, mixWithOthers: true);
      },
    );
    addTearDown(pool.dispose);
    pool.acquire(_a);
    expect(built, 1);
  });
}

class _FakeCache implements ReelVideoCache {
  _FakeCache({this.supported = true});

  final bool supported;
  final Map<String, String> saved = <String, String>{};
  final List<String> prefetched = <String>[];

  @override
  bool get isSupported => supported;

  @override
  String? pathFor(ReelNetworkSource source) => saved[source.url];

  @override
  void prefetch(ReelNetworkSource source) => prefetched.add(source.url);

  @override
  Future<void> clear() async => saved.clear();
}
