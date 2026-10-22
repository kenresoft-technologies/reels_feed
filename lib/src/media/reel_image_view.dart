import 'package:flutter/material.dart';

import 'reel_media.dart';
import 'reel_source.dart';

/// Builds a picture for [source]. Pass one to `ReelMediaCarousel.imageBuilder`
/// to load pictures with your own cache or loader.
typedef ReelImageBuilder = Widget Function(BuildContext context, ReelSource source, BoxFit fit);

/// Shows one picture full-bleed: chooses how it fills the screen, fades in once
/// loaded, and warms the image cache early so a swipe never shows a blank frame.
class ReelImageView extends StatefulWidget {
  /// Creates a view for [media], which must be an image.
  const ReelImageView({super.key, required this.media, this.fit, this.imageBuilder});

  /// The picture.
  final ReelMedia media;

  /// How the picture fills the space. When `null`, tall pictures fill it
  /// (cropping a little) and wide pictures fit inside it.
  final BoxFit? fit;

  /// Replaces the default picture widget.
  final ReelImageBuilder? imageBuilder;

  @override
  State<ReelImageView> createState() => _ReelImageViewState();
}

class _ReelImageViewState extends State<ReelImageView> {
  late ImageProvider<Object> _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  double? _aspect;

  @override
  void initState() {
    super.initState();
    _provider = widget.media.source.toImageProvider();
    _aspect = widget.media.aspectRatio;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant ReelImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.source != widget.media.source) {
      _provider = widget.media.source.toImageProvider();
      _aspect = widget.media.aspectRatio;
      _resolve();
    }
  }

  void _resolve() {
    _unlisten();
    if (widget.imageBuilder != null) return; // the custom loader does its own work
    final stream = _provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener((info, _) {
      final image = info.image;
      final aspect = image.height == 0 ? null : image.width / image.height;
      if (mounted && aspect != null && aspect != _aspect && widget.media.aspectRatio == null) {
        setState(() => _aspect = aspect);
      }
    }, onError: (_, _) {});
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  void _unlisten() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _unlisten();
    super.dispose();
  }

  BoxFit get _fit => widget.fit ?? ((_aspect ?? 1) < 1 ? BoxFit.cover : BoxFit.contain);

  @override
  Widget build(BuildContext context) {
    final custom = widget.imageBuilder;
    final Widget image = custom != null
        ? custom(context, widget.media.source, _fit)
        : Image(
            image: _provider,
            fit: _fit,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: child,
              );
            },
            errorBuilder: (context, error, stackTrace) =>
                const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48)),
          );
    return Semantics(
      image: true,
      label: widget.media.semanticLabel,
      child: SizedBox.expand(child: image),
    );
  }
}
