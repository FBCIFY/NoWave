import 'package:flutter/material.dart';

enum MapNoticeKind { success, warning, error }

/// Message court de la carte (publication, erreur de capteur…).
class MapNotice {
  const MapNotice(this.message, this.kind);

  final String message;
  final MapNoticeKind kind;
}

/// Bandeau affiché en haut de la carte, sous la position GPS. Remplace les
/// SnackBars, qui masquaient les boutons du bas. Un appui le ferme.
class MapNoticeBanner extends StatelessWidget {
  const MapNoticeBanner({
    super.key,
    required this.notice,
    required this.onDismiss,
  });

  final MapNotice notice;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (notice.kind) {
      MapNoticeKind.success => (Icons.check_circle, const Color(0xFF1E8E5A)),
      MapNoticeKind.warning => (
        Icons.warning_amber_rounded,
        const Color(0xFFB86E00),
      ),
      MapNoticeKind.error => (Icons.error_outline, const Color(0xFFAF3942)),
    };

    return Semantics(
      liveRegion: true,
      child: Material(
        color: const Color(0xFFF6F8FA),
        elevation: 6,
        shadowColor: const Color(0x660D2238),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: color.withValues(alpha: 0.45)),
        ),
        child: InkWell(
          onTap: onDismiss,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    notice.message,
                    style: const TextStyle(
                      color: Color(0xFF243243),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
