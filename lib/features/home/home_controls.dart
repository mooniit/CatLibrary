import 'package:flutter/material.dart';

import '../../room_layout.dart';
import '../identity/identity_repository.dart';

class RoomActionButton extends StatelessWidget {
  const RoomActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    tooltip: label,
    onPressed: onPressed,
    icon: Icon(icon, size: 23),
    style: IconButton.styleFrom(
      minimumSize: const Size(48, 48),
      backgroundColor: Theme.of(
        context,
      ).colorScheme.surface.withValues(alpha: 0.9),
      foregroundColor: Theme.of(context).colorScheme.primary,
    ),
  );
}

class HomeWallet extends StatelessWidget {
  const HomeWallet({super.key, required this.wallet, required this.onTap});
  final IdentityWallet? wallet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final values = [
      ('喵喵币', Icons.pets_outlined, wallet?.miaoCoins),
      ('鹰镑', Icons.payments_outlined, wallet?.eaglePounds),
      ('宝石', Icons.diamond_outlined, wallet?.gems),
    ];
    return Material(
      key: const Key('wallet-balance'),
      color: scheme.surface.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            children: [
              for (final value in values)
                Expanded(
                  child: Semantics(
                    label:
                        '${value.$1} ${value.$3 ?? '未连接'}${(value.$3 ?? 0) < 0 ? '，欠款' : ''}',
                    excludeSemantics: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          children: [
                            Icon(value.$2, size: 17, color: scheme.primary),
                            const SizedBox(width: 5),
                            Text(
                              value.$1,
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              value.$3?.toString() ?? '—',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: (value.$3 ?? 0) < 0
                                    ? scheme.error
                                    : scheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class FurnitureControls extends StatelessWidget {
  const FurnitureControls({
    super.key,
    required this.layout,
    required this.selected,
    required this.onSelect,
    required this.onMove,
    required this.onSave,
    required this.onCancel,
  });
  final RoomLayout layout;
  final String selected;
  final ValueChanged<String> onSelect;
  final ValueChanged<Offset> onMove;
  final VoidCallback onSave, onCancel;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
    borderRadius: BorderRadius.circular(20),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('选中家具后拖动，双指可缩放场景', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final item in const {'bookshelf': '书柜', 'bed': '猫窝'}.entries)
                ChoiceChip(
                  label: Text(item.value),
                  selected: selected == item.key,
                  onSelected: (_) => onSelect(item.key),
                ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final d in const [
                Offset(-1, 0),
                Offset(1, 0),
                Offset(0, -1),
                Offset(0, 1),
              ])
                IconButton(
                  tooltip: '移动 ${d.dx.toInt()},${d.dy.toInt()}',
                  onPressed: () => onMove(d),
                  icon: Icon(
                    d.dx < 0
                        ? Icons.arrow_back
                        : d.dx > 0
                        ? Icons.arrow_forward
                        : d.dy < 0
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                  ),
                ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(onPressed: onCancel, child: const Text('取消')),
              const SizedBox(width: 12),
              FilledButton(onPressed: onSave, child: const Text('保存预览')),
            ],
          ),
        ],
      ),
    ),
  );
}
