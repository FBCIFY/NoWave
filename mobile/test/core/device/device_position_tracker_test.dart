import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:blueway/core/device/device_position_reporter.dart';
import 'package:blueway/core/device/device_position_tracker.dart';

/// Note chaque appel reçu du tracker.
class _Reporter extends Fake implements DevicePositionReporter {
  final List<String> calls = [];

  @override
  Future<void> start() async => calls.add('start');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> setBackground(bool enabled) async =>
      calls.add('background:$enabled');

  @override
  Future<void> appHidden() async => calls.add('hidden');
}

void main() {
  late _Reporter reporter;

  setUp(() => reporter = _Reporter());

  Widget tracker({required bool runInBackground}) {
    return DevicePositionTracker(
      reporter: reporter,
      runInBackground: runInBackground,
      child: const SizedBox(),
    );
  }

  void setLifecycle(WidgetTester tester, List<AppLifecycleState> states) {
    for (final state in states) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  testWidgets('choisit le mode avant de démarrer le suivi', (tester) async {
    await tester.pumpWidget(tracker(runInBackground: true));

    expect(reporter.calls, ['background:true', 'start']);
  });

  testWidgets('prévient le reporter quand l’app est masquée puis revient', (
    tester,
  ) async {
    await tester.pumpWidget(tracker(runInBackground: true));
    reporter.calls.clear();

    setLifecycle(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
    ]);
    setLifecycle(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);

    expect(reporter.calls, ['hidden', 'start', 'start']);
  });

  testWidgets('relance le suivi après une fenêtre système', (tester) async {
    await tester.pumpWidget(tracker(runInBackground: false));
    reporter.calls.clear();

    setLifecycle(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);

    expect(reporter.calls, ['start']);
  });

  testWidgets('suit un changement de la préférence d’alertes', (tester) async {
    await tester.pumpWidget(tracker(runInBackground: false));
    await tester.pumpWidget(tracker(runInBackground: true));
    await tester.pumpWidget(tracker(runInBackground: true));

    expect(reporter.calls, ['background:false', 'start', 'background:true']);
  });

  testWidgets('arrête le suivi quand il quitte l’écran', (tester) async {
    await tester.pumpWidget(tracker(runInBackground: true));
    await tester.pumpWidget(const SizedBox());

    expect(reporter.calls.last, 'stop');
  });
}
