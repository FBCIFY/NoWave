import 'package:flutter/material.dart';

/// Fait entrer l'étape suivante par la droite pendant que la précédente sort
/// par la gauche.
class FlowTransition extends StatefulWidget {
  final int step;
  final Widget child;

  const FlowTransition({super.key, required this.step, required this.child});

  @override
  State<FlowTransition> createState() => _FlowTransitionState();
}

class _FlowTransitionState extends State<FlowTransition> {
  bool _forward = true;

  @override
  void didUpdateWidget(FlowTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.step != oldWidget.step) {
      _forward = widget.step > oldWidget.step;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        layoutBuilder: (currentChild, previousChildren) => Stack(
          fit: StackFit.expand,
          children: [...previousChildren, ?currentChild],
        ),
        transitionBuilder: (child, animation) => AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            final offset = 1 - animation.value;
            final entering = animation.status != AnimationStatus.reverse;
            final direction = _forward ? 1.0 : -1.0;
            return FractionalTranslation(
              translation: Offset(
                (entering ? direction : -direction) * offset,
                0,
              ),
              child: child,
            );
          },
        ),
        child: KeyedSubtree(key: ValueKey(widget.step), child: widget.child),
      ),
    );
  }
}
