import 'package:cat_library_demo/features/study/lock_screen_timer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android notification stops at an injected six-hour boundary', (
    _,
  ) async {
    expect(LockScreenTimer.supported, isTrue);
    expect(
      await LockScreenTimer.requestPermission(),
      isTrue,
      reason:
          'Grant notifications on the test device before running this probe.',
    );
    await LockScreenTimer.stop();
    expect(await LockScreenTimer.isActive(), isFalse);
    // Inject a start timestamp; do not change the device clock or study database.
    final start = DateTime.now()
        .subtract(const Duration(hours: 6))
        .add(const Duration(seconds: 12));
    expect(await LockScreenTimer.show(start), isTrue);
    for (var i = 0; i < 30 && !await LockScreenTimer.isActive(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(await LockScreenTimer.isActive(), isTrue);
    await Future<void>.delayed(const Duration(seconds: 15));
    expect(
      await LockScreenTimer.isActive(),
      isFalse,
      reason:
          'The native service must remove the stopwatch when the cap is reached.',
    );
    expect(
      await LockScreenTimer.show(
        DateTime.now().add(const Duration(minutes: 1)),
      ),
      isFalse,
    );
    expect(await LockScreenTimer.isActive(), isFalse);
    await LockScreenTimer.stop();
    // This is not six hours of real elapsed time, nor a deep-doze validation.
  });
}
