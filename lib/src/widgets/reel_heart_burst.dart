import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A layer that shows a heart bursting up from a point, like a double-tap to
/// like. Put it over your content and call [ReelHeartBurstState.burst] with the
/// tap position.
///
/// [ReelMediaCarousel] already includes one; use this directly for custom
/// layouts.
///
/// ```dart
/// final burst = GlobalKey<ReelHeartBurstState>();
/// // ...
/// Stack(children: [content, ReelHeartBurst(key: burst)]);
/// // on double tap:
/// burst.currentState?.burst(details.localPosition);
/// ```
class ReelHeartBurst extends StatefulWidget {
  /// Creates the layer.
  const ReelHeartBurst({
    super.key,
    this.child,
    this.size = 96,
    this.duration = const Duration(milliseconds: 750),
  });

  /// What bursts. Defaults to a red heart.
  final Widget? child;

  /// The size of the heart.
  final double size;

  /// How long one burst lasts.
  final Duration duration;

  @override
  State<ReelHeartBurst> createState() => ReelHeartBurstState();
}

/// The state of a [ReelHeartBurst]. Use [burst] to show a heart.
class ReelHeartBurstState extends State<ReelHeartBurst> with TickerProviderStateMixin {
  final List<_Burst> _bursts = <_Burst>[];
  final math.Random _random = math.Random();

  /// Shows a heart centred on [position], in this layer's own coordinates.
  void burst(Offset position) {
    final controller = AnimationController(vsync: this, duration: widget.duration);
    final burst = _Burst(controller, position, (_random.nextDouble() - 0.5) * 0.5);
    setState(() => _bursts.add(burst));
    controller.forward().whenComplete(() {
      if (!mounted) return;
      setState(() => _bursts.remove(burst));
      controller.dispose();
    });
  }

  @override
  void dispose() {
    for (final burst in _bursts) {
      burst.controller.dispose();
    }
    _bursts.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final heart =
        widget.child ??
        Icon(
          Icons.favorite,
          color: Colors.redAccent,
          size: widget.size,
          shadows: const [Shadow(blurRadius: 18, color: Colors.black38)],
        );
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final burst in _bursts)
              AnimatedBuilder(
                animation: burst.controller,
                child: heart,
                builder: (context, child) {
                  final t = burst.controller.value;
                  final scale = reduceMotion ? 1.0 : _scale(t);
                  final rise = reduceMotion ? 0.0 : -70 * Curves.easeOut.transform(t);
                  final opacity = t < 0.6 ? 1.0 : 1 - (t - 0.6) / 0.4;
                  return Positioned(
                    left: burst.position.dx - widget.size / 2,
                    top: burst.position.dy - widget.size / 2 + rise,
                    child: Opacity(
                      opacity: opacity.clamp(0.0, 1.0),
                      child: Transform.rotate(
                        angle: burst.tilt,
                        child: Transform.scale(scale: scale, child: child),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // Pops in with a little overshoot, then settles.
  double _scale(double t) {
    if (t < 0.25) return Curves.easeOutBack.transform(t / 0.25) * 1.15;
    if (t < 0.4) return 1.15 - 0.15 * ((t - 0.25) / 0.15);
    return 1.0;
  }
}

class _Burst {
  _Burst(this.controller, this.position, this.tilt);

  final AnimationController controller;
  final Offset position;
  final double tilt;
}
