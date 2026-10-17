package fr.blueway.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private var rotationMatrixHandler: RotationMatrixStreamHandler? = null
    private var rotationMatrixChannel: EventChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Matrice partagée entre le cap de carte et l'axe photo (NW-150).
        val handler = RotationMatrixStreamHandler(applicationContext)
        rotationMatrixHandler = handler
        rotationMatrixChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "fr.blueway.app/rotation_matrix",
        ).also { it.setStreamHandler(handler) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // La destruction du moteur ne garantit pas un onCancel Dart.
        rotationMatrixHandler?.stop()
        rotationMatrixChannel?.setStreamHandler(null)
        rotationMatrixHandler = null
        rotationMatrixChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
