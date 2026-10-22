import 'package:flutter/material.dart';

/// A soft dark gradient along an edge, so white text and icons stay readable
/// over bright video. It ignores touches.
///
/// ```dart
/// Stack(children: [
///   ReelMediaCarousel(media: media),
///   const ReelScrim(),               // bottom, behind the caption
///   const ReelScrim.top(),           // top, behind the status bar
///   caption,
/// ])
/// ```
class ReelScrim extends StatelessWidget {
  /// A scrim along the bottom edge.
  const ReelScrim({super.key, this.height = 280, this.opacity = 0.6}) : _top = false;

  /// A scrim along the top edge.
  const ReelScrim.top({super.key, this.height = 140, this.opacity = 0.4}) : _top = true;

  /// How tall the gradient is.
  final double height;

  /// How dark it is at the edge, from 0 to 1.
  final double opacity;

  final bool _top;

  @override
  Widget build(BuildContext context) {
    final color = Colors.black.withValues(alpha: opacity);
    return Positioned(
      left: 0,
      right: 0,
      top: _top ? 0 : null,
      bottom: _top ? null : 0,
      height: height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: _top ? Alignment.topCenter : Alignment.bottomCenter,
              end: _top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [color, Colors.transparent],
            ),
          ),
        ),
      ),
    );
  }
}
