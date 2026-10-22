import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/alerts/domain/alert.dart';
import 'alert_notification_banner.dart';
import 'alert_push_controller.dart';

/// UI attachée uniquement à l'accueil autorisé. Le contrôleur capture les taps
/// plus tôt (AuthGate), puis attend cet écran pour naviguer.
class PushNotificationListener extends StatefulWidget {
  const PushNotificationListener({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.child,
    this.onOpenHistory,
    this.onReceived,
  });
  final AlertPushController controller;
  final Future<void> Function(AlertPush) onOpen;
  final Widget child;
  final VoidCallback? onOpenHistory;
  final ValueChanged<AlertPush>? onReceived;
  @override
  State<PushNotificationListener> createState() =>
      _PushNotificationListenerState();
}

class _PushNotificationListenerState extends State<PushNotificationListener> {
  Timer? _dismissTimer;
  OverlayEntry? _overlayEntry;
  AlertPush? _push;
  String? _notice;
  int _session = -1;
  int _bannerId = 0;
  String? _actionLabel;
  VoidCallback? _action;

  void _dismiss() {
    _dismissTimer?.cancel();
    if (!mounted) return;
    _push = null;
    _notice = null;
    _overlayEntry?.markNeedsBuild();
  }

  Future<void> _open(AlertPush push) {
    if (_push != null || _notice != null) _dismiss();
    return widget.onOpen(push);
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _overlayEntry = OverlayEntry(builder: _buildBanner);
      Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
      widget.controller.attach(_open);
      _changed();
    });
  }

  void _changed() {
    if (!mounted) return;
    final controller = widget.controller;
    final push = controller.foreground;
    final notice = controller.notice;
    final session = controller.sessionEpoch;
    controller.foreground = null;
    controller.notice = null;
    if (push == null && notice == null) return;
    if (push != null && notice == null && controller.ready) {
      widget.onReceived?.call(push);
    }
    VoidCallback? action;
    String? label;
    if (notice == null && push != null) {
      label = 'Ouvrir';
      action = () => controller.open(push);
    } else if (controller.canRetry) {
      label = 'Réessayer';
      action = controller.retry;
    } else if (widget.onOpenHistory != null) {
      label = 'Historique';
      action = widget.onOpenHistory;
    }
    _dismissTimer?.cancel();
    _push = push;
    _notice = notice;
    _session = session;
    _bannerId++;
    _actionLabel = label;
    _action = action == null
        ? null
        : () {
            _dismiss();
            if (controller.sessionEpoch == session && controller.ready) {
              action!();
            }
          };
    final overlay = Overlay.of(context, rootOverlay: true);
    final entry = _overlayEntry;
    if (entry == null) {
      _overlayEntry = OverlayEntry(builder: _buildBanner);
      overlay.insert(_overlayEntry!);
    } else {
      overlay.rearrange([entry], below: entry);
      entry.markNeedsBuild();
    }
    if (!MediaQuery.accessibleNavigationOf(context)) {
      _dismissTimer = Timer(const Duration(seconds: 8), _dismiss);
    }
  }

  @override
  void didUpdateWidget(covariant PushNotificationListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_changed);
    oldWidget.controller.detach(_open);
    _dismissTimer?.cancel();
    _removeOverlay();
    _push = null;
    _notice = null;
    widget.controller.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.attach(_open);
      _changed();
    });
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _removeOverlay();
    widget.controller.removeListener(_changed);
    widget.controller.detach(_open);
    super.dispose();
  }

  Widget _buildBanner(BuildContext context) {
    final controller = widget.controller;
    final visible =
        controller.ready &&
        controller.sessionEpoch == _session &&
        (_push != null || _notice != null);
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 8,
      left: 12 + MediaQuery.paddingOf(context).left,
      right: 12 + MediaQuery.paddingOf(context).right,
      child: AnimatedSwitcher(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, -0.12), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          ),
        ),
        child: visible
            ? AlertNotificationBanner(
                key: ValueKey(_bannerId),
                push: _push,
                notice: _notice,
                actionLabel: _actionLabel,
                onAction: _action,
                onDismiss: _dismiss,
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
