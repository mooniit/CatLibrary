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
            '四组风格 · 七类家具 · 五幅装饰画\n固定位置，自由混搭；选择自动保存到本机。',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final style in [
                FurnitureStyle.lunar,
                FurnitureStyle.bauhaus,
              ])
                OutlinedButton(
                  key: Key('room-set-${style.name}'),
                  onPressed: saving ? null : () => change(room.withSet(style)),
                  child: Text('布置${style.label}'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('墙面与地板'),
            subtitle: Text('${room.wall.label} · ${room.floor.label}'),
            children: [
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
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final floor in FloorStyle.values)
                    ChoiceChip(
                      key: Key('floor-${floor.name}'),
                      label: Text(floor.label),
                      selected: room.floor == floor,
                      onSelected: saving
                          ? null
                          : (_) => change(room.withFloor(floor)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
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
                '${room.usesLunarRoom ? lunarFurnitureLocations[kind] : furnitureLocations[kind]}${room.isVisible(kind) ? '' : ' · 已隐藏'}',
              ),
              value: room.isVisible(kind),
              onChanged: saving
                  ? null
                  : (visible) => change(room.withVisibility(kind, visible)),
            ),
            for (var i = 0; i < stylesFor(kind).length; i += 2) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _choice(kind, stylesFor(kind)[i])),
                  const SizedBox(width: 12),
                  Expanded(
                    child: i + 1 < stylesFor(kind).length
                        ? _choice(kind, stylesFor(kind)[i + 1])
                        : const SizedBox(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (room.usesLunarRoom && kind == 'window')
              for (final side in ['left', 'right'])
                SwitchListTile.adaptive(
                  key: Key('window-$side-visible'),
                  title: Text(side == 'left' ? '左墙窗户' : '右墙窗户'),
                  value: room.isVisible('window-$side'),
                  onChanged: saving
                      ? null
                      : (visible) => change(
                          room.withVisibility('window-$side', visible),
                        ),
                ),
            if (room.usesLunarRoom &&
                room.styleFor(kind) == FurnitureStyle.lunar &&
                ['bookshelf', 'desk', 'chair', 'tree', 'bed'].contains(kind))
              Wrap(
                spacing: 8,
                children: [
                  for (final facing in ['x', 'y'])
                    ChoiceChip(
                      key: Key('lunar-facing-$kind-$facing'),
                      label: Text('正面 +${facing.toUpperCase()}'),
                      selected: room.facingFor(kind) == facing,
                      onSelected: saving
                          ? null
                          : (_) => change(room.withFacing(kind, facing)),
                    ),
                ],
              ),
            if (kind == 'bed' && room.styleFor(kind) == FurnitureStyle.lunar)
              SwitchListTile.adaptive(
                key: const Key('bed-canopy'),
                contentPadding: EdgeInsets.zero,
                title: const Text('月牙罩'),
                subtitle: const Text('保留原款，也可切换开放猫窝'),
                value: room.bedCovered,
                onChanged: saving
                    ? null
                    : (value) => change(room.withBedCovered(value)),
              ),
          ],
          const SizedBox(height: 16),
          if (room.usesLunarRoom) ...[
            Text('月轨画框', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in const {
                  'auto': '样稿搭配',
                  'landscape': '横版',
                  'portrait': '竖版',
                  'square': '正方形',
                }.entries)
                  ChoiceChip(
                    key: Key('lunar-frame-${entry.key}'),
                    label: Text(entry.value),
                    selected: room.frameTemplate == entry.key,
                    onSelected: saving
                        ? null
                        : (_) => change(room.withFrameTemplate(entry.key)),
                  ),
              ],
            ),
          ],
          SwitchListTile.adaptive(
            key: const Key('painting-visible'),
            contentPadding: EdgeInsets.zero,
            title: Text('装饰画', style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text(
              '${room.usesLunarRoom ? '两堵墙 · 四个固定画位' : '左墙中间偏上'}${room.isVisible('painting') ? '' : ' · 已隐藏'}',
            ),
            value: room.isVisible('painting'),
            onChanged: saving
                ? null
                : (visible) => change(room.withVisibility('painting', visible)),
          ),
          for (var i = 0; i < ArtworkStyle.values.length; i += 2) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _artworkChoice(ArtworkStyle.values[i])),
                const SizedBox(width: 12),
                Expanded(
                  child: i + 1 < ArtworkStyle.values.length
                      ? _artworkChoice(ArtworkStyle.values[i + 1])
                      : const SizedBox(),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
              child:
                  style == FurnitureStyle.lunar &&
                      !(kind == 'bed' && room.bedCovered)
                  ? Image.asset(
                      'assets/images/room/lunar-v5/${kind == 'window'
                          ? 'window-left'
                          : kind == 'rug'
                          ? 'rug'
                          : '$kind-${room.facingFor(kind)}'}.png',
                      fit: BoxFit.contain,
                    )
                  : FutureBuilder<ui.Image>(
                      future: Flame.images.load(
                        furnitureAsset(kind, style, covered: room.bedCovered),
                      ),
                      builder: (context, snapshot) => snapshot.hasData
                          ? CustomPaint(
                              painter: _FurniturePainter(
                                snapshot.data!,
                                sourceFor(
                                  kind,
                                  style,
                                  covered: room.bedCovered,
                                ),
                                geometryFor(
                                  kind,
                                  style,
                                  covered: room.bedCovered,
                                ),
                              ),
                            )
                          : Center(
                              child: snapshot.hasError
                                  ? const Icon(Icons.broken_image_outlined)
                                  : const CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
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

  Widget _artworkChoice(ArtworkStyle style) {
    final selected = room.artwork == style;
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      key: Key('painting-${style.name}'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(10),
        backgroundColor: selected
            ? scheme.primary.withValues(alpha: 0.08)
            : scheme.surfaceContainerLow,
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: saving ? null : () => change(room.withArtwork(style)),
      child: Column(
        children: [
          ExcludeSemantics(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xff775335), width: 4),
              ),
              child: Image.asset(
                'assets/images/${style.asset}',
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(style.label, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
            selected
                ? (room.isVisible('painting') ? '✓ 使用中' : '已选 · 点击显示')
                : '选用画作',
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
