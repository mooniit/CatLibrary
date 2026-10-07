import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/game.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cat_library_demo/features/room/room_scene.dart';
import 'package:cat_library_demo/features/room/layout_draft.dart';
import 'package:cat_library_demo/features/shop/shop_repository.dart';

// Visual fixture only: no cloud writes, accounts, rewards or persistent inventory.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'six refined souvenirs in the existing native room, both facings and preview',
    (tester) async {
      final products =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/data/souvenir-products.json',
                ),
              )
              as List;
      final layout = RoomLayout([
        for (var n = 0; n < products.length; n++)
          PlacedItem('art$n', gx: 1 + n % 3 * 2, gy: 1 + n ~/ 3 * 3),
      ]);
      final scene = RoomScene(fitViewport: true, forceLayout: true)
        ..roomState = FurnitureState.fromJson({
          'configured': true,
          'products': products,
          'inventory': [
            for (var n = 0; n < products.length; n++)
              {'id': 'art$n', 'sku': products[n]['sku'], 'source': 'souvenir'},
          ],
          'layout': layout.toJson(),
        });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: const Color(0xffeef5fa),
            body: SafeArea(child: GameWidget(game: scene)),
          ),
        ),
      );
      for (var n = 0; n < 100 && !scene.geometryReady; n++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(scene.geometryReady, true);
      expect(scene.roomState!.rules.validate(layout), isEmpty);
      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot('m6-v2-native-six-x');
      scene.draftLayout = RoomLayout([
        for (final item in layout.items)
          PlacedItem(item.instanceId, gx: item.gx, gy: item.gy, facing: 'y'),
      ]);
      await tester.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot('m6-v2-native-six-y');
      final venus = scene.roomState!.products['souvenir-louvre']!;
      scene.setGhost(
        const PlacedItem('preview', gx: 6, gy: 6, facing: 'y'),
        venus,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(scene.ghostBounds, isNotNull);
      final center =
          scene.origin +
          scene.projectWorld(6.0625 / 8, 6.0625 / 8) * scene.displayScale;
      expect(scene.hitsGhost(center), true);
      await binding.takeScreenshot('m6-v2-native-venus-preview');
      expect(tester.takeException(), isNull);
    },
  );
}
