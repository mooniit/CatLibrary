import 'package:cat_library_demo/features/room/layout_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final chair = FurnitureProduct.fromJson({
    'sku': 'lunar-chair',
    'label': '椅子',
    'theme': 'lunar',
    'kind': 'chair',
    'placement': 'ground',
    'geometry': {
      'x': {
        'cells': [
          [0, 0],
        ],
        'w': .115,
        'd': .12,
        'h': .2,
      },
      'y': {
        'cells': [
          [0, 0],
        ],
        'w': .12,
        'd': .115,
        'h': .2,
      },
    },
  });
  final desk = FurnitureProduct.fromJson({
    'sku': 'lunar-desk',
    'label': '桌',
    'theme': 'lunar',
    'kind': 'desk',
    'placement': 'ground',
    'geometry': {
      'x': {
        'cells': [
          [0, 0],
          [0, 1],
          [1, 0],
        ],
        'w': .2,
        'd': .2,
        'h': .2,
      },
      'y': {
        'cells': [
          [0, 0],
          [1, 0],
          [1, 1],
        ],
        'w': .2,
        'd': .2,
        'h': .2,
      },
    },
  });
  final products = {chair.sku: chair, desk.sku: desk};
  final inventory = [
    InventoryInstance('c1', chair.sku, 'A', 'purchase'),
    InventoryInstance('c2', chair.sku, 'B', 'purchase'),
    InventoryInstance('d1', desk.sku, 'A', 'purchase'),
    InventoryInstance('d2', desk.sku, 'B', 'purchase'),
  ];
  List<String> errors(RoomLayout l) => PlacementRules(
    products,
    inventory,
    categoryLimits: {'desk': 1},
  ).validate(l);

  test('one instance cannot appear twice and storage cannot copy stock', () {
    const item = PlacedItem('c1', gx: 0, gy: 0);
    expect(errors(RoomLayout([item, item])).join(), contains('重复'));
    expect(
      errors(const RoomLayout([PlacedItem('unknown')])).join(),
      contains('库存'),
    );
    expect(
      errors(const RoomLayout([PlacedItem('c1'), PlacedItem('c2', gx: 1)])),
      isEmpty,
    );
  });
  test('actual L cells allow a chair in missing corner but reject overlap', () {
    expect(
      errors(
        const RoomLayout([PlacedItem('d1'), PlacedItem('c1', gx: 1, gy: 1)]),
      ),
      isEmpty,
    );
    expect(
      errors(
        const RoomLayout([PlacedItem('d1'), PlacedItem('c1', gx: 0, gy: 1)]),
      ).join(),
      contains('占格'),
    );
    expect(
      errors(const RoomLayout([PlacedItem('c1', gx: 8)])).join(),
      contains('边界'),
    );
  });
  test('category count spans styles and identities', () {
    expect(
      errors(
        const RoomLayout([PlacedItem('d1'), PlacedItem('d2', gx: 4)]),
      ).join(),
      contains('类别'),
    );
  });
  test('preview cancel keeps original and confirm changes draft only', () {
    final draft = LayoutDraft(const RoomLayout([PlacedItem('c1')]), 12);
    draft.preview = const PlacedItem('c1', gx: 3);
    expect(draft.layout.items.single.gx, 0);
    draft.cancelPreview();
    expect(draft.layout.items.single.gx, 0);
    draft.preview = const PlacedItem('c1', gx: 3);
    draft.confirm(PlacementRules(products, inventory));
    expect(draft.layout.items.single.gx, 3);
    expect(draft.baseVersion, 12);
    draft.stow('c1');
    expect(draft.layout.items, isEmpty);
    expect(inventory.length, 4);
  });
  test('failed replace preserves old layout and preview remains editable', () {
    final draft = LayoutDraft(const RoomLayout([PlacedItem('c1')]), 2);
    draft.preview = const PlacedItem('c1', gx: -1);
    expect(
      () => draft.confirm(PlacementRules(products, inventory)),
      throwsStateError,
    );
    expect(draft.layout.items.single.gx, 0);
    expect(draft.preview!.gx, -1);
  });
  test(
    'restart preserves replacement preview without consuming another instance',
    () {
      final draft = LayoutDraft(
        const RoomLayout([PlacedItem('c1')]),
        2,
        preview: const PlacedItem('c2', gx: 3),
        replacing: 'c1',
      );
      final restored = LayoutDraft.fromJson(draft.toJson());
      expect(restored.candidate().items.single.instanceId, 'c2');
      restored.cancelPreview();
      expect(restored.layout.items.single.instanceId, 'c1');
      expect(inventory.length, 4);
    },
  );

  test(
    'new ground instance starts in a free cell without duplicating stock',
    () {
      final rules = PlacementRules(products, inventory);
      final target = rules.firstAvailable(
        const RoomLayout([PlacedItem('c1')]),
        inventory[1],
      );
      expect(target!.gx, 1);
      expect(
        rules.validate(RoomLayout([const PlacedItem('c1'), target])),
        isEmpty,
      );
    },
  );
  test('art chooses four free mounts in order and refuses a full wall', () {
    final art = FurnitureProduct.fromJson({
      'sku': 'art',
      'label': '画',
      'theme': 'wood',
      'kind': 'painting',
      'placement': 'art',
      'geometry': {'artwork': 'starry'},
    });
    final stock = List.generate(
      5,
      (i) => InventoryInstance('a$i', 'art', 'A', 'purchase'),
    );
    final rules = PlacementRules({'art': art}, stock);
    var layout = const RoomLayout([]);
    const expected = [
      'art-left-back',
      'art-left-front',
      'art-right-back',
      'art-right-front',
    ];
    for (var i = 0; i < 4; i++) {
      final item = rules.firstAvailable(layout, stock[i])!;
      expect(item.slot, expected[i]);
      layout = RoomLayout([...layout.items, item]);
    }
    expect(rules.firstAvailable(layout, stock[4]), isNull);
    expect(rules.firstAvailable(layout, stock[0])!.slot, expected[0]);
  });
}
