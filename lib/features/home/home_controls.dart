import 'package:flutter/material.dart';

import '../identity/identity_repository.dart';
import '../../core/sync/cloud_client.dart';
import '../../core/sync/cloud_connection.dart';

class HomeConnectionStatus extends StatelessWidget {
  const HomeConnectionStatus({
    super.key,
    required this.cached,
    required this.onTap,
  });
  final bool cached;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<CloudStatus>(
    valueListenable: CloudClient.connection,
    builder: (context, status, _) {
      final scheme = Theme.of(context).colorScheme;
      final connected = status.phase == CloudPhase.online;
      return Material(
        color: scheme.surface.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  connected
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                  size: 16,
                  color: scheme.primary,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    connected && cached ? '已连接，余额待核对' : status.label,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

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
  const HomeWallet({super.key, required this.wallet, this.onExchange});
  final IdentityWallet? wallet;
  final VoidCallback? onExchange;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final values = [
      ('喵喵币', Icons.pets_outlined, wallet?.miaoCoins),
      ('鹰镑', Icons.payments_outlined, wallet?.eaglePounds),
      ('宝石', Icons.diamond_outlined, wallet?.gems),
    ];
    return Row(
      key: const Key('wallet-balance'),
      children: [
        for (var i = 0; i < values.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              label:
                  '${values[i].$1} ${values[i].$3 ?? '未连接'}${(values[i].$3 ?? 0) < 0 ? '，欠款' : ''}',
              excludeSemantics: true,
              button: i == 0 && onExchange != null,
              onTap: i == 0 ? onExchange : null,
              child: Material(
                key: Key('wallet-card-$i'),
                color: scheme.surface.withValues(alpha: 0.96),
                elevation: 0,
                shadowColor: scheme.shadow.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
                child: InkWell(
                  onTap: i == 0 ? onExchange : null,
                  borderRadius: BorderRadius.circular(13),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(values[i].$2, size: 14, color: scheme.primary),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                values[i].$1,
                                maxLines: 1,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          alignment: Alignment.centerLeft,
                          fit: BoxFit.scaleDown,
                          child: Text(
                            values[i].$3?.toString() ?? '—',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: (values[i].$3 ?? 0) < 0
                                  ? scheme.error
                                  : scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class SkyBackground extends StatelessWidget {
  const SkyBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? const [Color(0xff1c344e), Color(0xff294763)]
                : const [Color(0xffdceffd), Color(0xffc7e6fa)],
          ),
        ),
        child: CustomPaint(
          painter: _CloudPainter(dark ? 0.13 : 0.55),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _CloudPainter extends CustomPainter {
  const _CloudPainter(this.opacity);
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    for (final center in [
      Offset(size.width * 0.08, size.height * 0.22),
      Offset(size.width * 0.78, size.height * 0.14),
      Offset(size.width * 0.98, size.height * 0.83),
    ]) {
      canvas.drawOval(
        Rect.fromCenter(center: center, width: 72, height: 22),
        paint,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: center.translate(-17, -8),
          width: 39,
          height: 29,
        ),
        paint,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: center.translate(12, -11),
          width: 48,
          height: 34,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CloudPainter oldDelegate) =>
      opacity != oldDelegate.opacity;
}

class HomeMenu extends StatefulWidget {
  const HomeMenu({
    super.key,
    required this.onCats,
    required this.onStore,
    this.onArrange,
    required this.onAlbum,
    required this.onSettings,
  });
  final VoidCallback onCats, onStore, onAlbum, onSettings;
  final VoidCallback? onArrange;

  @override
  State<HomeMenu> createState() => _HomeMenuState();
}

class _HomeMenuState extends State<HomeMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );
  bool open = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void toggle() {
    setState(() => open = !open);
    if (open) {
      controller.forward();
    } else {
      controller.reverse();
    }
  }

  void select(VoidCallback action) {
    setState(() => open = false);
    controller.reverse();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = [
      ('猫咪管理', Icons.pets_outlined, widget.onCats),
      ('商店', Icons.storefront_outlined, widget.onStore),
      if (widget.onArrange != null)
        ('布置', Icons.edit_outlined, widget.onArrange!),
      ('相册', Icons.photo_library_outlined, widget.onAlbum),
      ('设置', Icons.settings_outlined, widget.onSettings),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton.filledTonal(
          key: const Key('home-menu-toggle'),
          tooltip: open ? '关闭功能菜单' : '打开功能菜单',
          onPressed: toggle,
          icon: AnimatedIcon(
            icon: AnimatedIcons.menu_close,
            progress: controller,
          ),
          style: IconButton.styleFrom(
            minimumSize: const Size(48, 48),
            backgroundColor: scheme.surface.withValues(alpha: 0.95),
            foregroundColor: scheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < entries.length; i++) ...[
          IgnorePointer(
            ignoring: !open,
            child: SlideTransition(
              position: Tween(begin: const Offset(1.2, 0), end: Offset.zero)
                  .animate(
                    CurvedAnimation(
                      parent: controller,
                      curve: Interval(
                        i * 0.1,
                        0.58 + i * 0.1,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                  ),
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: controller,
                  curve: Interval(i * 0.1, 0.58 + i * 0.1),
                ),
                child: Material(
                  key: Key('home-menu-item-$i'),
                  color: scheme.surface.withValues(alpha: 0.96),
                  elevation: 3,
                  shadowColor: scheme.shadow.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => select(entries[i].$3),
                    child: SizedBox(
                      width: 132,
                      height: 46,
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Icon(entries[i].$2, size: 21, color: scheme.primary),
                          const SizedBox(width: 10),
                          Text(entries[i].$1),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (i < entries.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}
