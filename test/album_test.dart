import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/album/album_page.dart';
import 'package:cat_library_demo/features/travel/travel_repository.dart';
import 'package:cat_library_demo/features/travel/travel_sheet.dart';

void main() {
  testWidgets('shared album metadata visible and no fake photo used', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = TravelRepository(
      db,
      'A',
      rpc: (_, _) async => {
        'family_id': 'F',
        'photos': [
          {
            'id': 'P',
            'cat_name': '远行猫',
            'destination_label': '故宫',
            'taken_at': '2026-10-07T16:00:00Z',
            'arranger_label': '另一位成员',
            'arranged_by': 'B',
            'souvenir_label': '故宫宫殿',
          },
        ],
      },
    );
    await tester.pumpWidget(MaterialApp(home: AlbumPage(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('故宫'), findsOneWidget);
    expect(find.text('旅行插画待收录'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('photo-P')));
    await tester.pumpAndSettle();
    expect(find.text('安排人：另一位成员'), findsOneWidget);
    expect(find.text('2026 年 10 月 8 日'), findsOneWidget);
    expect(find.text('故宫宫殿'), findsOneWidget);
  });
  testWidgets(
    'offline travel disables new expense and retains reconcile control',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final raw = {
        'family_id': 'F',
        'server_time': '2026-10-07T00:00:00Z',
        'wallet': {
          'owner_id': 'A',
          'miao_coins': 30,
          'eagle_pounds': 0,
          'gems': 120,
        },
        'cats': [
          {'id': 'C', 'name': '远行猫', 'visited': 0, 'trip_id': null},
        ],
      };
      final cache = TravelRepository(db, 'A', rpc: (_, _) async => raw);
      await cache.load();
      final repo = TravelRepository(
        db,
        'A',
        rpc: (_, _) async => throw StateError('offline'),
      );
      await tester.pumpWidget(MaterialApp(home: TravelSheet(repository: repo)));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('travel-C')))
            .onPressed,
        isNull,
      );
      expect(find.byTooltip('核对旅行'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
