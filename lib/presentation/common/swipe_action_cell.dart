import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/vault_colors.dart';

/// One button revealed by [SwipeActionCell] on the right edge of a row.
class SwipeAction {
  const SwipeAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;

  /// Short caption under the icon ("操作" / "删除"). Kept to two Han
  /// characters so it still fits inside a single grid cell.
  final String label;

  /// Runs after the row has closed itself again.
  final VoidCallback onPressed;

  /// Paints the button with the theme error colour (delete / purge forever).
  final bool destructive;
}

/// Reveals [actions] on the **right** when the child is dragged to the left.
///
/// Gesture model (the familiar "swipe to delete" row):
/// * drag left → the child slides out, buttons appear on the right edge;
/// * release past half way, or flick, → the row stays open;
/// * tap an action → the row closes and [SwipeAction.onPressed] runs;
/// * tap the child while open → the caller closes it (see [open]).
///
/// [open] is owned by the parent so a grid can keep a single row open at a
/// time; the cell reports gesture-driven open/close through [onOpenChanged].
///
/// The child is translated with [Transform], which moves its hit area too, so
/// the revealed buttons stay tappable while the poster only occupies its
/// remaining (clipped) part.
class SwipeActionCell extends StatefulWidget {
  const SwipeActionCell({
    super.key,
    required this.child,
    required this.actions,
    this.enabled = true,
    this.open = false,
    this.onOpenChanged,
  });

  final Widget child;
  final List<SwipeAction> actions;

  /// When false (e.g. while the grid is in selection mode) the drag gesture is
  /// not registered at all, so the row cannot be swiped open.
  final bool enabled;

  /// Parent-owned open state.
  final bool open;

  /// Called when a drag or an action tap opened / closed this row.
  final ValueChanged<bool>? onOpenChanged;

  @override
  State<SwipeActionCell> createState() => _SwipeActionCellState();
}

class _SwipeActionCellState extends State<SwipeActionCell>
    with SingleTickerProviderStateMixin {
  static const Duration _settleDuration = Duration(milliseconds: 180);

  /// Share of the cell width one button wants (clamped in [build]).
  static const double _actionWidthFactor = 0.34;
  static const double _minActionWidth = 44;
  static const double _maxActionWidth = 88;

  /// The poster must stay visible while the row is open.
  static const double _maxStripFactor = 0.78;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _settleDuration,
    value: widget.open ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant SwipeActionCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open != oldWidget.open) {
      _controller.animateTo(widget.open ? 1 : 0, curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Animates to [open] and tells the parent when the state really changed.
  void _settle(bool open) {
    _controller.animateTo(open ? 1 : 0, curve: Curves.easeOutCubic);
    if (widget.open != open) widget.onOpenChanged?.call(open);
  }

  void _onDragUpdate(DragUpdateDetails details, double strip) {
    if (strip <= 0) return;
    _controller.value =
        (_controller.value - details.delta.dx / strip).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    if (velocity < -kMinFlingVelocity) {
      _settle(true);
    } else if (velocity > kMinFlingVelocity) {
      _settle(false);
    } else {
      _settle(_controller.value >= 0.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.actions;
    if (actions.isEmpty) return widget.child;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (!width.isFinite || width <= 0) return widget.child;

        // Buttons must not eat the whole tile: cap the revealed strip so the
        // poster stays visible while the row is open.
        final maxStrip = width * _maxStripFactor;
        final actionWidth = math.min(
          math.max(width * _actionWidthFactor, _minActionWidth),
          math.min(_maxActionWidth, maxStrip / actions.length),
        );
        final strip = actionWidth * actions.length;

        final row = widget.child;
        final dragArea = widget.enabled
            ? GestureDetector(
                behavior: HitTestBehavior.deferToChild,
                onHorizontalDragUpdate: (details) =>
                    _onDragUpdate(details, strip),
                onHorizontalDragEnd: _onDragEnd,
                child: row,
              )
            : row;

        return Stack(
          children: [
            PositionedDirectional(
              end: 0,
              top: 0,
              bottom: 0,
              width: strip,
              child: Row(
                children: [
                  for (final action in actions)
                    SizedBox(
                      width: actionWidth,
                      child: _SwipeActionButton(
                        action: action,
                        onTap: () {
                          _settle(false);
                          action.onPressed();
                        },
                      ),
                    ),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: _controller,
              child: dragArea,
              builder: (context, child) => Transform.translate(
                offset: Offset(-strip * _controller.value, 0),
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SwipeActionButton extends StatelessWidget {
  const _SwipeActionButton({required this.action, required this.onTap});

  final SwipeAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background =
        action.destructive ? scheme.error : context.vaultColors.chrome;
    final foreground = action.destructive ? scheme.onError : Colors.white;

    return Material(
      color: background,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: 20, color: foreground),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  action.label,
                  maxLines: 1,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

