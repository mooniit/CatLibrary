import 'dart:convert';

class FurnitureProduct {
  FurnitureProduct.fromJson(Map<String, dynamic> value)
    : sku = value['sku'],
      label = value['label'],
      theme = value['theme'],
      kind = value['kind'],
      placement = value['placement'],
      geometry = Map<String, dynamic>.from(value['geometry']),
      price = value['price'],
      currency = value['currency'],
      purchaseLimit = value['purchase_limit'],
      active = value['active'] == true,
      isTest = value['is_test'] == true;
  final String sku, label, theme, kind, placement;
  final Map<String, dynamic> geometry;
  final int? price, purchaseLimit;
  final String? currency;
  final bool active, isTest;
  String? get artwork => geometry['artwork'] as String?;
  String get sprite => placement == 'ground'
      ? '$kind-x'
      : placement == 'window'
      ? 'window-left'
      : placement == 'art'
      ? 'frame-${geometry['template']}-left'
      : placement == 'wall'
      ? 'wall-left-closed'
      : kind;
  String get assetRoot =>
      'assets/images/room/${theme == 'lunar' ? 'lunar-v5' : theme}/';
  List<(int, int)> cells(String facing) => [
    for (final cell in geometry[facing]['cells'] as List)
      ((cell[0] as num).toInt(), (cell[1] as num).toInt()),
  ];
}

class InventoryInstance {
  const InventoryInstance(
    this.id,
    this.sku,
    this.purchasedBy,
    this.source, {
    this.sourceCatId,
    this.sourceCatOwner,
    this.sourceCatName,
    this.sourceTripId,
    this.sourceDestination,
    this.sourceDate,
  });
  factory InventoryInstance.fromJson(Map value) => InventoryInstance(
    value['id'],
    value['sku'],
    value['purchased_by'],
    value['source'],
    sourceCatId: value['source_cat_id'],
    sourceCatOwner: value['source_cat_owner'],
    sourceCatName: value['source_cat_name'],
    sourceTripId: value['source_trip_id'],
    sourceDestination: value['source_destination'],
    sourceDate: value['source_date'],
  );
  final String id, sku, source;
  final String? purchasedBy;
  bool belongsTo(String owner) =>
      purchasedBy == owner || sourceCatOwner == owner;
  final String? sourceCatId,
      sourceCatOwner,
      sourceCatName,
      sourceTripId,
      sourceDestination,
      sourceDate;
}

class PlacedItem {
  const PlacedItem(
    this.instanceId, {
    this.gx = 0,
    this.gy = 0,
    this.facing = 'x',
    this.slot,
    this.artwork = 'starry',
  });
  factory PlacedItem.fromJson(Map value) => PlacedItem(
    value['instance_id'],
    gx: (value['gx'] as num?)?.toInt() ?? 0,
    gy: (value['gy'] as num?)?.toInt() ?? 0,
    facing: value['facing'] ?? 'x',
    slot: value['slot'],
    artwork: value['artwork'] ?? 'starry',
  );
  final String instanceId, facing, artwork;
  final int gx, gy;
  final String? slot;
  PlacedItem copy({
    String? instanceId,
    int? gx,
    int? gy,
    String? facing,
    String? slot,
    String? artwork,
  }) => PlacedItem(
    instanceId ?? this.instanceId,
    gx: gx ?? this.gx,
    gy: gy ?? this.gy,
    facing: facing ?? this.facing,
    slot: slot ?? this.slot,
    artwork: artwork ?? this.artwork,
  );
  Map<String, dynamic> toJson() => {
    'instance_id': instanceId,
    'gx': gx,
    'gy': gy,
    'facing': facing,
    'slot': slot,
    'artwork': artwork,
  };
}

class RoomLayout {
  const RoomLayout(this.items);
  factory RoomLayout.fromJson(Map value) {
    if (value['standard'] != 'room-standard-v1') throw StateError('未知房屋标准');
    return RoomLayout([
      for (final i in value['items'] as List) PlacedItem.fromJson(i),
    ]);
  }
  final List<PlacedItem> items;
  Map<String, dynamic> toJson() => {
    'standard': 'room-standard-v1',
    'items': items.map((i) => i.toJson()).toList(),
  };
}

class PlacementRules {
  PlacementRules(
    this.products,
    this.inventory, {
    this.categoryLimits = const {'desk': 1, 'tree': 1, 'bed': 1},
    this.slots = const {
      'window-left': 'window',
      'window-right': 'window',
      'art-left-back': 'art',
      'art-left-front': 'art',
      'art-right-back': 'art',
      'art-right-front': 'art',
      'rug': 'rug',
      'wall': 'wall',
      'floor': 'floor',
    },
  });
  final Map<String, FurnitureProduct> products;
  final List<InventoryInstance> inventory;
  final Map<String, int> categoryLimits;
  final Map<String, String> slots;
  List<String> validate(RoomLayout layout) {
    final errors = <String>[],
        ids = <String>{},
        cells = <(int, int)>{},
        usedSlots = <String>{},
        counts = <String, int>{};
    for (final item in layout.items) {
      if (!ids.add(item.instanceId)) {
        errors.add('同一库存实例重复摆放');
        continue;
      }
      final instance = inventory
          .where((i) => i.id == item.instanceId)
          .firstOrNull;
      final product = instance == null ? null : products[instance.sku];
      if (product == null) {
        errors.add('物件不属于家庭库存');
        continue;
      }
      if (product.placement == 'ground') {
        if (item.slot != null || !['x', 'y'].contains(item.facing)) {
          errors.add('地面家具位置或朝向无效');
          continue;
        }
        final count = counts.update(
          product.kind,
          (n) => n + 1,
          ifAbsent: () => 1,
        );
        if (count > (categoryLimits[product.kind] ?? 64)) {
          errors.add('超出房间类别上限');
        }
        for (final cell in product.cells(item.facing)) {
          final x = cell.$1 + item.gx, y = cell.$2 + item.gy;
          if (x < 0 || y < 0 || x >= 8 || y >= 8) errors.add('家具超出地板边界');
          if (!cells.add((x, y))) errors.add('家具占格冲突');
        }
      } else {
        if (slots[item.slot] != product.placement ||
            !usedSlots.add(item.slot ?? '')) {
          errors.add('固定挂位不匹配或已占用');
        }
        if (product.placement == 'art' &&
            ((product.artwork != null && item.artwork != product.artwork) ||
                ![
                  'starry',
                  'mona',
                  'scream',
                  'pearl',
                  'sunflowers',
                ].contains(item.artwork))) {
          errors.add('画作无效');
        }
        if (item.gx != 0 || item.gy != 0 || item.facing != 'x') {
          errors.add('固定物件不可自由移动');
        }
      }
    }
    return errors.toSet().toList();
  }
}

String nextMount(
  PlacementRules rules,
  FurnitureProduct product,
  String? current,
) {
  final slots = rules.slots.entries
      .where((e) => e.value == product.placement)
      .map((e) => e.key)
      .toList();
  return slots[(slots.indexOf(current ?? '') + 1) % slots.length];
}

class LayoutDraft {
  LayoutDraft(this.layout, this.baseVersion, {this.preview, this.replacing});
  RoomLayout layout;
  final int baseVersion;
  PlacedItem? preview;
  String? replacing;
  RoomLayout candidate({String? replacing}) => RoomLayout([
    for (final item in layout.items)
      if (item.instanceId != preview?.instanceId &&
          item.instanceId != (replacing ?? this.replacing))
        item,
    ?preview,
  ]);
  void confirm(PlacementRules rules, {String? replacing}) {
    final next = candidate(replacing: replacing);
    final errors = rules.validate(next);
    if (errors.isNotEmpty) throw StateError(errors.join('；'));
    layout = next;
    preview = null;
    this.replacing = null;
  }

  void cancelPreview() {
    preview = null;
    replacing = null;
  }

  void stow(String id) {
    layout = RoomLayout(layout.items.where((i) => i.instanceId != id).toList());
    preview = null;
    replacing = null;
  }

  Map<String, dynamic> toJson() => {
    'base_version': baseVersion,
    'layout': layout.toJson(),
    'preview': preview?.toJson(),
    'replacing': replacing,
  };
  factory LayoutDraft.fromJson(Map value) => LayoutDraft(
    RoomLayout.fromJson(value['layout']),
    value['base_version'],
    preview: value['preview'] == null
        ? null
        : PlacedItem.fromJson(value['preview']),
    replacing: value['replacing'],
  );
  String encode() => jsonEncode(toJson());
}
