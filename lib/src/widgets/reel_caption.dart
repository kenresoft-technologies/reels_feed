import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A caption that shows a few lines and expands on tap, with tappable
/// `#hashtags`, `@mentions` and links.
///
/// ```dart
/// ReelCaption(
///   text: post.caption,
///   onHashtagTap: (tag) => openTag(tag),
///   onMentionTap: (name) => openProfile(name),
/// )
/// ```
class ReelCaption extends StatefulWidget {
  /// Creates a caption.
  const ReelCaption({
    super.key,
    required this.text,
    this.maxLines = 2,
    this.style,
    this.linkStyle,
    this.moreLabel = 'more',
    this.lessLabel = 'less',
    this.onHashtagTap,
    this.onMentionTap,
    this.onLinkTap,
  }) : assert(maxLines > 0);

  /// The caption text.
  final String text;

  /// How many lines show before the caption is cut off.
  final int maxLines;

  /// The text style. Defaults to white with a soft shadow.
  final TextStyle? style;

  /// The style of hashtags, mentions and links. Defaults to bold.
  final TextStyle? linkStyle;

  /// The label that expands a long caption.
  final String moreLabel;

  /// The label that collapses it again.
  final String lessLabel;

  /// Called with the tag, without the `#`.
  final ValueChanged<String>? onHashtagTap;

  /// Called with the name, without the `@`.
  final ValueChanged<String>? onMentionTap;

  /// Called with the address.
  final ValueChanged<String>? onLinkTap;

  @override
  State<ReelCaption> createState() => _ReelCaptionState();
}

final RegExp _tokens = RegExp(r'(#[\p{L}\p{N}_]+)|(@[\p{L}\p{N}_.]+)|(https?://[^\s]+)', unicode: true);

class _ReelCaptionState extends State<ReelCaption> {
  bool _expanded = false;
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  TextSpan _spans(TextStyle base, TextStyle link) {
    _disposeRecognizers();
    final children = <InlineSpan>[];
    var last = 0;
    for (final match in _tokens.allMatches(widget.text)) {
      if (match.start > last) children.add(TextSpan(text: widget.text.substring(last, match.start)));
      final value = match.group(0)!;
      VoidCallback? onTap;
      if (match.group(1) != null && widget.onHashtagTap != null) {
        onTap = () => widget.onHashtagTap!(value.substring(1));
      } else if (match.group(2) != null && widget.onMentionTap != null) {
        onTap = () => widget.onMentionTap!(value.substring(1));
      } else if (match.group(3) != null && widget.onLinkTap != null) {
        onTap = () => widget.onLinkTap!(value);
      }
      TapGestureRecognizer? recognizer;
      if (onTap != null) {
        recognizer = TapGestureRecognizer()..onTap = onTap;
        _recognizers.add(recognizer);
      }
      children.add(TextSpan(text: value, style: link, recognizer: recognizer));
      last = match.end;
    }
    if (last < widget.text.length) children.add(TextSpan(text: widget.text.substring(last)));
    return TextSpan(style: base, children: children);
  }

  @override
  Widget build(BuildContext context) {
    final base =
        widget.style ??
        const TextStyle(
          color: Colors.white,
          fontSize: 14,
          height: 1.3,
          shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
        );
    final link = (widget.linkStyle ?? const TextStyle(fontWeight: FontWeight.w700)).copyWith(
      color: widget.linkStyle?.color ?? base.color,
    );
    final span = _spans(base, link);

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: span,
          maxLines: widget.maxLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();

        final text = Text.rich(
          span,
          maxLines: _expanded ? null : widget.maxLines,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
        );
        if (!overflows && !_expanded) return text;
        return Semantics(
          button: true,
          hint: _expanded ? widget.lessLabel : widget.moreLabel,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topLeft,
              curve: Curves.easeOut,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  text,
                  Text(
                    _expanded ? widget.lessLabel : widget.moreLabel,
                    style: base.copyWith(color: Colors.white70, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
