import 'package:flutter/material.dart';

import '../../core/sync/cloud_client.dart';
import '../family/family_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.onThemeChanged, this.ownerId});

  final Future<void> Function(ThemeMode)? onThemeChanged;
  final String? ownerId;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool saving = false;

  Future<void> choose(ThemeMode mode) async {
    if (saving || widget.onThemeChanged == null) return;
    final current = Theme.of(context).brightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light;
    if (mode == current) return;
    setState(() => saving = true);
    try {
      await widget.onThemeChanged!(mode);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('主题未保存，请重试')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = Theme.of(context).brightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text('外观', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('选择适合此刻阅读的界面', style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          _ThemeChoice(
            label: '白色简约',
            description: '明亮、清爽',
            mode: ThemeMode.light,
            selected: current == ThemeMode.light,
            onTap: saving || widget.onThemeChanged == null
                ? null
                : () => choose(ThemeMode.light),
          ),
          const SizedBox(height: 10),
          _ThemeChoice(
            label: '暗色夜晚',
            description: '低亮度、柔和雾蓝',
            mode: ThemeMode.dark,
            selected: current == ThemeMode.dark,
            onTap: saving || widget.onThemeChanged == null
                ? null
                : () => choose(ThemeMode.dark),
          ),
          const SizedBox(height: 32),
          Divider(color: scheme.outlineVariant),
          if (widget.ownerId != null)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: const Icon(Icons.people_outline),
              title: const Text('家庭与邀请'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FamilyPage(ownerId: widget.ownerId!),
                ),
              ),
            ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('连接验证'),
            subtitle: const Text('开发测试工具'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => const CloudProbePanel(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.label,
    required this.description,
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String description;
  final ThemeMode mode;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = mode == ThemeMode.dark;
    final previewSurface = dark ? const Color(0xff151a24) : Colors.white;
    final previewInk = dark ? const Color(0xfff1f3f7) : const Color(0xff242832);
    final previewAccent = dark
        ? const Color(0xff9cb2cd)
        : const Color(0xff7186a0);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label主题',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: selected
              ? scheme.primary.withValues(alpha: 0.08)
              : scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 46,
                    decoration: BoxDecoration(
                      color: previewSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(width: 21, height: 4, color: previewInk),
                          Container(width: 32, height: 9, color: previewAccent),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          description,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle, color: scheme.primary)
                  else
                    const SizedBox(width: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
