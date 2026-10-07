import 'package:flutter/material.dart';
import 'travel_repository.dart';

Future<void> showTravelReturn(
  BuildContext context,
  Map<String, dynamic> trip,
  TravelRepository repository,
  Future<void> Function() refresh,
) async {
  final acknowledged = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.flight_land_outlined,
              size: 40,
              color: Theme.of(c).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '${trip['cat_name']}从${trip['destination_label']}回来了',
              style: Theme.of(c).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              trip['first_visit'] == true
                  ? '带回了旅行记录与一件纪念品。去相册查看，或回小屋布置。'
                  : '六个地点已集齐，本次没有新增收藏。',
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('收好回忆'),
            ),
          ],
        ),
      ),
    ),
  );
  if (acknowledged == true) {
    try {
      await repository.call('ack_travel_return', {'target_trip': trip['id']});
      await refresh();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('返程已完成，提示暂未标记为已读，请重连核对。')));
      }
    }
  }
}
