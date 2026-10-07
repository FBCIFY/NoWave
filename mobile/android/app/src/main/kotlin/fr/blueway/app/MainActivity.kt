package fr.blueway.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Axe de la caméra pour la photo de signalement (NW-150).
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "fr.blueway.app/rotation_matrix",
        ).setStreamHandler(RotationMatrixStreamHandler(applicationContext))
    }
}
