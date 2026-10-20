import 'package:blueway/core/map/cloud_passage_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void camera(CloudPassageController controller, double zoom) => controller
      .setCamera(zoom: zoom, longitude: 6, latitude: 43, bearing: 0, pitch: 0);

  test('no foreground outside the window; no notifications at rest', () {
    final controller = CloudPassageController();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);
    for (final zoom in [.65, 4.0, 4.5, 6.2, 7.0, 15.5]) {
      camera(controller, zoom);
      expect(controller.visible, isFalse);
    }
    expect(notifications, 0);
    camera(controller, 5);
    expect(controller.visible, isTrue);
    expect(notifications, 1);
    camera(controller, 5);
    expect(notifications, 1);
    camera(controller, 6.3);
    expect(controller.visible, isFalse);
    expect(notifications, 2); // Clears the previous painted frame.
    camera(controller, 9);
    expect(notifications, 2);
  });

  test('fast skips do not play a delayed animation; reverse re-enters', () {
    final controller = CloudPassageController();
    addTearDown(controller.dispose);
    camera(controller, 4);
    camera(controller, 7);
    expect(controller.visible, isFalse);
    camera(controller, 5.3);
    expect(controller.visible, isTrue);
    camera(controller, double.nan);
    expect(controller.zoom, 5.3);
    camera(controller, 4);
    expect(controller.visible, isFalse);
  });

  test('three smooth, distinct planes grow and fully dissipate', () {
    for (final plane in CloudPassagePlane.planes) {
      for (final zoom in [4.0, 4.5, 6.2, 6.3, 7.0, 16.0]) {
        expect(plane.opacityAt(zoom), 0);
      }
      expect(plane.opacityAt(plane.crest), plane.opacity);
      expect(plane.opacityAt(plane.enter + 1e-5), lessThan(1e-7));
      expect(plane.opacityAt(plane.exit - 1e-5), lessThan(1e-7));
      expect(plane.scaleAt(5.4), greaterThan(plane.scaleAt(4.9)));
    }
    expect(CloudPassagePlane.planes.map((p) => p.crest).toSet(), hasLength(3));
    expect(CloudPassagePlane.planes.map((p) => p.speed).toSet(), hasLength(3));
  });
}
