import 'dart:typed_data';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import '../../room_layout.dart';

enum FurnitureStyle {
  cream('原木奶油'),
  sage('胡桃鼠尾草'),
  lunar('月轨阅读舱'),
  bauhaus('包豪斯');

  const FurnitureStyle(this.label);
  final String label;
}

enum WallStyle {
  cream('奶油抹灰', 'room/shell.png'),
  sage('鼠尾草护墙', 'room/shell-sage.png'),
  blue('雾蓝壁纸', 'room/shell-blue.png'),
  lunar('月轨星纹', 'room/lunar-wall.png'),
  bauhaus('包豪斯几何', 'room/bauhaus-wall.png');

  const WallStyle(this.label, this.asset);
  final String label;
  final String asset;
}

enum FloorStyle {
  oak('原木地板', 'room/floor-oak.png'),
  lunar('月轨浅木', 'room/lunar-floor.png'),
  bauhaus('包豪斯拼木', 'room/bauhaus-floor.png');

  const FloorStyle(this.label, this.asset);
  final String label;
  final String asset;
}

List<FurnitureStyle> stylesFor(String kind) => kind == 'tree' || kind == 'rug'
    ? const [FurnitureStyle.lunar, FurnitureStyle.bauhaus]
    : FurnitureStyle.values;

String furnitureAsset(
  String kind,
  FurnitureStyle style, {
  bool covered = false,
}) {
  if (style == FurnitureStyle.cream) return 'room/furniture-cream.png';
  if (style == FurnitureStyle.sage) return 'room/furniture-sage-v2.png';
  final variant = kind == 'chair'
      ? '-v2'
      : kind == 'bed' && style == FurnitureStyle.lunar && covered
      ? '-covered'
      : '';
  return 'room/${style.name}-$kind$variant.png';
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
  'tree': '猫爬架',
  'rug': '地毯',
};

const furnitureLocations = {
  'window': '右侧墙面 · 书桌上方',
  'chair': '书桌前一格 · 面向桌面',
  'bookshelf': '左墙内侧 · 靠近墙角',
  'bed': '地板前端中央 · 留出边距',
  'desk': '右侧靠墙 · 临窗阅读',
  'tree': '左墙前侧 · 独立攀爬区',
  'rug': '地板正中 · 家具下方',
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
    this.excluded = const [],
  ]);
  final Offset anchor;
  final double positiveSlope;
  final double? negativeSlope;
  final List<Offset> feet;
  final List<Rect> excluded;

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
    if (excluded.isNotEmpty) {
      final clip = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(source.shift(-anchor));
      for (final rect in excluded) {
        clip.addRect(rect.shift(-anchor));
      }
      canvas.clipPath(clip);
    }
    canvas.drawImageRect(
      image,
      source,
      source.shift(-anchor),
      Paint()..filterQuality = FilterQuality.medium,
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
    'chair': FurnitureGeometry(
      Offset(804, 598),
      0.55,
      -0.55,
      [Offset(677, 542), Offset(804, 598), Offset(924, 533)],
      [Rect.fromLTRB(660, 577, 750, 606), Rect.fromLTRB(900, 577, 940, 606)],
    ),
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
    'desk': FurnitureGeometry(
      Offset(740.5, 932.5),
      0.488,
      -0.566,
      [
        Offset(568, 861),
        Offset(913, 1004),
        Offset(1046, 930),
        Offset(682, 797),
      ],
      [Rect.fromLTRB(787, 580, 826, 614)],
    ),
  },
};

// Each modern piece is a separate cutout, so adjacent atlas pixels cannot leak.
const modernSources = {
  FurnitureStyle.lunar: {
    'window': Rect.fromLTRB(43, 58, 1494, 942),
    'desk': Rect.fromLTRB(72, 19, 1338, 1100),
    'chair': Rect.fromLTRB(135, 127, 1151, 1157),
    'bookshelf': Rect.fromLTRB(292, 8, 1002, 1250),
    'bed': Rect.fromLTRB(45, 271, 1225, 1106),
    'tree': Rect.fromLTRB(214, 37, 929, 1298),
    'rug': Rect.fromLTRB(23, 33, 1234, 1220),
  },
  FurnitureStyle.bauhaus: {
    'window': Rect.fromLTRB(76, 90, 1460, 936),
    'desk': Rect.fromLTRB(125, 73, 1175, 1208),
    'chair': Rect.fromLTRB(155, 129, 1144, 1127),
    'bookshelf': Rect.fromLTRB(319, 21, 935, 1227),
    'bed': Rect.fromLTRB(83, 243, 1188, 1047),
    'tree': Rect.fromLTRB(120, 67, 984, 1319),
    'rug': Rect.fromLTRB(93, 94, 1443, 933),
  },
};
const modernGeometry = {
  FurnitureStyle.lunar: {
    'window': FurnitureGeometry(Offset(768, 500), 0, null),
    'desk': FurnitureGeometry(Offset(580, 1139.798), 0.322, -0.821, [
      Offset(113, 794),
      Offset(1047, 1095),
      Offset(1299, 888),
      Offset(347, 643),
    ]),
    'chair': FurnitureGeometry(Offset(639, 1145), 0.567, -0.499, [
      Offset(214, 904),
      Offset(639, 1145),
      Offset(1114, 908),
    ]),
    'bookshelf': FurnitureGeometry(Offset(327, 1123), 0.853, -0.29255, [
      Offset(297, 1132),
      Offset(426, 1242),
      Offset(990, 1077),
    ]),
    'bed': FurnitureGeometry(Offset(637, 1095), 0.674, -0.674, [
      Offset(210, 935),
      Offset(637, 1095),
      Offset(1080, 939),
    ]),
    'tree': FurnitureGeometry(Offset(572, 1290), 0.674, -0.674, [
      Offset(275, 1198),
      Offset(572, 1290),
      Offset(861, 1205),
    ]),
    'rug': FurnitureGeometry(Offset(0, 0), 0, null),
  },
  FurnitureStyle.bauhaus: {
    'window': FurnitureGeometry(Offset(768, 500), 0, null),
    'desk': FurnitureGeometry(Offset(500, 1135.612), 0.4503, -0.60, [
      Offset(162, 899),
      Offset(826, 1198),
      Offset(1138, 1003),
      Offset(408, 751),
    ]),
    'chair': FurnitureGeometry(Offset(704, 1113), 0.569, -0.6005, [
      Offset(207, 830),
      Offset(704, 1113),
      Offset(1102, 874),
    ]),
    'bookshelf': FurnitureGeometry(Offset(330, 1115), 0.649, -0.345, [
      Offset(330, 1115),
      Offset(478, 1211),
      Offset(916, 1060),
    ]),
    'bed': FurnitureGeometry(Offset(637, 1040), 0.674, -0.674, [
      Offset(210, 855),
      Offset(637, 1040),
      Offset(1065, 852),
    ]),
    'tree': FurnitureGeometry(Offset(640, 1305), 0.54, -0.58, [
      Offset(177, 1100),
      Offset(640, 1305),
      Offset(936, 1100),
    ]),
    'rug': FurnitureGeometry(Offset(0, 0), 0, null),
  },
};
const coveredBedSource = Rect.fromLTRB(44, 80, 1230, 1205);
const coveredBedGeometry = FurnitureGeometry(Offset(637, 1195), 0.674, -0.674, [
  Offset(213, 1053),
  Offset(637, 1195),
  Offset(1068, 1056),
]);

Rect sourceFor(String kind, FurnitureStyle style, {bool covered = false}) =>
    kind == 'bed' && style == FurnitureStyle.lunar && covered
    ? coveredBedSource
    : (furnitureSources[style] ?? modernSources[style])![kind]!;
FurnitureGeometry geometryFor(
  String kind,
  FurnitureStyle style, {
  bool covered = false,
}) => kind == 'bed' && style == FurnitureStyle.lunar && covered
    ? coveredBedGeometry
    : (furnitureGeometry[style] ?? modernGeometry[style])![kind]!;

double furnitureScale(
  String kind,
  FurnitureStyle style, {
  bool covered = false,
}) {
  final source = sourceFor(kind, style, covered: covered);
  final widthScale = furnitureWidths[kind]! / source.width;
  final height = kind == 'tree'
      ? 285.0
      : (style == FurnitureStyle.lunar || style == FurnitureStyle.bauhaus)
      ? switch (kind) {
          'bookshelf' => 390.0,
          'desk' => 300.0,
          _ => null,
        }
      : null;
  if (height == null) return widthScale;
  final heightScale = height / geometryFor(kind, style).bounds(source).height;
  return widthScale < heightScale ? widthScale : heightScale;
}

const furnitureWidths = {
  'window': 215.0,
  'chair': 125.0,
  'bookshelf': 185.0,
  'bed': 165.0,
  'desk': 270.0,
  'tree': 175.0,
  'rug': 330.0,
};

class RoomFurnishings {
  const RoomFurnishings({
    this.styles = const {},
    this.hidden = const {},
    this.wall = WallStyle.cream,
    this.floor = FloorStyle.oak,
    this.artwork = ArtworkStyle.starry,
    this.bedCovered = false,
    this.facings = const {},
    this.frameTemplate = 'auto',
  });

  final Map<String, FurnitureStyle> styles;
  final Set<String> hidden;
  final WallStyle wall;
  final FloorStyle floor;
  final ArtworkStyle artwork;
  final bool bedCovered;
  final Map<String, String> facings;
  final String frameTemplate;
  bool get usesLunarRoom =>
      wall == WallStyle.lunar ||
      floor == FloorStyle.lunar ||
      styles.values.contains(FurnitureStyle.lunar);
  String facingFor(String kind) =>
      facings[kind] ?? (['desk', 'chair', 'bed'].contains(kind) ? 'y' : 'x');

  FurnitureStyle styleFor(String kind) => styles[kind] ?? stylesFor(kind).first;
  // New slots stay absent in existing rooms until the user selects them.
  bool isVisible(String kind) =>
      !hidden.contains(kind) &&
      (styles.containsKey(kind) || (kind != 'tree' && kind != 'rug'));

  RoomFurnishings _copy({
    Map<String, FurnitureStyle>? styles,
    Set<String>? hidden,
    WallStyle? wall,
    FloorStyle? floor,
    ArtworkStyle? artwork,
    bool? bedCovered,
    Map<String, String>? facings,
    String? frameTemplate,
  }) => RoomFurnishings(
    styles: styles ?? this.styles,
    hidden: hidden ?? this.hidden,
    wall: wall ?? this.wall,
    floor: floor ?? this.floor,
    artwork: artwork ?? this.artwork,
    bedCovered: bedCovered ?? this.bedCovered,
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
  RoomFurnishings withBedCovered(bool next) => _copy(bedCovered: next);
  RoomFurnishings withArtwork(ArtworkStyle next) =>
      _copy(artwork: next, hidden: {...hidden}..remove('painting'));

  RoomFurnishings withSet(FurnitureStyle style) {
    if (style != FurnitureStyle.lunar && style != FurnitureStyle.bauhaus) {
      throw ArgumentError('Not a complete modern set: $style');
    }
    return _copy(
      styles: {for (final kind in furnitureNames.keys) kind: style},
      hidden: {...hidden}..removeAll(furnitureNames.keys),
      wall: style == FurnitureStyle.lunar ? WallStyle.lunar : WallStyle.bauhaus,
      floor: style == FurnitureStyle.lunar
          ? FloorStyle.lunar
          : FloorStyle.bauhaus,
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
    if (stored == null && ownerId == null) {
      return RoomFurnishings(
        styles: {
          for (final kind in furnitureNames.keys)
            if (stylesFor(kind).contains(FurnitureStyle.sage))
              kind: FurnitureStyle.sage,
        },
        wall: WallStyle.sage,
      );
    }
    final styles = <String, FurnitureStyle>{};
    final hidden = <String>{};
    var wall = WallStyle.cream;
    var floor = FloorStyle.oak;
    var artwork = ArtworkStyle.starry;
    var bedCovered = false;
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
      } else if (kind == 'bed-canopy') {
        if (parts[1] == 'covered') bedCovered = parts[2] == '1';
      } else if (kind == 'painting') {
        final style = ArtworkStyle.values
            .where((s) => s.name == parts[1])
            .firstOrNull;
        if (style != null) {
          artwork = style;
          if (parts[2] == '0') hidden.add(kind);
        }
      } else if (furnitureNames.containsKey(kind)) {
        final style = stylesFor(
          kind,
        ).where((s) => s.name == parts[1]).firstOrNull;
        if (style != null) {
          styles[kind] = style;
          if (parts[2] == '0') hidden.add(kind);
        }
      }
    }
    return RoomFurnishings(
      styles: styles,
      hidden: hidden,
      wall: wall,
      floor: floor,
      artwork: artwork,
      bedCovered: bedCovered,
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
        'bed-canopy|covered|${bedCovered ? '1' : '0'}',
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
