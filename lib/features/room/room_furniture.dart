import 'package:shared_preferences/shared_preferences.dart';

enum FurnitureStyle {
  lunar('月轨阅读舱');

  const FurnitureStyle(this.label);
  final String label;
}

enum WallStyle {
  lunar('月轨星纹');

  const WallStyle(this.label);
  final String label;
}

enum FloorStyle {
  lunar('月轨浅木');

  const FloorStyle(this.label);
  final String label;
}

List<FurnitureStyle> stylesFor(String kind) => const [FurnitureStyle.lunar];

enum ArtworkStyle {
  starry('爪印星夜'),
  mona('猫娜丽莎'),
  scream('喵的呐喊'),
  pearl('戴珍珠耳环的猫'),
  sunflowers('向日葵');

  const ArtworkStyle(this.label);
  final String label;
  String get asset => 'room/painting-$name.png';
}

const furnitureNames = {
  'window': '窗户',
  'chair': '椅子',
  'bookshelf': '书柜',
  'bed': '猫窝',
  'desk': '书桌',
  'tree': '猫爬架',
  'rug': '地毯',
};

const lunarFurnitureLocations = {
  'window': '两堵墙各居中 · 日间淡月／夜间星月',
  'bookshelf': '左墙内侧 · 1×3 格 · 高 3 格',
  'desk': '右侧阅读区 · 3×2 格',
  'chair': '书桌后侧 · 1×1 格',
  'tree': '左侧攀爬区 · 2×2 格',
  'bed': '地板前侧 · 2×2 格 · 开放软垫',
  'rug': '地板中央 · 固定 6×6 格',
};

class RoomFurnishings {
  const RoomFurnishings({
    this.styles = const {},
    this.hidden = const {},
    this.wall = WallStyle.lunar,
    this.floor = FloorStyle.lunar,
    this.artwork = ArtworkStyle.starry,
    this.facings = const {},
    this.frameTemplate = 'auto',
  });

  final Map<String, FurnitureStyle> styles;
  final Set<String> hidden;
  final WallStyle wall;
  final FloorStyle floor;
  final ArtworkStyle artwork;
  final Map<String, String> facings;
  final String frameTemplate;
  String facingFor(String kind) =>
      facings[kind] ?? (['desk', 'chair', 'bed'].contains(kind) ? 'y' : 'x');

  FurnitureStyle styleFor(String kind) => styles[kind] ?? stylesFor(kind).first;
  bool isVisible(String kind) => !hidden.contains(kind);

  RoomFurnishings _copy({
    Map<String, FurnitureStyle>? styles,
    Set<String>? hidden,
    WallStyle? wall,
    FloorStyle? floor,
    ArtworkStyle? artwork,
    Map<String, String>? facings,
    String? frameTemplate,
  }) => RoomFurnishings(
    styles: styles ?? this.styles,
    hidden: hidden ?? this.hidden,
    wall: wall ?? this.wall,
    floor: floor ?? this.floor,
    artwork: artwork ?? this.artwork,
    facings: facings ?? this.facings,
    frameTemplate: frameTemplate ?? this.frameTemplate,
  );

  RoomFurnishings withStyle(String kind, FurnitureStyle style) {
    if (!furnitureNames.containsKey(kind) || !stylesFor(kind).contains(style)) {
      throw ArgumentError('Unavailable furniture: $kind / $style');
    }
    return _copy(
      styles: {...styles, kind: style},
      hidden: {...hidden}..remove(kind),
    );
  }

  RoomFurnishings withVisibility(String kind, bool visible) => _copy(
    styles: visible && furnitureNames.containsKey(kind)
        ? {...styles, kind: styleFor(kind)}
        : styles,
    hidden: visible ? ({...hidden}..remove(kind)) : {...hidden, kind},
  );

  RoomFurnishings withWall(WallStyle next) => _copy(wall: next);
  RoomFurnishings withFacing(String kind, String facing) {
    if (!['desk', 'chair', 'bed', 'bookshelf', 'tree'].contains(kind) ||
        !['x', 'y'].contains(facing)) {
      throw ArgumentError('Invalid furniture facing');
    }
    return _copy(facings: {...facings, kind: facing});
  }

  RoomFurnishings withFrameTemplate(String template) {
    if (!['auto', 'landscape', 'portrait', 'square'].contains(template)) {
      throw ArgumentError('Invalid frame template');
    }
    return _copy(frameTemplate: template);
  }

  RoomFurnishings withFloor(FloorStyle next) => _copy(floor: next);
  RoomFurnishings withArtwork(ArtworkStyle next) =>
      _copy(artwork: next, hidden: {...hidden}..remove('painting'));

  RoomFurnishings withSet(FurnitureStyle style) {
    return _copy(
      styles: {for (final kind in furnitureNames.keys) kind: style},
      hidden: {...hidden}
        ..removeAll([...furnitureNames.keys, 'window-left', 'window-right']),
      wall: WallStyle.lunar,
      floor: FloorStyle.lunar,
      facings: const {},
      frameTemplate: 'auto',
    );
  }

  static String _key(String? ownerId) =>
      'room_furniture_v1_${ownerId ?? 'preview'}';

  static Future<RoomFurnishings> load(String? ownerId) async {
    final stored = (await SharedPreferences.getInstance()).getStringList(
      _key(ownerId),
    );
    final styles = <String, FurnitureStyle>{};
    final hidden = <String>{};
    var wall = WallStyle.lunar;
    var floor = FloorStyle.lunar;
    var artwork = ArtworkStyle.starry;
    final facings = <String, String>{};
    var frameTemplate = 'auto';
    for (final value in stored ?? <String>[]) {
      final parts = value.split('|');
      if (parts.length != 3 || !['0', '1'].contains(parts[2])) continue;
      final kind = parts[0];
      if (kind.startsWith('facing-') &&
          [
            'desk',
            'chair',
            'bed',
            'bookshelf',
            'tree',
          ].contains(kind.substring(7)) &&
          ['x', 'y'].contains(parts[1])) {
        facings[kind.substring(7)] = parts[1];
      } else if (kind == 'frame-template' &&
          ['auto', 'landscape', 'portrait', 'square'].contains(parts[1])) {
        frameTemplate = parts[1];
      } else if (['window-left', 'window-right'].contains(kind)) {
        if (parts[2] == '0') hidden.add(kind);
      } else if (kind == 'wall') {
        wall =
            WallStyle.values.where((s) => s.name == parts[1]).firstOrNull ??
            wall;
      } else if (kind == 'floor') {
        floor =
            FloorStyle.values.where((s) => s.name == parts[1]).firstOrNull ??
            floor;
      } else if (kind == 'painting') {
        final style = ArtworkStyle.values
            .where((s) => s.name == parts[1])
            .firstOrNull;
        if (style != null) {
          artwork = style;
          if (parts[2] == '0') hidden.add(kind);
        }
      } else if (furnitureNames.containsKey(kind)) {
        styles[kind] = FurnitureStyle.lunar;
        if (parts[2] == '0') hidden.add(kind);
      }
    }
    return RoomFurnishings(
      styles: styles,
      hidden: hidden,
      wall: wall,
      floor: floor,
      artwork: artwork,
      facings: facings,
      frameTemplate: frameTemplate,
    );
  }

  Future<void> save(String? ownerId) async {
    final saved = await (await SharedPreferences.getInstance()).setStringList(
      _key(ownerId),
      [
        'wall|${wall.name}|1',
        'floor|${floor.name}|1',
        'frame-template|$frameTemplate|1',
        for (final facing in facings.entries)
          'facing-${facing.key}|${facing.value}|1',
        for (final side in ['left', 'right'])
          'window-$side|lunar|${isVisible('window-$side') ? '1' : '0'}',
        'painting|${artwork.name}|${isVisible('painting') ? '1' : '0'}',
        for (final kind in furnitureNames.keys)
          '$kind|${styleFor(kind).name}|${isVisible(kind) ? '1' : '0'}',
      ],
    );
    if (!saved) throw StateError('Furniture preferences were not saved');
  }
}
