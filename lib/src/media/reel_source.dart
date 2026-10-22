import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import 'platform_file_stub.dart' if (dart.library.io) 'platform_file_io.dart';

/// Where a picture or a video comes from: a web address, an app asset or a file
/// on the device.
///
/// ```dart
/// const ReelSource.network('https://example.com/clip.mp4');
/// const ReelSource.asset('assets/intro.mp4');
/// const ReelSource.file('/storage/emulated/0/Movies/clip.mp4');
/// ```
@immutable
sealed class ReelSource {
  /// Base constructor for the concrete sources.
  const ReelSource();

  /// A picture or video fetched over the network. [headers] are sent with the
  /// request (for example an `Authorization` header).
  const factory ReelSource.network(String url, {Map<String, String> headers}) = ReelNetworkSource;

  /// A picture or video bundled with the app. Pass [package] for assets that
  /// belong to another package.
  const factory ReelSource.asset(String name, {String? package}) = ReelAssetSource;

  /// A picture or video stored on the device. Not available in a browser, where
  /// using it throws an [UnsupportedError].
  const factory ReelSource.file(String path) = ReelFileSource;

  /// A stable identity for this source, used to share one loaded video between
  /// the places that show it.
  String get key;

  /// The Flutter image provider for this source, for showing it as a picture.
  ImageProvider<Object> toImageProvider() => switch (this) {
    ReelNetworkSource(:final url, :final headers) => NetworkImage(url, headers: headers),
    ReelAssetSource(:final name, :final package) => AssetImage(name, package: package),
    ReelFileSource(:final path) => fileImageProvider(path),
  };

  @override
  bool operator ==(Object other) =>
      other is ReelSource && other.runtimeType == runtimeType && other.key == key;

  @override
  int get hashCode => Object.hash(runtimeType, key);

  @override
  String toString() => '$runtimeType($key)';
}

/// A [ReelSource] fetched over the network. See [ReelSource.network].
final class ReelNetworkSource extends ReelSource {
  /// Creates a network source.
  const ReelNetworkSource(this.url, {this.headers = const <String, String>{}});

  /// The web address.
  final String url;

  /// Extra request headers.
  final Map<String, String> headers;

  @override
  String get key => url;
}

/// A [ReelSource] bundled with the app. See [ReelSource.asset].
final class ReelAssetSource extends ReelSource {
  /// Creates an asset source.
  const ReelAssetSource(this.name, {this.package});

  /// The asset path, as declared in `pubspec.yaml`.
  final String name;

  /// The package the asset belongs to, if not the app.
  final String? package;

  @override
  String get key => package == null ? name : 'packages/$package/$name';
}

/// A [ReelSource] stored on the device. See [ReelSource.file].
final class ReelFileSource extends ReelSource {
  /// Creates a file source.
  const ReelFileSource(this.path);

  /// The file path.
  final String path;

  @override
  String get key => path;
}

/// Builds the player behind a video [source]. Used by the video pool; the
/// defaults cover network, asset and file sources.
VideoPlayerController createReelVideoController(ReelSource source, {required bool mixWithOthers}) {
  final options = VideoPlayerOptions(mixWithOthers: mixWithOthers);
  return switch (source) {
    ReelNetworkSource(:final url, :final headers) => VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: headers,
      videoPlayerOptions: options,
    ),
    ReelAssetSource(:final name, :final package) => VideoPlayerController.asset(
      name,
      package: package,
      videoPlayerOptions: options,
    ),
    ReelFileSource(:final path) => fileVideoController(path, options),
  };
}
