import 'reel_source.dart';
import 'reel_video_cache.dart';

/// Makes a cache that saves nothing, for platforms without file storage (the web).
ReelVideoCache createVideoCache({
  String? directory,
  int maxBytes = 0,
  int maxFileBytes = 0,
  int maxConcurrentDownloads = 0,
}) => const _NoVideoCache();

class _NoVideoCache implements ReelVideoCache {
  const _NoVideoCache();

  @override
  bool get isSupported => false;

  @override
  String? pathFor(ReelNetworkSource source) => null;

  @override
  void prefetch(ReelNetworkSource source) {}

  @override
  Future<void> clear() async {}
}
