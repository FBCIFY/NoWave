import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../features/alerts/domain/alert.dart';
import '../../features/reports/presentation/report_category_badge.dart';
import '../../features/reports/presentation/report_category_style.dart';
import '../../features/reports/presentation/report_detail_format.dart';

/// Notification NoWave au premier plan, au-dessus de la carte.
class AlertNotificationBanner extends StatelessWidget {
  const AlertNotificationBanner({
    super.key,
    this.push,
    this.notice,
    this.actionLabel,
    this.onAction,
    required this.onDismiss,
  });

  final AlertPush? push;
  final String? notice;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final alert = notice == null ? push?.alert : null;
    final text = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: Colors.white,
        elevation: 6,
        shadowColor: const Color(0x400D2238),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFD7E3EC)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onAction,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                alert == null
                    ? const Icon(
                        Icons.notifications_outlined,
                        color: AppColors.blue600,
                        size: 32,
                      )
                    : ReportCategoryBadge(category: alert.category, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    notice ??
                        '${alert!.category.label} · ${formatNauticalMiles(alert.distanceM)}',
                    style: text.bodyMedium?.copyWith(
                      color: AppColors.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onAction != null && actionLabel != null)
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.blue600,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(48, 48),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(actionLabel!),
                  ),
                IconButton(
                  tooltip: 'Masquer la notification',
                  onPressed: onDismiss,
                  icon: const Icon(
                    Icons.close,
                    size: 20,
                    color: Color(0xFF475569),
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
