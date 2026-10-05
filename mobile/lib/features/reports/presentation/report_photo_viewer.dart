import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Photo du signalement en plein écran, pour vérifier ce qu'on signale avant
/// de publier. On pince pour zoomer ; la croix ou le retour referme.
class ReportPhotoViewer extends StatelessWidget {
  const ReportPhotoViewer({super.key, required this.photo});

  final Uint8List photo;

  static Future<void> show(BuildContext context, Uint8List photo) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, _, _) => ReportPhotoViewer(photo: photo),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 5,
                child: SizedBox.expand(
                  child: Image.memory(
                    photo,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: IconButton(
                    tooltip: 'Fermer la photo',
                    onPressed: () => Navigator.of(context).pop(),
                    color: Colors.white,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                    ),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
