import 'package:flutter/painting.dart';
import 'package:video_player/video_player.dart';

/// Files do not exist in a browser, so there is no picture to build.
ImageProvider<Object> fileImageProvider(String path) => throw UnsupportedError(
  'ReelSource.file is not available on the web. Use ReelSource.network instead.',
);

/// Files do not exist in a browser, so there is no player to build.
VideoPlayerController fileVideoController(String path, VideoPlayerOptions options) =>
    throw UnsupportedError(
      'ReelSource.file is not available on the web. Use ReelSource.network instead.',
    );
