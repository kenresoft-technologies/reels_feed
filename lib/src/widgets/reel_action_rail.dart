import 'package:flutter/material.dart';

import 'format_count.dart';
import 'reel_shadows.dart';

/// One button in a [ReelActionRail]: an icon with an optional count under it.
@immutable
class ReelAction {
  /// Creates an action.
  const ReelAction({
    required this.icon,
    required this.semanticLabel,
    this.activeIcon,
    this.count,
    this.label,
    this.isActive = false,
    this.activeColor,
    this.onTap,
  });

  /// The icon at rest.
  final IconData icon;

  /// The icon while [isActive], for example a filled heart. Defaults to [icon].
  final IconData? activeIcon;

  /// A number shown under the icon, shortened (`1.2K`).
  final int? count;

  /// Text shown under the icon instead of [count].
  final String? label;

  /// Whether the action is switched on, for example a liked post.
  final bool isActive;

  /// The icon colour while [isActive]. Defaults to a red.
  final Color? activeColor;

  /// What a screen reader announces.
  final String semanticLabel;

  /// Called when the action is tapped.
  final VoidCallback? onTap;
}

/// A vertical column of actions (like, comment, share, save) for the side of a
/// post. Switching an action on bounces its icon.
///
/// ```dart
/// ReelActionRail(actions: [
///   ReelAction(icon: Icons.favorite_border, activeIcon: Icons.favorite,
///       isActive: liked, count: likes, semanticLabel: 'Like', onTap: toggleLike),
///   ReelAction(icon: Icons.chat_bubble_outline, count: comments,
///       semanticLabel: 'Comments', onTap: openComments),
///   ReelAction(icon: Icons.share_outlined, semanticLabel: 'Share', onTap: share),
/// ])
/// ```
class ReelActionRail extends StatelessWidget {
  /// Creates a rail.
  const ReelActionRail({
    super.key,
    required this.actions,
    this.spacing = 18,
    this.iconSize = 30,
    this.color = Colors.white,
    this.textStyle,
    this.shadows = reelCheapShadow,
  });

  /// The buttons, top to bottom.
  final List<ReelAction> actions;

  /// Space between the buttons.
  final double spacing;

  /// The icon size.
  final double iconSize;

  /// The icon and text colour.
  final Color color;

  /// The count text style. Defaults to a small bold style with a shadow.
  final TextStyle? textStyle;

  /// Shadows under the icons and counts. The default is a cheap hard shadow;
  /// a blurred one (for example `Shadow(blurRadius: 8)`) looks softer but costs
  /// noticeably more while scrolling.
  final List<Shadow> shadows;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) SizedBox(height: spacing),
          _ActionButton(
            action: actions[i],
            iconSize: iconSize,
            color: color,
            textStyle: textStyle,
            shadows: shadows,
          ),
        ],
      ],
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.action,
    required this.iconSize,
    required this.color,
    required this.shadows,
    this.textStyle,
  });

  final ReelAction action;
  final double iconSize;
  final Color color;
  final TextStyle? textStyle;
  final List<Shadow> shadows;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void didUpdateWidget(covariant _ActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.action.isActive && widget.action.isActive) {
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (!reduce) _bounce.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  double _scale(double t) =>
      1 +
      0.35 * (t < 0.5 ? Curves.easeOut.transform(t * 2) : 1 - Curves.easeIn.transform((t - 0.5) * 2));

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final text = action.label ?? (action.count == null ? null : formatReelCount(action.count!));
    final iconColor = action.isActive ? (action.activeColor ?? Colors.redAccent) : widget.color;
    return Semantics(
      button: true,
      label: action.semanticLabel,
      value: text,
      selected: action.isActive,
      child: ExcludeSemantics(
        child: InkResponse(
          onTap: action.onTap,
          radius: 32,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _bounce,
                  builder: (context, child) =>
                      Transform.scale(scale: _scale(_bounce.value), child: child),
                  child: Icon(
                    action.isActive ? (action.activeIcon ?? action.icon) : action.icon,
                    color: iconColor,
                    size: widget.iconSize,
                    shadows: widget.shadows,
                  ),
                ),
                if (text != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    text,
                    style:
                        widget.textStyle ??
                        TextStyle(
                          color: widget.color,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          shadows: widget.shadows,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
