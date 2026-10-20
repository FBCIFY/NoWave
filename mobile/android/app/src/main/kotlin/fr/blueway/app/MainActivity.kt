package fr.blueway.app

import android.annotation.SuppressLint
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import android.view.ViewGroup
import android.view.animation.DecelerateInterpolator
import com.mapbox.android.gestures.MoveGestureDetector
import com.mapbox.maps.MapView
import com.mapbox.maps.ScreenCoordinate
import com.mapbox.maps.CameraOptions
import com.mapbox.geojson.Point
import com.mapbox.maps.plugin.animation.MapAnimationOptions
import com.mapbox.maps.plugin.animation.camera
import com.mapbox.maps.plugin.gestures.OnMoveListener
import com.mapbox.maps.plugin.gestures.gestures
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.hypot
import kotlin.math.max

class MainActivity : FlutterActivity() {
    private var rotationMatrixHandler: RotationMatrixStreamHandler? = null
    private var rotationMatrixChannel: EventChannel? = null
    private var mapMotionChannel: MethodChannel? = null
    private var mapMotion: MapMomentum? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Matrice partagée entre le cap de carte et l'axe photo (NW-150).
        val handler = RotationMatrixStreamHandler(applicationContext)
        rotationMatrixHandler = handler
        rotationMatrixChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "fr.blueway.app/rotation_matrix",
        ).also { it.setStreamHandler(handler) }
        mapMotionChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "fr.blueway.app/map_motion",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method != "configure" && call.method != "diagnosePoles") {
                    result.notImplemented()
                } else {
                    val map = findMap(window.decorView)
                    if (map == null) {
                        result.success(false)
                    } else if (call.method == "diagnosePoles") {
                        result.success(diagnosePoles(map))
                    } else {
                        if (call.argument<Boolean>("baseline") == true) {
                            mapMotion?.dispose()
                            mapMotion = null
                            map.gestures.updateSettings {
                                scrollDecelerationEnabled = true
                                rotateDecelerationEnabled = true
                                pinchToZoomDecelerationEnabled = true
                            }
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        if (mapMotion?.map !== map) {
                            mapMotion?.dispose()
                            mapMotion = MapMomentum(map)
                        }
                        mapMotion!!.reduceMotion = call.argument<Boolean>("reduceMotion") ?: false
                        mapMotion!!.duration = call.argument<Number>("androidDurationMs")?.toLong() ?: 280L
                        mapMotion!!.maxVelocityDp = call.argument<Number>("androidMaxVelocityDp")?.toDouble() ?: 1400.0
                        // The bounded native release animation below replaces
                        // only fling; Mapbox still handles every touch gesture.
                        map.gestures.updateSettings { scrollDecelerationEnabled = false }
                        result.success(true)
                    }
                }
            }
        }
    }

    private fun findMap(view: View): MapView? {
        if (view is MapView) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) findMap(view.getChildAt(i))?.let { return it }
        }
        return null
    }

    private fun diagnosePoles(map: MapView): List<Map<String, Any>> {
        val saved = map.mapboxMap.cameraState
        val trials = listOf(1.0, -1.0).map { sign ->
            map.mapboxMap.setCamera(CameraOptions.Builder()
                .center(Point.fromLngLat(15.0, sign * 89.999)).zoom(.65).bearing(0.0).pitch(0.0).build())
            val actual = map.mapboxMap.cameraState.center.latitude()
            map.mapboxMap.setCamera(CameraOptions.Builder()
                .center(Point.fromLngLat(15.0, sign * 70)).zoom(.65).bearing(0.0).pitch(0.0).build())
            val start = ScreenCoordinate(map.width / 2.0, map.height * .75)
            val samples = (0 until 80).map {
                map.mapboxMap.setCamera(map.mapboxMap.cameraForDrag(
                    start, ScreenCoordinate(start.x, start.y + sign * 12)))
                val state = map.mapboxMap.cameraState
                listOf(state.center.longitude(), state.center.latitude(), state.bearing)
            }
            mapOf("hemisphere" to if (sign > 0) "north" else "south",
                "requested_latitude" to sign * 89.999, "actual_latitude" to actual,
                "drag_samples" to samples)
        }
        map.mapboxMap.setCamera(CameraOptions.Builder().center(saved.center)
            .zoom(saved.zoom).bearing(saved.bearing).pitch(saved.pitch).padding(saved.padding).build())
        return trials
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // La destruction du moteur ne garantit pas un onCancel Dart.
        rotationMatrixHandler?.stop()
        rotationMatrixChannel?.setStreamHandler(null)
        rotationMatrixHandler = null
        rotationMatrixChannel = null
        mapMotion?.dispose()
        mapMotion = null
        mapMotionChannel?.setMethodCallHandler(null)
        mapMotionChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}

/** Screen-space, cubic deceleration. No Dart events or geographic velocity
 * extrapolation near the poles. A new touch cancels the release immediately. */
@SuppressLint("ClickableViewAccessibility")
private class MapMomentum(val map: MapView) : OnMoveListener {
    var reduceMotion = false
    var duration = 280L
    var maxVelocityDp = 1400.0
    private var tracker: VelocityTracker? = null
    private var multiplePointers = false
    private var lastMoveTime = 0L
    private var vx = 0.0
    private var vy = 0.0

    init {
        map.setOnTouchListener { _, event ->
            if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                map.camera.cancelAllAnimators()
                tracker?.recycle()
                tracker = VelocityTracker.obtain()
                multiplePointers = false
                vx = 0.0
                vy = 0.0
            }
            if (event.pointerCount > 1) multiplePointers = true
            tracker?.addMovement(event)
            if (event.actionMasked == MotionEvent.ACTION_UP) {
                tracker?.computeCurrentVelocity(1000)
                vx = tracker?.xVelocity?.toDouble() ?: 0.0
                vy = tracker?.yVelocity?.toDouble() ?: 0.0
                tracker?.recycle()
                tracker = null
            } else if (event.actionMasked == MotionEvent.ACTION_CANCEL) {
                tracker?.recycle()
                tracker = null
                vx = 0.0
                vy = 0.0
            }
            false
        }
        map.gestures.addOnMoveListener(this)
    }

    override fun onMoveBegin(detector: MoveGestureDetector) {
        lastMoveTime = detector.currentEvent.eventTime
    }

    override fun onMove(detector: MoveGestureDetector): Boolean {
        lastMoveTime = detector.currentEvent.eventTime
        return false
    }

    override fun onMoveEnd(detector: MoveGestureDetector) {
        val event = detector.currentEvent
        if (reduceMotion || multiplePointers || event.actionMasked != MotionEvent.ACTION_UP ||
            event.eventTime - lastMoveTime > 50L || !vx.isFinite() || !vy.isFinite()) return
        val speed = hypot(vx, vy)
        val density = map.resources.displayMetrics.density
        if (speed < 80.0 * density) return
        val scale = maxVelocityDp * density / max(speed, maxVelocityDp * density)
        // Cubic ease-out has initial slope 3: distance = velocity * time / 3.
        val distanceTime = duration / 3000.0
        val anchor = ScreenCoordinate(map.width / 2.0, map.height * .75)
        val destination = ScreenCoordinate(
            anchor.x + vx * scale * distanceTime,
            anchor.y + vy * scale * distanceTime,
        )
        val camera = map.mapboxMap.cameraForDrag(anchor, destination)
        map.camera.easeTo(camera, MapAnimationOptions.Builder()
            .duration(duration).interpolator(DecelerateInterpolator(1.5f)).build())
    }

    fun dispose() {
        map.gestures.removeOnMoveListener(this)
        map.setOnTouchListener(null)
        tracker?.recycle()
        tracker = null
    }
}
