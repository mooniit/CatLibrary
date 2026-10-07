import 'package:flutter/material.dart';
import '../room/room_scene.dart';

/// Touch controls surround the sprite registered in the existing room viewport.
class ShopPreviewOverlay extends StatelessWidget {
  const ShopPreviewOverlay({
    super.key,
    required this.scene,
    required this.onRotate,
    required this.onCancel,
  });
  final RoomScene scene;
  final VoidCallback onRotate, onCancel;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: scene.previewChanges,
    builder: (_, _, _) => LayoutBuilder(
      builder: (context, box) {
        final bounds = scene.ghostBounds;
        if (bounds == null) return const SizedBox.shrink();
        Widget handle(
          String label,
          IconData icon,
          double left,
          double top,
          Alignment alignment,
          VoidCallback action,
        ) => Positioned(
          left: left.clamp(4, box.maxWidth - 48),
          // The home menu occupies the first 52 pixels of this same viewport.
          top: top.clamp(56, (box.maxHeight - 48).clamp(56, double.infinity)),
          child: IconButton(
            tooltip: label,
            onPressed: action,
            icon: SizedBox(
              width: 48,
              height: 48,
              child: Align(
                alignment: alignment,
                child: Container(
                  key: ValueKey('preview-glyph-$label'),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.96),
                  ),
                  child: Icon(icon, size: 12),
                ),
              ),
            ),
            style: IconButton.styleFrom(
              fixedSize: const Size(48, 48),
              padding: EdgeInsets.zero,
              backgroundColor: Colors.transparent,
              foregroundColor: Theme.of(context).colorScheme.primary,
            ),
          ),
        );
        return Stack(
          children: [
            if (scene.ghostProduct!.placement == 'ground')
              handle(
                '切换朝向',
                Icons.rotate_90_degrees_ccw_outlined,
                bounds.left - 40,
                bounds.bottom - 8,
                Alignment.topRight,
                onRotate,
              ),
            handle(
              '结束预览',
              Icons.close_rounded,
              bounds.right - 8,
              bounds.top - 40,
              Alignment.bottomLeft,
              onCancel,
            ),
          ],
        );
      },
    ),
  );
}
