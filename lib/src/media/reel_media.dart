import 'package:flutter/foundation.dart';

import 'reel_source.dart';

/// Whether a [ReelMedia] is a picture or a video.
enum ReelMediaType {
  /// A still picture.
  image,

  /// A video.
  video,
}

/// One picture or video inside a post. A post with several of them shows as a
/// swipeable carousel.
///
/// ```dart
/// final media = [
///   ReelMedia.videoUrl('https://example.com/a.mp4', posterUrl: 'https://example.com/a.jpg'),
///   ReelMedia.imageUrl('https://example.com/b.jpg'),
/// ];
/// ```
@immutable
class ReelMedia {
  /// A picture from any [source].
  const ReelMedia.image(this.source, {this.aspectRatio, this.semanticLabel})
    : type = ReelMediaType.image,
      poster = null,
      loop = true;

  /// A video from any [source]. The optional [poster] shows until the first
  /// frame is ready, which hides the loading gap.
  const ReelMedia.video(
    this.source, {
    this.poster,
    this.aspectRatio,
    this.semanticLabel,
    this.loop = true,
  }) : type = ReelMediaType.video;

  /// A picture at a web address.
  ReelMedia.imageUrl(String url, {this.aspectRatio, this.semanticLabel})
    : type = ReelMediaType.image,
      source = ReelSource.network(url),
      poster = null,
      loop = true;

  /// A video at a web address, with an optional poster picture at [posterUrl].
  ReelMedia.videoUrl(
    String url, {
    String? posterUrl,
    this.aspectRatio,
    this.semanticLabel,
    this.loop = true,
  }) : type = ReelMediaType.video,
       source = ReelSource.network(url),
       poster = posterUrl == null ? null : ReelSource.network(posterUrl);

  /// Picture or video.
  final ReelMediaType type;

  /// Where the media is loaded from.
  final ReelSource source;

  /// For videos, a picture shown until the first frame is ready.
  final ReelSource? poster;

  /// Width divided by height, when known ahead of time. Used to pick how the
  /// media fills the screen before it has loaded.
  final double? aspectRatio;

  /// What a screen reader announces for this media.
  final String? semanticLabel;

  /// Whether a video starts over when it ends. Defaults to `true`.
  final bool loop;

  /// Whether this is a video.
  bool get isVideo => type == ReelMediaType.video;

  @override
  bool operator ==(Object other) =>
      other is ReelMedia &&
      other.type == type &&
      other.source == source &&
      other.poster == poster &&
      other.aspectRatio == aspectRatio &&
      other.semanticLabel == semanticLabel &&
      other.loop == loop;

  @override
  int get hashCode => Object.hash(type, source, poster, aspectRatio, semanticLabel, loop);
}
