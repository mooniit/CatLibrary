import 'package:flutter/material.dart';
import 'layout_draft.dart';

const furnitureCategories = {
  'all': 'All',
  'furniture': '家具',
  'cats': '猫用',
  'decoration': '装饰',
  'windows': '窗景',
  'renovation': '装修',
};

const furnitureCategoryIcons = {
  'furniture': Icons.chair_outlined,
  'cats': Icons.pets_outlined,
  'decoration': Icons.image_outlined,
  'windows': Icons.window_outlined,
  'renovation': Icons.wallpaper_outlined,
};

String furnitureCategory(String kind) => switch (kind) {
  'bookshelf' || 'desk' || 'chair' => 'furniture',
  'tree' || 'bed' => 'cats',
  'rug' || 'frame' => 'decoration',
  'window' => 'windows',
  'wall' || 'floor' => 'renovation',
  _ => throw ArgumentError.value(kind, 'kind', 'Unregistered furniture kind'),
};

bool matchesFurnitureCategory(String category, String kind) =>
    category == 'all' || furnitureCategory(kind) == category;

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
                                : Icon(
                                    furnitureCategoryIcons[e.key],
                                    size: 22,
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
          final count = '$own/${p.purchaseLimit ?? 1}';
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
                        Expanded(
                          child: Image.asset(
                            '${p.assetRoot}${p.sprite}.png',
                            fit: BoxFit.contain,
                          ),
                        ),
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
                SizedBox(
                  height: 180,
                  child: Image.asset(
                    '${p.assetRoot}${p.sprite}.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 12),
                Text('已拥有 ${widget.owned}/${p.purchaseLimit ?? 1}'),
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
