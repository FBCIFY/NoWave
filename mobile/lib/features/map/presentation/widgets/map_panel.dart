import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Bord de l'écran où le panneau est posé.
enum MapPanelSide { top, bottom }

/// Panneau posé sur la carte, sans voile : l'autre moitié reste à la carte,
/// qui garde ses gestes. Jamais plus de la moitié de l'écran, marge comprise.
class MapPanel extends StatelessWidget {
  const MapPanel({
    super.key,
    required this.side,
    required this.onClose,
    required this.child,
    this.onBack,
    this.title,
    this.actions = const [],
  });

  final MapPanelSide side;
  final VoidCallback onClose;

  /// Flèche de retour en haut à gauche ; le retour système la suit aussi.
  final VoidCallback? onBack;
  final String? title;
  final List<Widget> actions;

  /// Contenu défilant ; il ne reçoit plus la marge du bord de l'écran.
  final Widget child;

  static double maxHeightFor(
    MediaQueryData mediaQuery, {
    MapPanelSide side = MapPanelSide.bottom,
  }) => math.max(0, mediaQuery.size.height / 2 - _margin(mediaQuery, side));

  static double _margin(MediaQueryData mediaQuery, MapPanelSide side) =>
      switch (side) {
        MapPanelSide.top => mediaQuery.padding.top + 8,
        MapPanelSide.bottom => math.max(12, mediaQuery.padding.bottom),
      };

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final top = side == MapPanelSide.top;
    final margin = _margin(mediaQuery, side);
    final header = _PanelHeader(
      onClose: onClose,
      onBack: onBack,
      title: title,
      actions: actions,
      // En bas, la poignée est dans l'en-tête ; en haut, sous le contenu.
      handle: !top,
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) (onBack ?? onClose)();
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          top ? margin : 0,
          12,
          top ? 0 : margin,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: maxHeightFor(mediaQuery, side: side),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x290D2238),
                  blurRadius: 28,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  header,
                  Flexible(
                    // La marge du bord est déjà hors du panneau.
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      removeBottom: true,
                      child: child,
                    ),
                  ),
                  if (top) _BottomHandle(onClose: onClose),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Retour, titre, actions et croix ; en bas, glisser la poignée vers le bas
/// ferme aussi le panneau.
class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.onClose,
    required this.onBack,
    required this.title,
    required this.actions,
    required this.handle,
  });

  final VoidCallback onClose;
  final VoidCallback? onBack;
  final String? title;
  final List<Widget> actions;
  final bool handle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: handle
          ? (details) {
              if ((details.primaryVelocity ?? 0) > 250) onClose();
            }
          : null,
      child: SizedBox(
        height: 48,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (handle) const _Grip(),
            Row(
              children: [
                if (onBack != null)
                  IconButton(
                    tooltip: 'Retour',
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                  )
                else
                  const SizedBox(width: 16),
                Expanded(
                  child: title == null
                      ? const SizedBox.shrink()
                      : Text(
                          title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                ),
                ...actions,
                IconButton(
                  tooltip: 'Fermer',
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Panneau du haut : la poignée est sous le contenu, glissée vers le haut
/// elle ferme le panneau.
class _BottomHandle extends StatelessWidget {
  const _BottomHandle({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < -250) onClose();
      },
      child: const SizedBox(
        height: 24,
        width: double.infinity,
        child: Center(child: _Grip()),
      ),
    );
  }
}

class _Grip extends StatelessWidget {
  const _Grip();

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 4,
    decoration: BoxDecoration(
      color: const Color(0xFFD5DCE6),
      borderRadius: BorderRadius.circular(2),
    ),
  );
}
