import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/features/shop/shop_preview.dart';
import 'package:cat_library_demo/features/shop/shop_repository.dart';
import 'package:cat_library_demo/features/room/furniture_catalog_widgets.dart';
import 'package:cat_library_demo/features/room/layout_draft.dart';

void main() {
  final catalog =
      jsonDecode(File('assets/data/furniture-products.json').readAsStringSync())
          as List;
  FurnitureState base() => FurnitureState.fromJson({
    'family_id': 'F',
    'configured': true,
    'version': 4,
    'products': catalog,
    'inventory': <dynamic>[],
    'layout': const RoomLayout([]).toJson(),
  });
  test(
    'every catalog product belongs to exactly one of five aggregate categories',
    () {
      expect(furnitureCategories.length, 6);
      final groups = furnitureCategories.keys.where((k) => k != 'all').toSet();
      expect(groups, {
        'furniture',
        'cats',
        'decoration',
        'windows',
        'renovation',
      });
      for (final product in base().products.values) {
        expect(
          groups.where((g) => matchesFurnitureCategory(g, product.kind)),
          hasLength(1),
        );
      }
      expect(matchesFurnitureCategory('furniture', 'bookshelf'), isTrue);
      expect(matchesFurnitureCategory('furniture', 'desk'), isTrue);
      expect(matchesFurnitureCategory('furniture', 'chair'), isTrue);
      expect(matchesFurnitureCategory('decoration', 'rug'), isTrue);
      expect(matchesFurnitureCategory('windows', 'painting'), isTrue);
      expect(matchesFurnitureCategory('windows', 'window'), isTrue);
    },
  );
  testWidgets(
    'All and five icon categories fit a narrow phone without text labels',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 320,
                child: FurnitureCategories(selected: 'all', onChanged: (_) {}),
              ),
            ),
          ),
        ),
      );
      expect(find.text('All'), findsOneWidget);
      expect(find.byType(RoomCategoryIcon), findsNWidgets(5));
      expect(find.text('家具'), findsNothing);
      expect(find.byTooltip('装修'), findsOneWidget);
      final all = tester.getRect(find.byKey(const Key('category-all')));
      final last = tester.getRect(find.byKey(const Key('category-renovation')));
      expect(last.right - all.left, lessThanOrEqualTo(320));
      expect(last.height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'shop preview moves virtual furniture without changing household inventory or layout',
    () {
      final original = base(),
          trial = ShopPreview(base(), base().products['wood-bookshelf']!);
      trial.move(999, -8);
      expect(trial.item.gx, 7);
      expect(trial.item.gy, 0);
      expect(trial.view.inventory.single.source, 'preview');
      expect(trial.view.rules.validate(trial.view.layout), isEmpty);
      expect(original.inventory, isEmpty);
      expect(original.layout.items, isEmpty);
      expect(original.version, 4);
    },
  );
  test(
    'fixed preview remains in its registered slot and cannot move as ground furniture',
    () {
      for (final sku in [
        'wood-window',
        'lunar-rug',
        'royal-painting-sunflowers',
      ]) {
        final trial = ShopPreview(base(), base().products[sku]!);
        final before = trial.item.toJson();
        trial.move(6, 6);
        expect(trial.item.toJson(), before);
        expect(trial.view.rules.validate(trial.view.layout), isEmpty);
      }
    },
  );
  test(
    'paintings bind their frame and artwork; fixed slots cycle without moving anchors',
    () {
      expect(base().products.values.where((p) => p.active), hasLength(42));
      for (final product in base().products.values.where(
        (p) => p.kind == 'painting',
      )) {
        final trial = ShopPreview(base(), product);
        expect(trial.item.artwork, product.artwork);
        final first = trial.item.slot;
        for (var i = 0; i < 4; i++) {
          trial.item = trial.item.copy(
            slot: nextMount(trial.base.rules, product, trial.item.slot),
          );
          expect(trial.view.rules.validate(trial.view.layout), isEmpty);
        }
        expect(trial.item.slot, first);
        trial.item = trial.item.copy(
          artwork: product.artwork == 'mona' ? 'starry' : 'mona',
        );
        expect(trial.view.rules.validate(trial.view.layout), contains('画作无效'));
      }
      final trial = ShopPreview(base(), base().products['wood-window']!);
      expect(
        nextMount(trial.base.rules, trial.product, trial.item.slot),
        'window-right',
      );
      expect(
        nextMount(trial.base.rules, trial.product, 'window-right'),
        'window-left',
      );
    },
  );
  testWidgets(
    'unique products hide quantity and owned copies disable purchase but allow preview',
    (tester) async {
      final product = base().products['wood-chair']!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FurnitureDetails(
              product: product,
              owned: 1,
              canPurchase: false,
              unavailable: '已拥有 1/1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('purchase-quantity')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(ValueKey('buy-${product.sku}')))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const Key('product-preview')), findsOneWidget);
    },
  );
  testWidgets(
    'only explicitly configured multiple copies show quantity; respects remaining capacity',
    (tester) async {
      final product = FurnitureProduct.fromJson({
        ...catalog.firstWhere((p) => p['sku'] == 'wood-chair'),
        'purchase_limit': 4,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FurnitureDetails(
              product: product,
              owned: 2,
              canPurchase: true,
              unavailable: '',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('purchase-quantity')), findsOneWidget);
      await tester.tap(find.byTooltip('增加数量'));
      await tester.pump();
      expect(find.text('2 件'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == '增加数量',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('购买 · 80 喵喵币'), findsOneWidget);
    },
  );
}
