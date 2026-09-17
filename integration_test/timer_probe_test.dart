import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cat_library_demo/core/storage/probe_database.dart';
import 'package:cat_library_demo/core/time/study_clock.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('device SQLite persists a checkpoint across database reopen', (
    _,
  ) async {
    final db = ProbeDatabase();
    final clock = StudyClock(DateTime.now());
    await Future<void>.delayed(const Duration(seconds: 2));
    clock.checkpoint(DateTime.now());
    await db.saveCheckpoint(clock.toJson());
    await db.close();
    final reopened = ProbeDatabase();
    final saved = await reopened.readCheckpoint();
    final recovered = StudyClock.restore(saved!);
    expect(recovered.elapsed, clock.elapsed);
    expect(recovered.running, false);
    await reopened.close();
    // This is not an OS kill, lock-screen, midnight or six-hour test.
  });
}
