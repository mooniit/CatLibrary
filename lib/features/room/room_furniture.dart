import 'dart:typed_data';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import '../../room_layout.dart';

enum FurnitureStyle {
  cream('原木奶油'),
  sage('胡桃鼠尾草');

  const FurnitureStyle(this.label);
  final String label;
  String get asset => 'room/furniture-${this == sage ? 'sage-v2' : name}.png';
}

enum WallStyle {
  cream('奶油抹灰', 'room/shell.png'),
  sage('鼠尾草护墙', 'room/shell-sage.png'),
  blue('雾蓝壁纸', 'room/shell-blue.png');

  const WallStyle(this.label, this.asset);
  final String label;
  final String asset;
}

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
};

const furnitureLocations = {
  'window': '右侧墙面 · 书桌上方',
  'chair': '书桌前一格 · 面向桌面',
  'bookshelf': '左墙内侧 · 靠近墙角',
  'bed': '右墙外侧 · 底角边缘',
  'desk': '右侧靠墙 · 临窗阅读',
};

// Pixel measurements belong to the artwork; placement belongs to RoomLayout.
const furnitureSources = {
  FurnitureStyle.cream: {
    'window': Rect.fromLTRB(57, 87, 417, 622),
    'chair': Rect.fromLTRB(499, 271, 801, 663),
    'bookshelf': Rect.fromLTRB(864, 53, 1211, 666),
    'bed': Rect.fromLTRB(30, 834, 410, 1141),
    'desk': Rect.fromLTRB(420, 693, 912, 1185),
  },
  FurnitureStyle.sage: {
    'window': Rect.fromLTRB(108, 38, 512, 573),
    'chair': Rect.fromLTRB(660, 237, 940, 606),
    'bookshelf': Rect.fromLTRB(1117, 26, 1450, 701),
    'bed': Rect.fromLTRB(97, 676, 463, 963),
    'desk': Rect.fromLTRB(547, 580, 1070, 1008),
  },
};

class FurnitureGeometry {
  const FurnitureGeometry(
    this.anchor,
    this.positiveSlope,
    this.negativeSlope, [
    this.feet = const [],
    this.excluded,
  ]);
  final Offset anchor;
  final double positiveSlope;
  final double? negativeSlope;
  final List<Offset> feet;
  final Rect? excluded;

  double get verticalScale => negativeSlope == null
      ? 1
      : 2 * RoomLayout.slope / (positiveSlope - negativeSlope!);
  double get shear => RoomLayout.slope - positiveSlope * verticalScale;

  Offset project(Offset pixel, double scale, Offset position) {
    final local = pixel - anchor;
    return position +
        Offset(local.dx, local.dy * verticalScale + local.dx * shear) * scale;
  }

  Rect bounds(Rect source) {
    final points = [
      source.topLeft,
      source.topRight,
      source.bottomLeft,
      source.bottomRight,
    ].map((p) => project(p, 1, Offset.zero));
    return Rect.fromLTRB(
      points.map((p) => p.dx).reduce((a, b) => a < b ? a : b),
      points.map((p) => p.dy).reduce((a, b) => a < b ? a : b),
      points.map((p) => p.dx).reduce((a, b) => a > b ? a : b),
      points.map((p) => p.dy).reduce((a, b) => a > b ? a : b),
    );
  }

  void draw(
    Canvas canvas,
    Image image,
    Rect source,
    double scale,
    Offset position,
  ) {
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.transform(
      Float64List.fromList([
        scale,
        shear * scale,
        0,
        0,
        0,
        verticalScale * scale,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
      ]),
    );
    if (excluded != null) {
      canvas.clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(source.shift(-anchor))
          ..addRect(excluded!.shift(-anchor)),
      );
    }
    canvas.drawImageRect(
      image,
      source,
      source.shift(-anchor),
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  }
}

const furnitureGeometry = {
  FurnitureStyle.cream: {
    'window': FurnitureGeometry(Offset(410, 612), 0.515, null),
    'chair': FurnitureGeometry(Offset(653, 659), 0.55, -0.55, [
      Offset(529, 593),
      Offset(653, 659),
      Offset(782, 583),
    ]),
    'bookshelf': FurnitureGeometry(Offset(870, 618), 0.6, -0.555, [
      Offset(870, 618),
      Offset(942, 660),
      Offset(1204, 517),
    ]),
    'bed': FurnitureGeometry(Offset(218, 1132), 0.55, -0.55, [
      Offset(60, 1046),
      Offset(218, 1132),
      Offset(386, 1046),
    ]),
    'desk': FurnitureGeometry(Offset(601, 1102.5), 0.486, -0.556, [
      Offset(443, 1028),
      Offset(759, 1177),
      Offset(882, 1098),
      Offset(548, 951),
    ]),
  },
  FurnitureStyle.sage: {
    'window': FurnitureGeometry(Offset(491, 567), 0.526, null),
    'chair': FurnitureGeometry(Offset(804, 598), 0.55, -0.55, [
      Offset(677, 542),
      Offset(804, 598),
      Offset(924, 533),
    ], Rect.fromLTRB(660, 577, 750, 606)),
    'bookshelf': FurnitureGeometry(Offset(1123, 658), 0.615, -0.554, [
      Offset(1123, 658),
      Offset(1187, 694),
      Offset(1438, 564),
    ]),
    'bed': FurnitureGeometry(Offset(280, 954), 0.55, -0.55, [
      Offset(122, 830),
      Offset(280, 954),
      Offset(443, 830),
    ]),
    'desk': FurnitureGeometry(Offset(740.5, 932.5), 0.488, -0.566, [
      Offset(568, 861),
      Offset(913, 1004),
      Offset(1046, 930),
      Offset(682, 797),
    ], Rect.fromLTRB(787, 580, 826, 614)),
  },
};

const furnitureWidths = {
  'window': 190.0,
  'chair': 125.0,
  'bookshelf': 185.0,
  'bed': 165.0,
  'desk': 270.0,
};

class RoomFurnishings {
  const RoomFurnishings({
    this.styles = const {},
    this.hidden = const {},
    this.wall = WallStyle.cream,
    this.artwork = ArtworkStyle.starry,
  });

  final Map<String, FurnitureStyle> styles;
  final Set<String> hidden;
  final WallStyle wall;
  final ArtworkStyle artwork;

  FurnitureStyle styleFor(String kind) => styles[kind] ?? FurnitureStyle.cream;
  bool isVisible(String kind) => !hidden.contains(kind);

  RoomFurnishings withStyle(String kind, FurnitureStyle style) =>
      RoomFurnishings(
        styles: {...styles, kind: style},
        hidden: {...hidden}..remove(kind),
        wall: wall,
        artwork: artwork,
      );

  RoomFurnishings withVisibility(String kind, bool visible) => RoomFurnishings(
    styles: styles,
    hidden: visible ? ({...hidden}..remove(kind)) : {...hidden, kind},
    wall: wall,
    artwork: artwork,
  );

  RoomFurnishings withWall(WallStyle next) => RoomFurnishings(
    styles: styles,
    hidden: hidden,
    wall: next,
    artwork: artwork,
  );

  RoomFurnishings withArtwork(ArtworkStyle next) => RoomFurnishings(
    styles: styles,
    hidden: {...hidden}..remove('painting'),
    wall: wall,
    artwork: next,
  );

  static String _key(String? ownerId) =>
      'room_furniture_v1_${ownerId ?? 'preview'}';

  static Future<RoomFurnishings> load(String? ownerId) async {
    final stored = (await SharedPreferences.getInstance()).getStringList(
      _key(ownerId),
    );
    if (stored == null && ownerId == null) {
      return RoomFurnishings(
        styles: {
          for (final kind in furnitureNames.keys) kind: FurnitureStyle.sage,
        },
        wall: WallStyle.sage,
      );
    }
    final values = stored ?? [];
    final styles = <String, FurnitureStyle>{};
    final hidden = <String>{};
    var wall = WallStyle.cream;
    var artwork = ArtworkStyle.starry;
    for (final value in values) {
      final parts = value.split('|');
      if (parts.length == 3 && parts[0] == 'painting') {
        final style = ArtworkStyle.values
            .where((s) => s.name == parts[1])
            .firstOrNull;
        if (style != null && ['0', '1'].contains(parts[2])) {
          artwork = style;
          if (parts[2] == '0') hidden.add('painting');
        }
        continue;
      }
      if (parts.length == 3 && parts[0] == 'wall') {
        wall =
            WallStyle.values.where((s) => s.name == parts[1]).firstOrNull ??
            wall;
        continue;
      }
      if (parts.length != 3 || !RoomLayout.defaults.containsKey(parts[0])) {
        continue;
      }
      final style = FurnitureStyle.values
          .where((s) => s.name == parts[1])
          .firstOrNull;
      if (style == null || !['0', '1'].contains(parts[2])) continue;
      styles[parts[0]] = style;
      if (parts[2] == '0') hidden.add(parts[0]);
    }
    return RoomFurnishings(
      styles: styles,
      hidden: hidden,
      wall: wall,
      artwork: artwork,
    );
  }

  Future<void> save(String? ownerId) async {
    final saved = await (await SharedPreferences.getInstance())
        .setStringList(_key(ownerId), [
          'wall|${wall.name}|1',
          'painting|${artwork.name}|${isVisible('painting') ? '1' : '0'}',
          for (final kind in RoomLayout.defaults.keys)
            '$kind|${styleFor(kind).name}|${isVisible(kind) ? '1' : '0'}',
        ]);
    if (!saved) throw StateError('Furniture preferences were not saved');
  }
}
