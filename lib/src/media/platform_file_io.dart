import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:video_player/video_player.dart';

/// A picture read from a file on the device.
ImageProvider<Object> fileImageProvider(String path) => FileImage(File(path));

/// A video player for a file on the device.
VideoPlayerController fileVideoController(String path, VideoPlayerOptions options) =>
    VideoPlayerController.file(File(path), videoPlayerOptions: options);
