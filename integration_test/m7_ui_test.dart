import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cat_library_demo/app/app_theme.dart';
import 'package:cat_library_demo/features/cats/cats_page.dart';

// In-memory visual fixture only; no accounts, RPCs, adoption or feeding writes.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('cat management and adoption render in light and night themes', (
    tester,
  ) async {
    var converted = false;
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final mode = brightness == Brightness.light ? 'light' : 'night';
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness),
          debugShowCheckedModeBanner: false,
          home: CatsPage(
            key: ValueKey(mode),
            ownerId: 'visual-owner',
            call: (action, args) async {
              calls.add(action);
              if (action != 'cats_state') {
                throw StateError('Visual fixture refuses writes');
              }
              return {
                'family_id': 'visual-family',
                'remaining': 1,
                'cats': [
                  {
                    'id': 'visual-calico',
                    'name': '橘点',
                    'appearance': 'black_short',
                    'owner_id': 'visual-owner',
                    'is_mine': true,
                    'fed_today': false,
                  },
                  {
                    'id': 'visual-longhair',
                    'name': '白云',
                    'appearance': 'light_long',
                    'owner_id': 'visual-member',
                    'is_mine': false,
                    'traveling': true,
                  },
                ],
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, ['cats_state']);
      if (!converted) {
        await binding.convertFlutterSurfaceToImage();
        converted = true;
      }
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('橘点'), findsOneWidget);
      expect(find.textContaining('登记主人：家庭成员'), findsOneWidget);
      expect(find.text('喂食 15'), findsOneWidget);
      await binding.takeScreenshot('m7-cats-ui-$mode');
      await tester.scrollUntilVisible(find.text('免费领养'), 160);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('m7-adoption-ui-$mode');
      expect(tester.takeException(), isNull);
    }
  });
}
