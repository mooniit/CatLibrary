import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../room_layout.dart';
import '../room/room_scene.dart';
import '../identity/adoption_sheet.dart';
import '../identity/identity_repository.dart';
import '../family/family_page.dart';
import '../../core/sync/cloud_client.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onStudy, this.wallet});
  final IdentityWallet? wallet;
  final VoidCallback onStudy;
  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  final layout = RoomLayout();
  late final scene = RoomScene(layout);
  String selected = 'chair';
  String? message;
  final cats = <String, String>{};
  Future<bool> canLeave() async {
    if (!layout.editing) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('离开布置？'),
        content: const Text('此原型的未保存草稿将被放弃。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('继续布置'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    if (discard == true) setState(layout.cancel);
    return discard == true;
  }

  void info(String title, String text) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(c).textTheme.headlineSmall),
            const SizedBox(height: 16),
            Text(text),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !layout.editing,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) canLeave();
    },
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '我们的书房',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton(
              tooltip: '设置',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => const CloudProbePanel(),
              ),
            ),
          ],
        ),
        if (widget.wallet case final wallet?) ...[
          Text(
            '喵喵币 ${wallet.miaoCoins} · 鹰镑 ${wallet.eaglePounds} · 宝石 ${wallet.gems}',
            key: const Key('wallet-balance'),
          ),
          const Text('个人钱包 · 已连接'),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FamilyPage(ownerId: wallet.ownerId),
              ),
            ),
            icon: const Icon(Icons.people_outline),
            label: const Text('家庭与邀请'),
          ),
        ] else
          const Text('钱包尚未连接 · 无真实资产'),
        const Text('场景为结构占位，风格暂不讨论'),
        const SizedBox(height: 12),
        AspectRatio(
          aspectRatio: 1.45,
          child: GestureDetector(
            onPanUpdate: layout.editing
                ? (event) => setState(() {
                    final old = layout.draft[selected]!;
                    // Accumulate small pointer deltas before snapping at the model boundary.
                    dragOffset += event.delta;
                    final delta = RoomLayout.unproject(
                      dragOffset * (400 / scene.size.x),
                    );
                    if (delta.x.abs() >= 0.6 || delta.y.abs() >= 0.6) {
                      layout.move(
                        selected,
                        GridPoint(old.x + delta.x, old.y + delta.y),
                      );
                      dragOffset = Offset.zero;
                    }
                  })
                : null,
            onPanEnd: (_) => dragOffset = Offset.zero,
            child: Semantics(
              label: '房间线框，桌椅和两只猫的位置占位',
              child: GameWidget(game: scene),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (message != null) Text(message!, key: const Key('layout-message')),
        if (layout.editing) ...[
          const Text('本机交互样例：选中物件后拖动，或用箭头移动。'),
          Wrap(
            spacing: 8,
            children: [
              for (final id in ['chair', 'table'])
                ChoiceChip(
                  label: Text(id == 'chair' ? '椅子' : '桌子'),
                  selected: selected == id,
                  onSelected: (_) => setState(() => selected = id),
                ),
            ],
          ),
          Wrap(
            children: [
              for (final d in [
                const Offset(-1, 0),
                const Offset(1, 0),
                const Offset(0, -1),
                const Offset(0, 1),
              ])
                IconButton(
                  tooltip: '移动 ${d.dx.toInt()},${d.dy.toInt()}',
                  onPressed: () => setState(() {
                    final p = layout.draft[selected]!;
                    layout.move(selected, GridPoint(p.x + d.dx, p.y + d.dy));
                  }),
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
              FilledButton(
                onPressed: () => setState(() {
                  layout.commit();
                  message = '已保留本次预览布局（仅当前运行，无云端保存）';
                }),
                child: const Text('保存预览'),
              ),
              TextButton(
                onPressed: () => setState(layout.cancel),
                child: const Text('取消'),
              ),
            ],
          ),
        ] else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => setState(layout.beginEditing),
                icon: const Icon(Icons.open_with),
                label: const Text('布置猫窝'),
              ),
              OutlinedButton.icon(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => AdoptionSheet(
                    cats: cats,
                    onAdopted: () => setState(() {}),
                  ),
                ),
                icon: const Icon(Icons.pets),
                label: const Text('猫咪管理'),
              ),
              OutlinedButton(
                onPressed: widget.onStudy,
                child: const Text('去自习'),
              ),
            ],
          ),
        const Divider(height: 32),
        ListTile(
          leading: const Icon(Icons.storefront_outlined),
          title: const Text('商店'),
          subtitle: const Text('固定目录 · 商品与价格待定'),
          onTap: () => info('商店', '这里将展示可购买家具。商品、币种、价格尚未确定，当前不能购买。'),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('相册'),
          subtitle: const Text('一起收藏猫咪的旅行回忆'),
          onTap: () => info('相册', '还没有旅行照片。此处是空状态原型，不生成旅行记录。'),
        ),
        if (cats.isNotEmpty) Text('本次试领养：${cats.values.join('、')}（内存样例）'),
      ],
    ),
  );
  Offset dragOffset = Offset.zero;
}
