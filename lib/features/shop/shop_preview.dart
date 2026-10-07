import '../room/layout_draft.dart';
import 'shop_repository.dart';

/// A virtual scene instance. Never inserted into purchased inventory or drafts.
class ShopPreview {
  ShopPreview(this.base, this.product) {
    instance = InventoryInstance(
      'shop-preview-${product.sku}',
      product.sku,
      null,
      'preview',
    );
    final slot = product.placement == 'ground'
        ? null
        : base.rules.slots.entries
              .firstWhere((e) => e.value == product.placement)
              .key;
    item = PlacedItem(instance.id, slot: slot);
    if (product.placement == 'ground') {
      for (var x = 2; x < 10; x++) {
        for (var y = 2; y < 10; y++) {
          final candidate = item.copy(gx: x % 8, gy: y % 8);
          item = candidate;
          if (view.rules.validate(view.layout).isEmpty) return;
        }
      }
      item = item.copy(gx: 0, gy: 0);
    }
  }
  final FurnitureState base;
  final FurnitureProduct product;
  late final InventoryInstance instance;
  late PlacedItem item;
  FurnitureState get view {
    final cap = base.rules.categoryLimits[product.kind];
    final sameKind = base.layout.items
        .where(
          (p) =>
              base
                  .products[base.inventory
                      .firstWhere((i) => i.id == p.instanceId)
                      .sku]
                  ?.kind ==
              product.kind,
        )
        .length;
    return FurnitureState.fromJson({
      ...base.raw,
      'configured': true,
      'inventory': [
        ...base.raw['inventory'],
        {
          'id': instance.id,
          'sku': instance.sku,
          'source': 'preview',
          'purchased_by': null,
        },
      ],
      'layout': RoomLayout([
        for (final p in base.layout.items)
          if (!(item.slot != null && p.slot == item.slot) &&
              !(product.placement == 'ground' &&
                  cap != null &&
                  sameKind >= cap &&
                  base
                          .products[base.inventory
                              .firstWhere((i) => i.id == p.instanceId)
                              .sku]
                          ?.kind ==
                      product.kind))
            p,
        item,
      ]).toJson(),
    });
  }

  void move(int gx, int gy) {
    if (product.placement != 'ground') return;
    final cells = product.cells(item.facing);
    final maxX = cells.map((c) => c.$1).reduce((a, b) => a > b ? a : b);
    final maxY = cells.map((c) => c.$2).reduce((a, b) => a > b ? a : b);
    item = item.copy(gx: gx.clamp(0, 7 - maxX), gy: gy.clamp(0, 7 - maxY));
  }
}
