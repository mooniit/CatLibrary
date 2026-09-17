import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cat_library_demo/core/sync/cloud_client.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('target device round-trips an anonymous private probe', (
    _,
  ) async {
    expect(
      CloudClient.configured,
      isTrue,
      reason:
          'Supply test project URL and public key; missing config is not a passing test.',
    );
    expect(await CloudClient.runProbe(), contains('往返成功'));
    final first = (await CloudClient.connect()).auth.currentUser!.id;
    expect((await CloudClient.connect()).auth.currentUser!.id, first);
  });
}
