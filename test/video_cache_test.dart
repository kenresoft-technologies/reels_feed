@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reels_feed/reels_feed.dart';

/// A tiny local web server that serves "videos" so the cache can be tested for
/// real, without the network.
class _Server {
  _Server._(this._server) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  final Map<String, _Route> routes = <String, _Route>{};
  final Map<String, int> hits = <String, int>{};
  int _running = 0;
  int peakConcurrent = 0;

  static Future<_Server> start() async =>
      _Server._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  String url(String path) => 'http://${_server.address.host}:${_server.port}$path';

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    hits[path] = (hits[path] ?? 0) + 1;
    final route = routes[path];
    _running += 1;
    if (_running > peakConcurrent) peakConcurrent = _running;
    try {
      if (route == null) {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      if (route.delay != Duration.zero) await Future<void>.delayed(route.delay);
      request.response.headers.contentType = ContentType.parse(route.contentType);
      request.response.contentLength = route.declaredLength ?? route.body.length;
      request.response.add(route.body);
      await request.response.close();
    } on Object {
      // A deliberately broken response ends up here; nothing to do.
    } finally {
      _running -= 1;
    }
  }

  Future<void> close() => _server.close(force: true);
}

class _Route {
  _Route(this.body, {this.contentType = 'video/mp4', this.declaredLength, this.delay = Duration.zero});

  final Uint8List body;
  final String contentType;
  final int? declaredLength;
  final Duration delay;
}

Uint8List _bytes(int length, [int seed = 7]) =>
    Uint8List.fromList(List.generate(length, (i) => (i * seed) % 251));

Future<void> _until(bool Function() condition, {Duration timeout = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting for the condition.');
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
}

void main() {
  late _Server server;
  late Directory dir;

  setUp(() async {
    server = await _Server.start();
    dir = await Directory.systemTemp.createTemp('reels_cache_test_');
  });

  tearDown(() async {
    await server.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  ReelNetworkSource source(String path) => ReelNetworkSource(server.url(path));

  test('a video that is not saved yet has no path, then downloads in the background', () async {
    final body = _bytes(5000);
    server.routes['/a.mp4'] = _Route(body);
    final cache = ReelVideoCache(directory: dir.path);

    expect(cache.pathFor(source('/a.mp4')), isNull);
    cache.prefetch(source('/a.mp4'));
    await _until(() => cache.pathFor(source('/a.mp4')) != null);

    expect(File(cache.pathFor(source('/a.mp4'))!).readAsBytesSync(), body);
  });

  test('asking again for a saved video does not download it again', () async {
    server.routes['/a.mp4'] = _Route(_bytes(2000));
    final cache = ReelVideoCache(directory: dir.path);
    cache.prefetch(source('/a.mp4'));
    await _until(() => cache.pathFor(source('/a.mp4')) != null);

    cache.prefetch(source('/a.mp4'));
    cache.prefetch(source('/a.mp4'));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(server.hits['/a.mp4'], 1);
  });

  test('repeated prefetch calls while downloading start one download', () async {
    server.routes['/slow.mp4'] = _Route(_bytes(3000), delay: const Duration(milliseconds: 150));
    final cache = ReelVideoCache(directory: dir.path);

    for (var i = 0; i < 5; i++) {
      cache.prefetch(source('/slow.mp4'));
    }
    await _until(() => cache.pathFor(source('/slow.mp4')) != null);

    expect(server.hits['/slow.mp4'], 1);
  });

  test('saved files keep the address extension and survive a new cache object', () async {
    server.routes['/clip.webm'] = _Route(_bytes(1500), contentType: 'video/webm');
    final first = ReelVideoCache(directory: dir.path);
    first.prefetch(source('/clip.webm'));
    await _until(() => first.pathFor(source('/clip.webm')) != null);

    final second = ReelVideoCache(directory: dir.path);
    final path = second.pathFor(source('/clip.webm'));
    expect(path, isNotNull);
    expect(path, endsWith('.webm'));
  });

  test('responses that are not video are not saved and not retried', () async {
    server.routes['/page.mp4'] = _Route(_bytes(500), contentType: 'text/html');
    final cache = ReelVideoCache(directory: dir.path);

    cache.prefetch(source('/page.mp4'));
    await _until(() => (server.hits['/page.mp4'] ?? 0) >= 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    cache.prefetch(source('/page.mp4'));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(cache.pathFor(source('/page.mp4')), isNull);
    expect(server.hits['/page.mp4'], 1);
  });

  test('streaming playlists are left to stream', () async {
    server.routes['/live.m3u8'] = _Route(_bytes(200), contentType: 'application/vnd.apple.mpegurl');
    final cache = ReelVideoCache(directory: dir.path);

    cache.prefetch(source('/live.m3u8'));
    await _until(() => (server.hits['/live.m3u8'] ?? 0) >= 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(cache.pathFor(source('/live.m3u8')), isNull);
  });

  test('a video larger than maxFileBytes is not saved', () async {
    server.routes['/big.mp4'] = _Route(_bytes(5000));
    final cache = ReelVideoCache(directory: dir.path, maxFileBytes: 1000);

    cache.prefetch(source('/big.mp4'));
    await _until(() => (server.hits['/big.mp4'] ?? 0) >= 1);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(cache.pathFor(source('/big.mp4')), isNull);
    expect(dir.listSync().where((e) => e.path.endsWith('.part')), isEmpty);
  });

  test('a download that is cut short is thrown away, not saved as a broken video', () async {
    server.routes['/cut.mp4'] = _Route(_bytes(1000), declaredLength: 5000);
    final cache = ReelVideoCache(directory: dir.path);

    cache.prefetch(source('/cut.mp4'));
    await _until(() => (server.hits['/cut.mp4'] ?? 0) >= 1);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(cache.pathFor(source('/cut.mp4')), isNull);
    expect(dir.listSync().where((e) => e.path.endsWith('.part')), isEmpty);
  });

  test('an error response is not saved', () async {
    final cache = ReelVideoCache(directory: dir.path);

    cache.prefetch(source('/missing.mp4'));
    await _until(() => (server.hits['/missing.mp4'] ?? 0) >= 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(cache.pathFor(source('/missing.mp4')), isNull);
  });

  test('the least recently used videos are removed to stay under maxBytes', () async {
    for (final name in ['a', 'b', 'c']) {
      server.routes['/$name.mp4'] = _Route(_bytes(1000));
    }
    final cache = ReelVideoCache(directory: dir.path, maxBytes: 2500, maxConcurrentDownloads: 1);

    cache.prefetch(source('/a.mp4'));
    await _until(() => cache.pathFor(source('/a.mp4')) != null);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    cache.prefetch(source('/b.mp4'));
    await _until(() => cache.pathFor(source('/b.mp4')) != null);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // Using a makes b the least recently used.
    expect(cache.pathFor(source('/a.mp4')), isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    cache.prefetch(source('/c.mp4'));
    await _until(() => cache.pathFor(source('/c.mp4')) != null);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(cache.pathFor(source('/b.mp4')), isNull, reason: 'b was the least recently used');
    expect(cache.pathFor(source('/a.mp4')), isNotNull);
    expect(cache.pathFor(source('/c.mp4')), isNotNull);
  });

  test('only maxConcurrentDownloads run at once', () async {
    for (var i = 0; i < 6; i++) {
      server.routes['/v$i.mp4'] = _Route(_bytes(800), delay: const Duration(milliseconds: 80));
    }
    final cache = ReelVideoCache(directory: dir.path, maxConcurrentDownloads: 2);

    for (var i = 0; i < 6; i++) {
      cache.prefetch(source('/v$i.mp4'));
    }
    await _until(
      () => List.generate(6, (i) => cache.pathFor(source('/v$i.mp4'))).every((p) => p != null),
    );

    expect(server.peakConcurrent, lessThanOrEqualTo(2));
  });

  test('request headers are sent', () async {
    String? seen;
    final raw = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => raw.close(force: true));
    raw.listen((request) async {
      seen = request.headers.value('authorization');
      request.response.headers.contentType = ContentType.parse('video/mp4');
      request.response.add(_bytes(600));
      await request.response.close();
    });
    final cache = ReelVideoCache(directory: dir.path);
    final secured = ReelNetworkSource(
      'http://${raw.address.host}:${raw.port}/s.mp4',
      headers: const {'Authorization': 'Bearer token'},
    );

    cache.prefetch(secured);
    await _until(() => cache.pathFor(secured) != null);

    expect(seen, 'Bearer token');
  });

  test('clear removes everything', () async {
    server.routes['/a.mp4'] = _Route(_bytes(1000));
    final cache = ReelVideoCache(directory: dir.path);
    cache.prefetch(source('/a.mp4'));
    await _until(() => cache.pathFor(source('/a.mp4')) != null);

    await cache.clear();

    expect(cache.pathFor(source('/a.mp4')), isNull);
  });

  test('it reports that it is supported on this platform', () {
    expect(ReelVideoCache(directory: dir.path).isSupported, isTrue);
  });
}
