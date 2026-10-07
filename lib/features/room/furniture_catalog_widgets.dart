import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'lunar_room.dart';
import 'room_furniture.dart';
import 'layout_draft.dart';
import 'souvenir_sculpture.dart';

const furnitureCategories = {
  'all': 'All',
  'furniture': '家具',
  'cats': '猫用',
  'decoration': '装饰',
  'windows': '窗画',
  'renovation': '装修',
};

const furnitureCategoryIcons = {
  'furniture': Icons.chair_outlined,
  'cats': Icons.pets_outlined,
  'decoration': Icons.texture_outlined,
  'windows': Icons.photo_library_outlined,
  'renovation': Icons.space_dashboard_outlined,
};

String furnitureCategory(String kind) => switch (kind) {
  'bookshelf' || 'desk' || 'chair' => 'furniture',
  'tree' || 'bed' => 'cats',
  'rug' || 'souvenir' => 'decoration',
  'window' || 'frame' || 'painting' => 'windows',
  'wall' || 'floor' => 'renovation',
  _ => throw ArgumentError.value(kind, 'kind', 'Unregistered furniture kind'),
};

bool matchesFurnitureCategory(String category, String kind) =>
    category == 'all' || furnitureCategory(kind) == category;

class RoomCategoryIcon extends StatelessWidget {
  const RoomCategoryIcon({
    super.key,
    required this.category,
    required this.color,
  });
  final String category;
  final Color color;
  @override
  Widget build(BuildContext context) =>
      ['decoration', 'renovation'].contains(category)
      ? CustomPaint(
          size: const Size(22, 22),
          painter: _SurfaceIcon(category, color),
        )
      : Icon(furnitureCategoryIcons[category], size: 22, color: color);
}

class _SurfaceIcon extends CustomPainter {
  _SurfaceIcon(this.category, this.color);
  final String category;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (category == 'decoration') {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(4, 5, 14, 12),
          const Radius.circular(1),
        ),
        pen,
      );
      canvas.drawRect(const Rect.fromLTWH(7, 8, 8, 6), pen);
      for (final x in [6.0, 11.0, 16.0]) {
        canvas.drawLine(Offset(x, 3), Offset(x, 5), pen);
        canvas.drawLine(Offset(x, 17), Offset(x, 19), pen);
      }
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(3, 14)
          ..lineTo(3, 5)
          ..lineTo(11, 2)
          ..lineTo(19, 5)
          ..lineTo(19, 14)
          ..lineTo(11, 20)
          ..close(),
        pen,
      );
      canvas.drawLine(const Offset(11, 2), const Offset(11, 10), pen);
      canvas.drawPath(
        Path()
          ..moveTo(3, 14)
          ..lineTo(11, 10)
          ..lineTo(19, 14),
        pen,
      );
      canvas.drawLine(const Offset(7, 17), const Offset(15, 12), pen);
      canvas.drawLine(const Offset(7, 12), const Offset(15, 17), pen);
    }
  }

  @override
  bool shouldRepaint(_SurfaceIcon old) =>
      old.color != color || old.category != category;
}

/// Artwork cards use the exact mounted frame and uncropped painting renderer.
class FurnitureThumbnail extends StatelessWidget {
  const FurnitureThumbnail({super.key, required this.product});
  final FurnitureProduct product;
  static final _thumbnails = <String, Future<ui.Image>>{};
  static final _images = <String, Future<ui.Image>>{};
  static Future<ui.Image> _image(String path) =>
      _images.putIfAbsent(path, () async {
        final bytes = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        final frame = await codec.getNextFrame();
        codec.dispose();
        return frame.image;
      });
  static Future<ui.Image> _painting(FurnitureProduct p) async {
    final catalog =
        jsonDecode(await rootBundle.loadString('${p.assetRoot}catalog.json'))
            as Map<String, dynamic>;
    final frame = p.sprite;
    final art = ArtworkStyle.values.byName(p.artwork!);
    final renderer = LunarRoom(catalog, {
      frame: await _image('${p.assetRoot}$frame.png'),
    });
    final item = PlacedItem(
      'thumbnail',
      slot: 'art-left-back',
      artwork: p.artwork!,
    );
    final bounds = renderer.placedSpriteBounds(item, p, {p.theme: renderer});
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final scale = (300 / bounds.width).clamp(0.0, 210 / bounds.height);
    canvas.translate(
      (320 - bounds.width * scale) / 2,
      (230 - bounds.height * scale) / 2,
    );
    canvas.scale(scale);
    canvas.translate(-bounds.left, -bounds.top);
    renderer.renderGhost(
      canvas,
      item,
      p,
      {p.theme: renderer},
      false,
      {art: await _image('assets/images/${art.asset}')},
      opacity: 1,
    );
    final picture = recorder.endRecording();
    final result = await picture.toImage(320, 230);
    picture.dispose();
    return result;
  }

  static Future<ui.Image> _souvenir(FurnitureProduct p) async {
    final catalog =
        jsonDecode(
              await rootBundle.loadString(
                'assets/images/room/lunar-v5/catalog.json',
              ),
            )
            as Map<String, dynamic>;
    final renderer = LunarRoom(catalog, {});
    await SouvenirSculpture.prepare(p, renderer.project);
    const item = PlacedItem('thumbnail');
    final bounds = SouvenirSculpture.bounds(item, p, renderer.project);
    final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
    final scale = (300 / bounds.width).clamp(0.0, 210 / bounds.height);
    canvas.translate(
      (320 - bounds.width * scale) / 2,
      (230 - bounds.height * scale) / 2,
    );
    canvas.scale(scale);
    canvas.translate(-bounds.left, -bounds.top);
    SouvenirSculpture.draw(canvas, item, p, renderer.project);
    final picture = recorder.endRecording(),
        result = await picture.toImage(320, 230);
    picture.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) => product.kind == 'souvenir'
      ? FutureBuilder<ui.Image>(
          future: _thumbnails.putIfAbsent(
            product.sku,
            () => _souvenir(product),
          ),
          builder: (_, snapshot) => snapshot.hasData
              ? RawImage(image: snapshot.data, fit: BoxFit.contain)
              : const SizedBox.shrink(),
        )
      : product.artwork == null
      ? Image.asset(
          '${product.assetRoot}${product.sprite}.png',
          fit: BoxFit.contain,
        )
      : FutureBuilder<ui.Image>(
          future: _thumbnails.putIfAbsent(
            '${product.theme}-${product.artwork}',
            () => _painting(product),
          ),
          builder: (_, snapshot) => snapshot.hasData
              ? RawImage(image: snapshot.data, fit: BoxFit.contain)
              : const SizedBox.shrink(),
        );
}

class FurnitureTool extends StatelessWidget {
  const FurnitureTool({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onPressed,
    icon: Icon(icon, size: 21),
    style: IconButton.styleFrom(
      minimumSize: const Size(44, 44),
      foregroundColor: Theme.of(context).colorScheme.primary,
    ),
  );
}

class FurnitureCategories extends StatelessWidget {
  const FurnitureCategories({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  final String selected;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          for (final e in furnitureCategories.entries)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Tooltip(
                  message: e.value,
                  child: Semantics(
                    label: e.value,
                    selected: selected == e.key,
                    button: true,
                    excludeSemantics: true,
                    onTap: () => onChanged(e.key),
                    child: Material(
                      color: selected == e.key
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.14)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        key: ValueKey('category-${e.key}'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => onChanged(e.key),
                        child: SizedBox(
                          width: 44,
                          child: Center(
                            child: e.key == 'all'
                                ? Text(
                                    'All',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  )
                                : RoomCategoryIcon(
                                    category: e.key,
                                    color: selected == e.key
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class FurnitureGrid extends StatelessWidget {
  const FurnitureGrid({
    super.key,
    required this.products,
    required this.inventory,
    required this.onTap,
    this.ownedOnly = false,
    this.layout,
  });
  final List<FurnitureProduct> products;
  final List<InventoryInstance> inventory;
  final ValueChanged<FurnitureProduct> onTap;
  final bool ownedOnly;
  final RoomLayout? layout;
  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return Center(child: Text(ownedOnly ? '这里还没有已拥有的家具' : '此分类暂无商品'));
    }
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, box) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisExtent: 124,
          crossAxisSpacing: 4,
          mainAxisSpacing: 8,
        ),
        itemCount: products.length,
        itemBuilder: (_, index) {
          final p = products[index];
          final instances = inventory.where((i) => i.sku == p.sku).toList();
          final own = instances.length;
          final placed = instances
              .where(
                (i) => layout?.items.any((x) => x.instanceId == i.id) == true,
              )
              .length;
          final count = p.kind == 'souvenir'
              ? '$own'
              : '$own/${p.purchaseLimit ?? 1}';
          return Material(
            color: colors.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Tooltip(
              message:
                  '${p.label}\n已拥有 $count${ownedOnly ? '\n已摆放 $placed，库存 ${own - placed}' : '\n${p.price ?? '—'} ${furnitureCurrency(p.currency)}'}',
              child: Semantics(
                label:
                    '${p.label}，已拥有 $count${ownedOnly ? '，已摆放 $placed，库存 ${own - placed}' : '，${p.price ?? '—'} ${furnitureCurrency(p.currency)}'}',
                button: true,
                excludeSemantics: true,
                onTap: () => onTap(p),
                child: InkWell(
                  key: ValueKey('product-${p.sku}'),
                  onTap: () => onTap(p),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      children: [
                        Expanded(child: FurnitureThumbnail(product: p)),
                        const SizedBox(height: 4),
                        Text(
                          count,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                        SizedBox(
                          height: 19,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                ownedOnly
                                    ? (placed > 0
                                          ? Icons.home_outlined
                                          : Icons.inventory_2_outlined)
                                    : own >= (p.purchaseLimit ?? 1)
                                    ? Icons.check_rounded
                                    : Icons.pets_outlined,
                                size: 12,
                                color: colors.primary,
                              ),
                              if (ownedOnly ||
                                  own < (p.purchaseLimit ?? 1)) ...[
                                const SizedBox(width: 3),
                                Text(
                                  ownedOnly
                                      ? '$placed / $own'
                                      : '${p.price ?? '—'}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: colors.primary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

String furnitureCurrency(String? currency) => switch (currency) {
  'miao' => '喵喵币',
  'eagle' => '鹰镑',
  'gem' => '宝石',
  _ => '待定币种',
};

typedef ProductAction = ({bool preview, int quantity});

class FurnitureDetails extends StatefulWidget {
  const FurnitureDetails({
    super.key,
    required this.product,
    required this.owned,
    required this.canPurchase,
    required this.unavailable,
    this.ownership,
  });
  final FurnitureProduct product;
  final int owned;
  final bool canPurchase;
  final String unavailable;
  final String? ownership;
  @override
  State<FurnitureDetails> createState() => _FurnitureDetailsState();
}

class _FurnitureDetailsState extends State<FurnitureDetails> {
  int quantity = 1;
  @override
  Widget build(BuildContext context) {
    final p = widget.product,
        remaining = (widget.product.purchaseLimit ?? 1) - widget.owned;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.label,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭详情',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                SizedBox(height: 180, child: FurnitureThumbnail(product: p)),
                const SizedBox(height: 12),
                Text(
                  p.kind == 'souvenir'
                      ? '已拥有 ${widget.owned}'
                      : '已拥有 ${widget.owned}/${p.purchaseLimit ?? 1}',
                ),
                if (widget.ownership != null)
                  Text(
                    widget.ownership!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 8),
                IconButton.filledTonal(
                  key: const Key('product-preview'),
                  tooltip: '在小窝中预览',
                  onPressed: () =>
                      Navigator.pop(context, (preview: true, quantity: 1)),
                  icon: const Icon(Icons.visibility_outlined),
                ),
                if ((p.purchaseLimit ?? 1) > 1 && remaining > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    key: const Key('purchase-quantity'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: '减少数量',
                        onPressed: quantity > 1
                            ? () => setState(() => quantity--)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      Text('$quantity 件'),
                      IconButton(
                        tooltip: '增加数量',
                        onPressed: quantity < remaining
                            ? () => setState(() => quantity++)
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  key: ValueKey('buy-${p.sku}'),
                  onPressed: widget.canPurchase
                      ? () => Navigator.pop(context, (
                          preview: false,
                          quantity: quantity,
                        ))
                      : null,
                  child: Text(
                    widget.canPurchase
                        ? '购买 · ${(p.price ?? 0) * quantity} ${furnitureCurrency(p.currency)}'
                        : widget.unavailable,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
