import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/album/album_page.dart';
import 'package:cat_library_demo/features/travel/travel_repository.dart';
import 'package:cat_library_demo/features/travel/travel_sheet.dart';

void main() {
  testWidgets(
    'delivered illustration keeps each cat collection and provenance distinct',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final calls = <String>[];
      final repo = TravelRepository(
        db,
        'A',
        rpc: (action, _) async {
          calls.add(action);
          return {
            'family_id': 'F',
            'photos': [
              for (final cat in ['C1', 'C2'])
                {
                  'id': 'visit-$cat',
                  'cat_id': cat,
                  'cat_name': cat,
                  'appearance': 'black_short',
                  'destination': 'palace',
                  'destination_label': '故宫',
                  'taken_at': '2026-10-07T16:00:00Z',
                  'arranger_label': cat == 'C1' ? '我' : '另一位成员',
                  'arranged_by': 'private-owner-$cat',
                  'souvenir_label': '故宫宫殿',
                },
            ],
          };
        },
      );
      await tester.pumpWidget(MaterialApp(home: AlbumPage(repository: repo)));
      await tester.pumpAndSettle();
      expect(find.text('2 条旅行回忆'), findsOneWidget);
      expect(find.text('旅行插画待收录'), findsNothing);
      expect(find.byType(Image), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('photo-visit-C2')));
      await tester.pumpAndSettle();
      expect(find.text('C2'), findsOneWidget);
      expect(find.text('安排人：另一位成员'), findsOneWidget);
      expect(find.textContaining('private-owner'), findsNothing);
      expect(calls, ['family_album']);
    },
  );
  testWidgets('only delivered appearance and destination pairs use art', (
    tester,
  ) async {
    for (final pair in [
      ('black_short', 'palace', 'calico-palace'),
      ('light_long', 'palace', 'longhair-palace'),
      ('black_short', 'louvre', 'calico-louvre'),
      ('light_long', 'louvre', 'longhair-louvre'),
      ('black_short', 'fuji', 'calico-fuji'),
      ('light_long', 'fuji', 'longhair-fuji'),
      ('black_short', 'pyramid', 'calico-pyramid'),
      ('light_long', 'pyramid', 'longhair-pyramid'),
      ('black_short', 'eiffel', 'calico-eiffel'),
      ('light_long', 'eiffel', 'longhair-eiffel'),
      ('black_short', 'liberty', 'calico-liberty'),
      ('light_long', 'liberty', 'longhair-liberty'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 280,
            height: 200,
            child: TravelRecordArt(
              photo: {
                'appearance': pair.$1,
                'destination': pair.$2,
                'cat_name': '测试猫',
                'destination_label': '测试地点',
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      final provider = tester.widget<Image>(find.byType(Image)).image;
      expect(provider, isA<ResizeImage>());
      final resized = provider as ResizeImage;
      expect(
        (resized.imageProvider as AssetImage).assetName,
        'assets/images/travel/${pair.$3}-v1.png',
      );
      expect(tester.takeException(), isNull);
    }
    for (final pair in [('light_long', 'unknown'), ('unknown', 'palace')]) {
      await tester.pumpWidget(
        MaterialApp(
          home: TravelRecordArt(
            photo: {
              'appearance': pair.$1,
              'destination': pair.$2,
              'cat_name': '测试猫',
              'destination_label': '测试地点',
            },
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.text('旅行插画待收录'), findsOneWidget);
    }
  });
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
