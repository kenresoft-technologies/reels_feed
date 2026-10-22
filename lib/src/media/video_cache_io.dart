import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'reel_source.dart';
import 'reel_video_cache.dart';

/// Makes the cache that saves videos to disk. See [ReelVideoCache].
ReelVideoCache createVideoCache({
  String? directory,
  int maxBytes = 200 * 1024 * 1024,
  int maxFileBytes = 60 * 1024 * 1024,
  int maxConcurrentDownloads = 2,
}) => _IoVideoCache(
  directory: directory,
  maxBytes: maxBytes,
  maxFileBytes: maxFileBytes,
  maxConcurrentDownloads: maxConcurrentDownloads,
);

class _IoVideoCache implements ReelVideoCache {
  _IoVideoCache({
    String? directory,
    int maxBytes = 200 * 1024 * 1024,
    int maxFileBytes = 60 * 1024 * 1024,
    int maxConcurrentDownloads = 2,
  }) : assert(maxBytes > 0),
       assert(maxFileBytes > 0),
       assert(maxConcurrentDownloads > 0),
       _maxBytes = maxBytes,
       _maxFileBytes = maxFileBytes,
       _maxConcurrent = maxConcurrentDownloads,
       _directory = Directory(directory ?? '${Directory.systemTemp.path}/reels_feed_video_cache');

  final Directory _directory;
  final int _maxBytes;
  final int _maxFileBytes;
  final int _maxConcurrent;

  final Set<String> _downloading = <String>{};
  final Queue<ReelNetworkSource> _waiting = Queue<ReelNetworkSource>();
  // Addresses that are not plain video files, so they are not tried again.
  final Set<String> _skipped = <String>{};
  int _active = 0;
  bool _prepared = false;

  @override
  bool get isSupported => true;

  File _fileFor(ReelNetworkSource source) {
    final url = source.url;
    var extension = 'mp4';
    final path = Uri.tryParse(url)?.path ?? '';
    final dot = path.lastIndexOf('.');
    if (dot >= 0 && path.length - dot <= 6) {
      final candidate = path.substring(dot + 1).toLowerCase();
      if (RegExp(r'^[a-z0-9]{2,5}$').hasMatch(candidate)) extension = candidate;
    }
    return File('${_directory.path}/${_hash(url)}.$extension');
  }

  // A 64-bit FNV-1a hash: stable between runs, unlike Object.hash.
  static String _hash(String text) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(text)) {
      hash = (hash ^ byte) * 0x100000001b3;
    }
    return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }

  @override
  String? pathFor(ReelNetworkSource source) {
    try {
      final file = _fileFor(source);
      if (!file.existsSync()) return null;
      if (file.lengthSync() == 0) return null;
      file.setLastModifiedSync(DateTime.now()); // mark as recently used
      return file.path;
    } on FileSystemException {
      return null;
    }
  }

  @override
  void prefetch(ReelNetworkSource source) {
    final key = source.url;
    if (_skipped.contains(key) || _downloading.contains(key)) return;
    if (!(Uri.tryParse(key)?.hasScheme ?? false)) return;
    if (_fileFor(source).existsSync()) return;
    _downloading.add(key);
    _waiting.add(source);
    _pump();
  }

  void _pump() {
    while (_active < _maxConcurrent && _waiting.isNotEmpty) {
      final source = _waiting.removeFirst();
      _active += 1;
      unawaited(
        _download(source).whenComplete(() {
          _active -= 1;
          _downloading.remove(source.url);
          _pump();
        }),
      );
    }
  }

  Future<void> _download(ReelNetworkSource source) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    File? part;
    try {
      await _prepare();
      final file = _fileFor(source);
      part = File('${file.path}.part');

      final request = await client.getUrl(Uri.parse(source.url));
      source.headers.forEach(request.headers.set);
      final response = await request.close();
      if (response.statusCode != 200 || !_isPlainVideo(response)) {
        await response.drain<void>();
        if (response.statusCode == 200) _skipped.add(source.url);
        return;
      }
      if (response.contentLength > _maxFileBytes) {
        await response.drain<void>();
        _skipped.add(source.url);
        return;
      }

      final sink = part.openWrite();
      var total = 0;
      var tooBig = false;
      try {
        await for (final chunk in response) {
          total += chunk.length;
          if (total > _maxFileBytes) {
            tooBig = true;
            break;
          }
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      final complete =
          !tooBig && total > 0 && (response.contentLength < 0 || total == response.contentLength);
      if (!complete) {
        if (tooBig) _skipped.add(source.url);
        await _delete(part);
        return;
      }
      part.renameSync(file.path);
      await _trim();
    } on Object catch (error) {
      if (kDebugMode) debugPrint('reels_feed: could not cache ${source.url}: $error');
      if (part != null) await _delete(part);
    } finally {
      client.close(force: true);
    }
  }

  static bool _isPlainVideo(HttpClientResponse response) {
    final type = response.headers.contentType?.mimeType.toLowerCase() ?? '';
    if (type.contains('mpegurl') || type.contains('dash')) return false;
    return type.startsWith('video/') ||
        type == 'application/octet-stream' ||
        type == 'binary/octet-stream';
  }

  // Makes sure the folder exists and clears downloads that never finished.
  Future<void> _prepare() async {
    if (_prepared) return;
    _prepared = true;
    _directory.createSync(recursive: true);
    for (final entity in _directory.listSync()) {
      if (entity is File && entity.path.endsWith('.part')) {
        final age = DateTime.now().difference(entity.lastModifiedSync());
        if (age > const Duration(hours: 1)) await _delete(entity);
      }
    }
  }

  // Deletes the least recently used videos until the cache fits.
  Future<void> _trim() async {
    final files = <(File, int, DateTime)>[];
    var total = 0;
    for (final entity in _directory.listSync()) {
      if (entity is! File || entity.path.endsWith('.part')) continue;
      final length = entity.lengthSync();
      total += length;
      files.add((entity, length, entity.lastModifiedSync()));
    }
    if (total <= _maxBytes) return;
    files.sort((a, b) => a.$3.compareTo(b.$3));
    for (final (file, length, _) in files) {
      if (total <= _maxBytes) break;
      if (await _delete(file)) total -= length;
    }
  }

  Future<bool> _delete(File file) async {
    try {
      if (file.existsSync()) file.deleteSync();
      return true;
    } on FileSystemException {
      return false; // in use on this platform; the next trim will try again
    }
  }

  @override
  Future<void> clear() async {
    _waiting.clear();
    _skipped.clear();
    if (_directory.existsSync()) {
      try {
        _directory.deleteSync(recursive: true);
      } on FileSystemException {
        // Some files are in use; they go on the next clear.
      }
    }
    _prepared = false;
  }
}
