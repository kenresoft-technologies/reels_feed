import 'reel_source.dart';
import 'video_cache_stub.dart' if (dart.library.io) 'video_cache_io.dart';

/// Saves network videos to the device so a video you have seen plays again
/// instantly, without using the network, even many posts later.
///
/// The big reels apps do the same. Here it works like this: a video that is not
/// saved yet streams as usual while a copy downloads in the background; the next
/// time it is needed it plays from the saved file. The cache keeps itself under
/// [maxBytes] by deleting the least recently used videos, and stores its files
/// where the system may clear them when it needs space.
///
/// [ReelsFeed] uses one by default (turn it off with `cacheVideos: false`). Use
/// it directly to share one between feeds or change its limits:
///
/// ```dart
/// final cache = ReelVideoCache(maxBytes: 500 * 1024 * 1024);
/// final pool = ReelVideoPool(cache: cache);
/// ```
///
/// Only plain video files are saved. Streaming playlists (HLS and DASH) and
/// responses that are not video are skipped and keep streaming. On the web there
/// is no file storage, so the cache does nothing there and the browser's own
/// cache applies.
abstract interface class ReelVideoCache {
  /// Creates a cache.
  ///
  /// [directory] is where files go (the app's temporary directory by default).
  /// [maxBytes] is the most it keeps in total, and [maxFileBytes] the largest
  /// single video it will save. At most [maxConcurrentDownloads] videos download
  /// at once.
  factory ReelVideoCache({
    String? directory,
    int maxBytes = 200 * 1024 * 1024,
    int maxFileBytes = 60 * 1024 * 1024,
    int maxConcurrentDownloads = 2,
  }) => createVideoCache(
    directory: directory,
    maxBytes: maxBytes,
    maxFileBytes: maxFileBytes,
    maxConcurrentDownloads: maxConcurrentDownloads,
  );

  /// Whether this platform can save videos (`false` on the web).
  bool get isSupported;

  /// The path of the saved copy of [source], or `null` if it is not saved yet.
  String? pathFor(ReelNetworkSource source);

  /// Starts saving [source] in the background if it is not saved or already
  /// downloading. Safe to call repeatedly.
  void prefetch(ReelNetworkSource source);

  /// Deletes every saved video.
  Future<void> clear();
}
