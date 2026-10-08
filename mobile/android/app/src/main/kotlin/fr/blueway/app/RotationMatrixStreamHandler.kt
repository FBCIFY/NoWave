package fr.blueway.app

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.plugin.common.EventChannel

/**
 * Envoie à Flutter la matrice de rotation du téléphone (9 valeurs, ligne par
 * ligne, du repère du téléphone vers le repère terrestre est/nord/haut).
 *
 * Même capteur fusionné que precise_compass (accéléromètre, gyroscope et
 * magnétomètre). Le calcul de l'axe de la caméra se fait en Dart
 * (camera_azimuth.dart), où il est testé.
 */
class RotationMatrixStreamHandler(context: Context) : EventChannel.StreamHandler {
    private val sensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private var listener: SensorEventListener? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val sensor = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
            ?: sensorManager.getDefaultSensor(Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR)
        if (sensor == null) {
            events.error("unavailable", "Capteur de rotation absent", null)
            return
        }

        val matrix = FloatArray(9)
        val newListener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                // Certains anciens Samsung lèvent une erreur au-delà de 4 valeurs.
                val vector =
                    if (event.values.size > 4) event.values.copyOfRange(0, 4) else event.values
                SensorManager.getRotationMatrixFromVector(matrix, vector)
                events.success(matrix.map { it.toDouble() })
            }

            override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {}
        }
        listener = newListener
        sensorManager.registerListener(newListener, sensor, SensorManager.SENSOR_DELAY_GAME)
    }

    override fun onCancel(arguments: Any?) {
        listener?.let { sensorManager.unregisterListener(it) }
        listener = null
    }
}
