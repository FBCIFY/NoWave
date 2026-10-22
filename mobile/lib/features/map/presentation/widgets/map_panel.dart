import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Bord de l'écran où le panneau est posé.
enum MapPanelSide { top, bottom }

typedef MapPanelScrollableBuilder = Widget Function(
  BuildContext context,
  ScrollController scrollController,
  ValueChanged<double> onContentHeightChanged,
);

/// Consultation au-dessus de la carte. Un contenu défilant peut agrandir
/// le panneau avant de défiler, puis le réduire jusqu'à sa fermeture.
class MapPanel extends StatefulWidget {
  const MapPanel({
    super.key,
    required this.side,
    required this.onClose,
    this.child,
    this.scrollableBuilder,
    this.onBack,
    this.title,
    this.actions = const [],
    this.showCloseButton = true,
    this.dismissRequested = false,
    this.backgroundColor,
    this.extendToBottom = false,
  }) : assert((child == null) != (scrollableBuilder == null)),
       assert(scrollableBuilder == null || side == MapPanelSide.bottom);

  final MapPanelSide side;
  final VoidCallback onClose;
  final VoidCallback? onBack;
  final String? title;
  final List<Widget> actions;
  final Widget? child;
  final MapPanelScrollableBuilder? scrollableBuilder;
  final bool showCloseButton;

  /// Conserve le contenu jusqu'à la fin de l'animation de sortie.
  final bool dismissRequested;
  final Color? backgroundColor;

  /// Prolonge le fond jusqu'en bas et laisse le contenu gérer sa zone sûre.
  final bool extendToBottom;

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
  State<MapPanel> createState() => _MapPanelState();
}

class _MapPanelState extends State<MapPanel>
    with SingleTickerProviderStateMixin {
  final _surfaceKey = GlobalKey();
  late final _offset = AnimationController.unbounded(vsync: this);
  final _sheet = DraggableScrollableController();
  final _visibleExtent = ValueNotifier<double?>(null);
  bool _extentUpdateScheduled = false;
  bool _hasUserDragged = false;
  ScrollController? _contentScroll;
  Drag? _headerDrag;
  double? _contentHeight;
  List<double> _snapSizes = const [];
  bool _closing = false;
  double _motionHeight = 160;

  @override
  void initState() {
    super.initState();
    _sheet.addListener(_followSheetSize);
    if (widget.dismissRequested) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _close();
      });
    }
  }

  @override
  void didUpdateWidget(covariant MapPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dismissRequested && !oldWidget.dismissRequested) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.dismissRequested) _close();
      });
    }
  }

  bool get _top => widget.side == MapPanelSide.top;
  double get _direction => _top ? -1 : 1;
  bool get _ios => Theme.of(context).platform == TargetPlatform.iOS;
  bool get _reduceMotion =>
      MediaQuery.disableAnimationsOf(context) ||
      View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;
  double get _height => _surfaceKey.currentContext?.size?.height ?? 160;

  void _updateContentHeight(double height) {
    if (!mounted ||
        _closing ||
        (_contentHeight != null && (height - _contentHeight!).abs() < 0.5)) {
      return;
    }
    setState(() => _contentHeight = height);
  }

  void _followSheetSize() {
    if (!mounted || !_sheet.isAttached) return;
    // Modifier les bornes du panneau notifie aussi pendant sa construction.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_extentUpdateScheduled) return;
      _extentUpdateScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _extentUpdateScheduled = false;
        _followSheetSize();
      });
    } else {
      _visibleExtent.value = _sheet.size;
    }
  }

  @override
  void dispose() {
    _headerDrag?.cancel();
    _sheet.dispose();
    _visibleExtent.dispose();
    _offset.dispose();
    super.dispose();
  }

  void _dragStart(DragStartDetails details) {
    if (!_closing) {
      if (widget.scrollableBuilder != null && _contentScroll!.hasClients) {
        _hasUserDragged = true;
        _headerDrag = _contentScroll!.position.drag(
          details,
          () => _headerDrag = null,
        );
        return;
      }
      _motionHeight = _height;
      _offset.stop();
    }
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (_closing) return;
    if (widget.scrollableBuilder != null) {
      _headerDrag?.update(details);
      return;
    }
    final distance = (_offset.value + details.delta.dy) * _direction;
    _offset.value = _direction * distance.clamp(0, _height);
  }

  void _dragEnd(DragEndDetails details) {
    if (_closing) return;
    if (widget.scrollableBuilder != null) {
      _headerDrag?.end(details);
      _headerDrag = null;
      return;
    }
    final velocity = (details.primaryVelocity ?? 0) * _direction;
    if (_offset.value.abs() >= _height * 0.25 || velocity > 500) {
      _close();
    } else {
      _settle();
    }
  }

  Future<void> _settle() async {
    if (_closing) return;
    if (_reduceMotion) {
      _offset.value = 0;
      return;
    }
    await _offset.animateTo(
      0,
      duration: Duration(milliseconds: _ios ? 260 : 200),
      curve: _ios ? Curves.easeOutCubic : Curves.easeOut,
    );
  }

  void _dragCancel() {
    _headerDrag?.cancel();
    _headerDrag = null;
    if (widget.scrollableBuilder == null) _settle();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    if (_sheet.isAttached) _sheet.jumpTo(_sheet.size);
    _motionHeight = _height;
    if (!_reduceMotion) {
      await _offset.animateTo(
        _direction * (_height + 48),
        duration: Duration(milliseconds: _ios ? 240 : 200),
        curve: Curves.easeOutCubic,
      );
    }
    if (mounted) widget.onClose();
  }

  Widget _dragHandle({required Widget child, required Key key}) =>
      GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: _dragStart,
        onVerticalDragUpdate: _dragUpdate,
        onVerticalDragEnd: _dragEnd,
        onVerticalDragCancel: _dragCancel,
        child: child,
      );

  Widget _button(String label, IconData icon, VoidCallback onPressed) {
    if (!_ios) {
      return IconButton(tooltip: label, onPressed: onPressed, icon: Icon(icon));
    }
    return Tooltip(
      message: label,
      child: CupertinoButton(
        padding: const EdgeInsets.all(12),
        minimumSize: const Size.square(48),
        onPressed: onPressed,
        child: Icon(icon, size: 22, color: const Color(0xFF243243)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final extendToBottom = !_top && widget.extendToBottom;
    final margin = extendToBottom
        ? 0.0
        : MapPanel._margin(mediaQuery, widget.side);
    final radius = _ios
        ? BorderRadius.circular(24)
        : const BorderRadius.vertical(top: Radius.circular(24));
    final headerHeight =
        widget.showCloseButton || widget.onBack != null || widget.title != null
        ? 48.0
        : 32.0;
    final header = SizedBox(
      height: headerHeight,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!_top && widget.title == null) const _Grip(),
          Row(
            children: [
              if (widget.onBack != null)
                _button(
                  'Retour',
                  _ios ? CupertinoIcons.chevron_back : Icons.arrow_back,
                  widget.onBack!,
                )
              else
                const SizedBox(width: 16),
              Expanded(
                child: widget.title == null
                    ? const SizedBox.shrink()
                    : Text(
                        widget.title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
              ),
              ...widget.actions,
              if (widget.showCloseButton)
                _button(
                  'Fermer',
                  _ios ? CupertinoIcons.xmark : Icons.close,
                  _close,
                ),
              const SizedBox(width: 4),
            ],
          ),
        ],
      ),
    );

    Widget surface(Widget content, {bool fill = false}) => DecoratedBox(
      key: _surfaceKey,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: const Color(0x60FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x180D2238),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        key: const ValueKey('map-panel-surface'),
        color:
            widget.backgroundColor ??
            Colors.white.withValues(alpha: _ios ? 0.86 : 0.90),
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: ScrollConfiguration(
          behavior: _ios
              ? const CupertinoScrollBehavior()
              : const MaterialScrollBehavior(),
          child: Column(
            mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (_top)
                header
              else
                _dragHandle(
                  key: const ValueKey('map-panel-drag-handle'),
                  child: header,
                ),
              Flexible(
                fit: fill ? FlexFit.tight : FlexFit.loose,
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  removeBottom: !extendToBottom,
                  child: content,
                ),
              ),
              if (_top)
                _dragHandle(
                  key: const ValueKey('map-panel-drag-handle'),
                  child: const SizedBox(
                    height: 32,
                    width: double.infinity,
                    child: Center(child: _Grip()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final Widget panel;
    final scrollableBuilder = widget.scrollableBuilder;
    if (scrollableBuilder == null) {
      panel = ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MapPanel.maxHeightFor(mediaQuery, side: widget.side),
        ),
        child: surface(widget.child!),
      );
    } else {
      final available = math.max(
        1.0,
        mediaQuery.size.height - mediaQuery.padding.top - margin - 8,
      );
      // Le panneau ne peut dépasser la hauteur réelle de son contenu.
      final maximum = _contentHeight == null
          ? 0.92
          : math.min(0.92, (_contentHeight! + headerHeight) / available);
      final initial = math.min(
        maximum,
        MapPanel.maxHeightFor(mediaQuery) / available,
      );
      final minimum = math.min(0.18, initial * 0.45);
      if (_snapSizes.isEmpty || _snapSizes.single != initial) {
        _snapSizes = [initial];
      }
      panel = AnimatedBuilder(
        animation: _visibleExtent,
        builder: (context, child) => Align(
          alignment: Alignment.bottomCenter,
          // La boîte mesurée par la carte suit la hauteur visible du panneau.
          // La zone au-dessus reste disponible pour toucher les signalements.
          heightFactor: _hasUserDragged
              ? (_visibleExtent.value ?? initial).clamp(minimum, maximum)
              : initial,
          child: child,
        ),
        child: SizedBox(
          height: available,
          child: NotificationListener<DraggableScrollableNotification>(
            onNotification: (notification) {
              if (notification.extent <= notification.minExtent + 0.001) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _close();
                });
              }
              return true;
            },
            child: NotificationListener<ScrollStartNotification>(
              onNotification: (notification) {
                if (notification.dragDetails != null) _hasUserDragged = true;
                return false;
              },
              child: DraggableScrollableSheet(
                controller: _sheet,
                initialChildSize: initial,
                minChildSize: minimum,
                maxChildSize: maximum,
                snap: !_reduceMotion,
                snapSizes: _snapSizes,
                snapAnimationDuration: const Duration(milliseconds: 200),
                shouldCloseOnMinExtent: false,
                builder: (context, scrollController) {
                  _contentScroll = scrollController;
                  return surface(
                    scrollableBuilder(
                      context,
                      scrollController,
                      _updateContentHeight,
                    ),
                    fill: true,
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_closing) (widget.onBack ?? _close)();
      },
      child: Semantics(
        onDismiss: _close,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            _top ? margin : 0,
            12,
            _top ? 0 : margin,
          ),
          child: AnimatedBuilder(
            animation: _offset,
            builder: (context, child) {
              final progress = (_offset.value.abs() / (_motionHeight + 48))
                  .clamp(0.0, 1.0);
              return Transform.translate(
                offset: Offset(0, _offset.value),
                child: Opacity(
                  opacity: 1 - progress * 0.35,
                  child: IgnorePointer(ignoring: _closing, child: child),
                ),
              );
            },
            child: panel,
          ),
        ),
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
      color: const Color(0xFF9AA8B8),
      borderRadius: BorderRadius.circular(2),
    ),
  );
}
