import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Une action de la carte ; son identité reste stable quand son libellé change.
class MapRailAction {
  const MapRailAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String id;
  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
}

/// Barre compacte de trois commandes visibles. Un glissé horizontal donne
/// accès aux autres actions, sans rotation ni changement d'échelle des icônes.
class MapActionRail extends StatefulWidget {
  const MapActionRail({
    super.key,
    required this.actions,
    this.initialActionId = 'navigation',
  });

  final List<MapRailAction> actions;
  final String initialActionId;

  @override
  State<MapActionRail> createState() => _MapActionRailState();
}

class _MapActionRailState extends State<MapActionRail>
    with SingleTickerProviderStateMixin {
  static const _step = 64.0;
  static const _buttonSize = 52.0;
  late final _position = AnimationController.unbounded(
    vsync: this,
    value: _initialIndex,
  );
  bool _dragging = false;

  double get _initialIndex {
    final index = widget.actions.indexWhere(
      (action) => action.id == widget.initialActionId,
    );
    return math.max(0, index).toDouble();
  }

  bool get _reduceMotion =>
      MediaQuery.disableAnimationsOf(context) ||
      View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;

  @override
  void didUpdateWidget(covariant MapActionRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.actions.map((action) => action.id).join(',');
    final after = widget.actions.map((action) => action.id).join(',');
    if (before != after ||
        oldWidget.initialActionId != widget.initialActionId) {
      _position.stop();
      _position.value = _initialIndex;
    }
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  void _snap(double target) {
    if (_reduceMotion) {
      _position.value = target;
    } else {
      _position.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _dragEnd(DragEndDetails details) {
    _dragging = false;
    final velocity = details.primaryVelocity ?? 0;
    final travel = velocity.abs() > 450 ? -velocity.sign : 0.0;
    _snap((_position.value + travel).roundToDouble());
  }

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) return const SizedBox.shrink();
    final count = widget.actions.length;
    final slots = count == 1 ? 1 : 3;
    final width = slots * _step + 16;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    return Semantics(
      label: 'Commandes de la carte',
      hint: 'Glisser horizontalement pour les alertes et le profil',
      onIncrease: () => _snap(_position.value.roundToDouble() + 1),
      onDecrease: () => _snap(_position.value.roundToDouble() - 1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) {
          _dragging = true;
          _position.stop();
        },
        onHorizontalDragUpdate: (details) {
          _position.value -= details.delta.dx / _step;
        },
        onHorizontalDragEnd: _dragEnd,
        onHorizontalDragCancel: () {
          _dragging = false;
          _snap(_position.value.roundToDouble());
        },
        child: SizedBox(
          width: width,
          height: 56,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF0D2238)
                    .withValues(alpha: ios ? 0.38 : 0.44),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0x25FFFFFF)),
              ),
              child: AnimatedBuilder(
                animation: _position,
                builder: (context, _) => Stack(
                  children: [
                    for (var index = 0; index < count; index++)
                      _action(index, width),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _action(int index, double width) {
    final count = widget.actions.length;
    final action = widget.actions[index];
    final half = count / 2;
    final bias = count.isEven ? 0.5 : 0.0;
    final relative =
        (index - _position.value + half + bias) % count - half - bias;
    // Aucun bouton caché ne reste cliquable ou annoncé par le lecteur d'écran.
    if (relative.abs() >= 2) return const SizedBox.shrink();
    final selected = relative.abs() < 0.5;
    return Positioned(
      key: ValueKey('map-action-${action.id}'),
      left: width / 2 + relative * _step - _buttonSize / 2,
      top: 2,
      width: _buttonSize,
      height: _buttonSize,
      child: ExcludeSemantics(
        excluding: relative.abs() > 1.5,
        child: IgnorePointer(
          ignoring: _dragging || relative.abs() > 1.5,
          child: Material(
            color: selected ? const Color(0x20FFFFFF) : Colors.transparent,
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: action.label,
              onPressed: action.onPressed,
              style: IconButton.styleFrom(
                foregroundColor: selected
                    ? const Color(0xFF80DFFF)
                    : Colors.white,
                disabledForegroundColor: Colors.white38,
                padding: const EdgeInsets.all(6),
              ),
              icon: action.icon,
            ),
          ),
        ),
      ),
    );
  }
}
