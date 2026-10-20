import Flutter
import UIKit
import MapboxMaps
import CoreLocation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NoWaveMapMotion")!
    let channel = FlutterMethodChannel(
      name: "fr.blueway.app/map_motion", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "configure" || call.method == "diagnosePoles" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let arguments = call.arguments as? [String: Any] ?? [:]
      let reduceMotion = arguments["reduceMotion"] as? Bool ?? false
      let decay = arguments["iosDecay"] as? Double ?? 0.985
      let windows = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
      // No private plugin registry or dependency fork: the sole visible map
      // belongs to the existing Flutter platform-view hierarchy.
      let maps = windows.flatMap { Self.mapViews(in: $0) }.filter { $0.window != nil }
      guard maps.count == 1, let map = maps.first else {
        result(false)
        return
      }
      if call.method == "diagnosePoles" {
        let saved = map.mapboxMap.cameraState
        var trials: [[String: Any]] = []
        for sign in [1.0, -1.0] {
          map.mapboxMap.setCamera(to: CameraOptions(
            center: CLLocationCoordinate2D(latitude: sign * 89.999, longitude: 15),
            zoom: 0.65, bearing: 0, pitch: 0))
          let requestedPole = map.mapboxMap.cameraState.center.latitude
          map.mapboxMap.setCamera(to: CameraOptions(
            center: CLLocationCoordinate2D(latitude: sign * 70, longitude: 15),
            zoom: 0.65, bearing: 0, pitch: 0))
          var samples: [[Double]] = []
          let start = CGPoint(x: map.bounds.midX, y: map.bounds.height * 0.75)
          for _ in 0..<80 {
            let camera = map.mapboxMap.dragCameraOptions(
              from: start, to: CGPoint(x: start.x, y: start.y + sign * 12))
            map.mapboxMap.setCamera(to: camera)
            let state = map.mapboxMap.cameraState
            samples.append([state.center.longitude, state.center.latitude, state.bearing])
          }
          trials.append(["hemisphere": sign > 0 ? "north" : "south",
                         "requested_latitude": sign * 89.999,
                         "actual_latitude": requestedPole, "drag_samples": samples])
        }
        map.mapboxMap.setCamera(to: CameraOptions(cameraState: saved))
        result(trials)
        return
      }
      map.gestures.options.panDecelerationFactor = reduceMotion ? 0 : CGFloat(decay)
      result(true)
    }
  }

  private static func mapViews(in view: UIView) -> [MapView] {
    if let map = view as? MapView { return [map] }
    return view.subviews.flatMap { mapViews(in: $0) }
  }
}
