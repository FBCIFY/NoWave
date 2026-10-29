import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Enregistre les vibrations demandées pendant le test, par type
/// (`HapticFeedbackType.selectionClick`…).
List<String> recordHaptics(WidgetTester tester) {
  final haptics = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') {
      haptics.add(call.arguments as String);
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return haptics;
}
