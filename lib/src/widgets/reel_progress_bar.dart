import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// A thin playback bar for a video: how much has played, how much is buffered,
/// and drag-to-seek.
///
/// It grows while it is being dragged, which makes it easy to grab without
/// taking space when idle. [ReelMediaCarousel] shows one under each video; use
/// this directly for custom layouts.
class ReelProgressBar extends StatefulWidget {
  /// Creates a bar for [controller].
  const ReelProgressBar({
    super.key,
    required this.controller,
    this.height = 2.5,
    this.activeHeight = 7,
    this.playedColor = Colors.white,
    this.bufferedColor = const Color(0x66FFFFFF),
    this.backgroundColor = const Color(0x33FFFFFF),
    this.onScrubStart,
    this.onScrubEnd,
  });

  /// The video to show and seek.
  final VideoPlayerController controller;

  /// The bar's thickness at rest.
  final double height;

  /// The bar's thickness while dragging.
  final double activeHeight;

  /// The part already played.
  final Color playedColor;

  /// The part downloaded ahead of the playhead.
  final Color bufferedColor;

  /// The whole track.
  final Color backgroundColor;

  /// Called when a drag starts, so playback can hold still.
  final VoidCallback? onScrubStart;

  /// Called when a drag ends.
  final VoidCallback? onScrubEnd;

  @override
  State<ReelProgressBar> createState() => _ReelProgressBarState();
}

class _ReelProgressBarState extends State<ReelProgressBar> {
  bool _scrubbing = false;
  double? _scrubFraction;

  double _fractionAt(double dx, double width) => width <= 0 ? 0 : (dx / width).clamp(0.0, 1.0);

  void _seekTo(double fraction) {
    final total = widget.controller.value.duration;
    if (total == Duration.zero) return;
    widget.controller.seekTo(total * fraction);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Semantics(
          label: 'Video progress',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (details) {
              widget.onScrubStart?.call();
              final fraction = _fractionAt(details.localPosition.dx, width);
              setState(() {
                _scrubbing = true;
                _scrubFraction = fraction;
              });
              _seekTo(fraction);
            },
            onHorizontalDragUpdate: (details) {
              final fraction = _fractionAt(details.localPosition.dx, width);
              setState(() => _scrubFraction = fraction);
              _seekTo(fraction);
            },
            onHorizontalDragEnd: (_) {
              setState(() {
                _scrubbing = false;
                _scrubFraction = null;
              });
              widget.onScrubEnd?.call();
            },
            onTapDown: (details) => _seekTo(_fractionAt(details.localPosition.dx, width)),
            child: SizedBox(
              height: 24,
              width: double.infinity,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: widget.controller,
                  builder: (context, value, _) {
                    final total = value.duration.inMilliseconds;
                    final played =
                        _scrubFraction ??
                        (total == 0 ? 0.0 : (value.position.inMilliseconds / total).clamp(0.0, 1.0));
                    final buffered = value.buffered.isEmpty || total == 0
                        ? 0.0
                        : (value.buffered.last.end.inMilliseconds / total).clamp(0.0, 1.0);
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      height: _scrubbing ? widget.activeHeight : widget.height,
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _BarPainter(
                          played: played,
                          buffered: buffered,
                          playedColor: widget.playedColor,
                          bufferedColor: widget.bufferedColor,
                          backgroundColor: widget.backgroundColor,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.played,
    required this.buffered,
    required this.playedColor,
    required this.bufferedColor,
    required this.backgroundColor,
  });

  final double played;
  final double buffered;
  final Color playedColor;
  final Color bufferedColor;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = backgroundColor);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width * buffered, size.height),
      Paint()..color = bufferedColor,
    );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width * played, size.height), Paint()..color = playedColor);
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.played != played ||
      old.buffered != buffered ||
      old.playedColor != playedColor ||
      old.bufferedColor != bufferedColor ||
      old.backgroundColor != backgroundColor;
}
