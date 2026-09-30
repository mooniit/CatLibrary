import 'dart:ui' as ui;

import 'package:flame/flame.dart';
import 'package:flutter/material.dart';

import 'room_furniture.dart';

class FurnitureStore extends StatefulWidget {
  const FurnitureStore({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final RoomFurnishings initial;
  final Future<void> Function(RoomFurnishings) onChanged;

  @override
  State<FurnitureStore> createState() => _FurnitureStoreState();
}

class _FurnitureStoreState extends State<FurnitureStore> {
  late RoomFurnishings room = widget.initial;
  bool saving = false;
  String? error;

  Future<void> change(RoomFurnishings next) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onChanged(next);
      if (mounted) setState(() => room = next);
    } catch (_) {
      if (mounted) setState(() => error = '家具未保存，请重试');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('给小屋添一点喜欢', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '两组风格 · 五种家具\n固定位置，自由混搭；选择自动保存到本机。',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text('墙面', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final wall in WallStyle.values)
                ChoiceChip(
                  key: Key('wall-${wall.name}'),
                  label: Text(wall.label),
                  selected: room.wall == wall,
                  onSelected: saving
                      ? null
                      : (_) => change(room.withWall(wall)),
                ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error!, style: TextStyle(color: scheme.error)),
            ),
          for (final kind in furnitureNames.keys) ...[
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              key: Key('furniture-visible-$kind'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                furnitureNames[kind]!,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(
                '${furnitureLocations[kind]}${room.isVisible(kind) ? '' : ' · 已隐藏'}',
              ),
              value: room.isVisible(kind),
              onChanged: saving
                  ? null
                  : (visible) => change(room.withVisibility(kind, visible)),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final style in FurnitureStyle.values) ...[
                  if (style.index > 0) const SizedBox(width: 12),
                  Expanded(child: _choice(kind, style)),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _choice(String kind, FurnitureStyle style) {
    final selected = room.styleFor(kind) == style;
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      key: Key('furniture-$kind-${style.name}'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(12),
        backgroundColor: selected
            ? scheme.primary.withValues(alpha: 0.08)
            : scheme.surfaceContainerLow,
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: saving ? null : () => change(room.withStyle(kind, style)),
      child: Column(
        children: [
          ExcludeSemantics(
            child: SizedBox(
              height: 124,
              width: double.infinity,
              child: FutureBuilder<ui.Image>(
                future: Flame.images.load(style.asset),
                builder: (context, snapshot) => snapshot.hasData
                    ? CustomPaint(
                        painter: _FurniturePainter(
                          snapshot.data!,
                          furnitureSources[style]![kind]!,
                          furnitureGeometry[style]![kind]!,
                        ),
                      )
                    : Center(
                        child: snapshot.hasError
                            ? const Icon(Icons.broken_image_outlined)
                            : const CircularProgressIndicator(strokeWidth: 2),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            style.label,
            semanticsLabel: '${style.label}${furnitureNames[kind]}',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            selected
                ? (room.isVisible(kind) ? '✓ 使用中' : '已选 · 点击显示')
                : '选用${furnitureNames[kind]}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _FurniturePainter extends CustomPainter {
  const _FurniturePainter(this.image, this.source, this.geometry);
  final ui.Image image;
  final Rect source;
  final FurnitureGeometry geometry;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = geometry.bounds(source);
    final fitted = applyBoxFit(BoxFit.contain, bounds.size, size).destination;
    final scale = fitted.width / bounds.width;
    final target = Alignment.center.inscribe(fitted, Offset.zero & size);
    geometry.draw(
      canvas,
      image,
      source,
      scale,
      target.topLeft - bounds.topLeft * scale,
    );
  }

  @override
  bool shouldRepaint(_FurniturePainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.source != source ||
      oldDelegate.geometry != geometry;
}
