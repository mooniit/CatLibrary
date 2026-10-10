import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/notifications/feeding_notifications.dart';
import 'feeding_reminders.dart';

class FeedingReminderBanner extends StatefulWidget {
  const FeedingReminderBanner({
    super.key,
    required this.controller,
    required this.onOpen,
    this.visible = true,
  });
  final FeedingReminderController controller;
  final VoidCallback onOpen;
  final bool visible;
  @override
  State<FeedingReminderBanner> createState() => _FeedingReminderBannerState();
}

class _FeedingReminderBannerState extends State<FeedingReminderBanner> {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final reminder = controller.reminder;
      if (!widget.visible || reminder == null) return const SizedBox.shrink();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.visible &&
            identical(controller, widget.controller) &&
            (ModalRoute.of(context)?.isCurrent ?? true)) {
          unawaited(controller.present(reminder.day));
        }
      });
      final scheme = Theme.of(context).colorScheme;
      return Material(
        key: const Key('feeding-reminder-banner'),
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: widget.onOpen,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.pets_outlined,
                        color: scheme.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              controller.hasError ? '上次核对 · 待喂食' : '晚餐时间',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            Text(
                              reminder.names.join('、'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 20),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: '收起今日提醒',
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => unawaited(controller.dismiss(reminder.day)),
            ),
          ],
        ),
      );
    },
  );
}

class FeedingReminderSettings extends StatefulWidget {
  const FeedingReminderSettings({
    super.key,
    required this.ownerId,
    this.store,
    this.notifications,
  });
  final String ownerId;
  final ReminderStore? store;
  final FeedingNotifications? notifications;
  @override
  State<FeedingReminderSettings> createState() =>
      _FeedingReminderSettingsState();
}

class _FeedingReminderSettingsState extends State<FeedingReminderSettings> {
  late ReminderStore store;
  late FeedingNotifications notifications;
  bool? enabled;
  bool busy = false;
  String? message;
  int request = 0;

  @override
  void initState() {
    super.initState();
    configure();
  }

  @override
  void didUpdateWidget(FeedingReminderSettings old) {
    super.didUpdateWidget(old);
    if (old.ownerId != widget.ownerId ||
        old.store != widget.store ||
        old.notifications != widget.notifications) {
      configure();
    }
  }

  void configure() {
    store = widget.store ?? PreferencesReminderStore();
    notifications = widget.notifications ?? NativeFeedingNotifications();
    enabled = null;
    busy = false;
    message = null;
    unawaited(load());
  }

  Future<void> load() async {
    final attempt = ++request;
    try {
      final state = await store.load(widget.ownerId);
      if (mounted && attempt == request) {
        setState(() {
          enabled = state.enabled;
          message = null;
        });
      }
    } catch (_) {
      if (mounted && attempt == request) {
        setState(() => message = '提醒设置未读取，点击重试');
      }
    }
  }

  Future<void> toggle(bool value) async {
    if (busy || enabled == null) return;
    final attempt = ++request;
    final owner = widget.ownerId;
    final currentStore = store;
    final currentNotifications = notifications;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final allowed = !value || await currentNotifications.requestPermission();
      if (!mounted || attempt != request) return;
      if (!allowed) {
        setState(() => message = '系统通知未开启，应用内提醒仍然保留');
        return;
      }
      await currentStore.update(owner, enabled: value);
      if (!value) await currentNotifications.cancel(owner);
      if (mounted && attempt == request) setState(() => enabled = value);
    } catch (_) {
      if (mounted && attempt == request) {
        setState(() => message = '提醒设置未保存，请重试');
      }
    } finally {
      if (mounted && attempt == request) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(Icons.notifications_none, color: scheme.primary),
          title: const Text('晚餐提醒'),
          subtitle: Text(
            notifications.supported ? '21:00 · 应用打开时可发送系统通知' : '21:00 · 应用内提醒',
          ),
          trailing: Switch(
            key: const Key('feeding-notification-switch'),
            value: enabled ?? false,
            onChanged: busy || enabled == null || !notifications.supported
                ? null
                : toggle,
          ),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: enabled == null
                ? TextButton.icon(
                    onPressed: () => unawaited(load()),
                    icon: const Icon(Icons.refresh),
                    label: Text(message!),
                  )
                : Text(
                    message!,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
          ),
      ],
    );
  }
}
