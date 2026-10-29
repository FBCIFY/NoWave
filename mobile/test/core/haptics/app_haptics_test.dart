import 'package:blueway/core/haptics/app_haptics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'record_haptics.dart';

void main() {
  testWidgets('chaque moment a sa vibration', (tester) async {
    final haptics = recordHaptics(tester);

    AppHaptics.selection();
    AppHaptics.capture();
    AppHaptics.success();
    AppHaptics.failure();
    await tester.pump();

    expect(haptics, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.heavyImpact',
    ]);
  });
}
