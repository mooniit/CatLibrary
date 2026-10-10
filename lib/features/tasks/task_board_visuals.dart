import 'package:flutter/material.dart';
import 'task_session.dart';

class TaskBoardHeading extends StatelessWidget {
  const TaskBoardHeading({super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '今日书签',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${now.month}月${now.day}日 · 周${weekdays[now.weekday - 1]}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          ExcludeSemantics(
            child: Image.asset(
              'assets/images/cats/calico-sitting-v1.png',
              width: 76,
              height: 98,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }
}

/// Long paper slips and a shared spine, rather than a stack of raised cards.
class TaskActivityCard extends StatelessWidget {
  const TaskActivityCard({
    super.key,
    required this.activity,
    required this.issued,
    required this.rewardCaption,
    this.onStart,
  });
  final TaskActivity activity;
  final int? issued;
  final String rewardCaption;
  final VoidCallback? onStart;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final language = activity == TaskActivity.language;
    final dark = scheme.brightness == Brightness.dark;
    final paper = language
        ? scheme.surfaceContainerLow
        : (dark ? const Color(0xff252c33) : const Color(0xfff3f3ef));
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: CustomPaint(
        painter: _BookmarkPainter(paper, scheme.primary.withValues(alpha: .45)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    language
                        ? Icons.translate_rounded
                        : Icons.directions_run_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const Spacer(),
                  Icon(
                    Icons.bookmark_outline_rounded,
                    size: 18,
                    color: scheme.primary.withValues(alpha: .6),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activity.label,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w500,
                                letterSpacing: 1,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          rewardCaption,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    tooltip: '开始${activity.label}',
                    onPressed: onStart,
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(54),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 28),
                  ),
                ],
              ),
              if (issued != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (var i = 0; i < 12; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Container(
                            height: 3,
                            color: i < issued!
                                ? scheme.primary
                                : scheme.primary.withValues(alpha: .12),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BookmarkPainter extends CustomPainter {
  _BookmarkPainter(this.paper, this.spine);
  final Color paper, spine;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - 9)
      ..lineTo(size.width - 18, size.height - 16)
      ..lineTo(size.width - 36, size.height - 9)
      ..lineTo(0, size.height - 9)
      ..close();
    canvas.drawPath(path, Paint()..color = paper);
    canvas.drawLine(
      const Offset(0, 0),
      Offset(0, size.height - 9),
      Paint()
        ..color = spine
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_BookmarkPainter old) =>
      old.paper != paper || old.spine != spine;
}

class TaskSectionTitle extends StatelessWidget {
  const TaskSectionTitle(
    this.title, {
    super.key,
    required this.icon,
    this.trailing,
  });
  final String title;
  final IconData icon;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 8),
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      ?trailing,
    ],
  );
}
