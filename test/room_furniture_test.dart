import 'dart:async';

import 'package:cat_library_demo/features/room/room_furniture.dart';
import 'package:cat_library_demo/features/room/furniture_store.dart';
import 'package:cat_library_demo/features/home/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'seven fixed pieces retain independent choices and visibility after reload',
    () async {
      expect(
        furnitureNames.keys,
        unorderedEquals([
          'window',
          'chair',
          'bookshelf',
          'bed',
          'desk',
          'tree',
          'rug',
        ]),
      );
      var room = const RoomFurnishings(wall: WallStyle.lunar);
      for (final kind in furnitureNames.keys) {
        room = room
            .withStyle(kind, FurnitureStyle.lunar)
            .withVisibility(kind, false);
      }
      await room.save('owner-a');
      final restored = await RoomFurnishings.load('owner-a');
      expect(restored.wall, WallStyle.lunar);
      for (final kind in furnitureNames.keys) {
        expect(restored.styleFor(kind), FurnitureStyle.lunar);
        expect(restored.isVisible(kind), isFalse);
      }
      final changed = restored.withStyle('desk', FurnitureStyle.lunar);
      expect(changed.isVisible('desk'), isTrue);
      expect(changed.isVisible('chair'), isFalse);
      expect(changed.styleFor('chair'), FurnitureStyle.lunar);
      expect(changed.wall, WallStyle.lunar);
      expect((await RoomFurnishings.load('owner-b')).isVisible('desk'), isTrue);
      final preview = await RoomFurnishings.load(null);
      expect(preview.wall, WallStyle.lunar);
      expect(preview.styleFor('desk'), FurnitureStyle.lunar);
    },
  );

  test('old style records cannot restore the deleted room', () async {
    SharedPreferences.setMockInitialValues({
      'room_furniture_v1_old': <String>[
        'desk|sage|0',
        'wall|blue|1',
        'floor|oak|1',
        'tree|sage|1',
        'rug|invalid|1',
        'bed-canopy|covered|1',
        'facing-desk|z|1',
        'frame-template|round|1',
      ],
    });
    final old = await RoomFurnishings.load('old');
    expect(old.wall, WallStyle.lunar);
    expect(old.floor, FloorStyle.lunar);
    expect(old.styleFor('desk'), FurnitureStyle.lunar);
    expect(old.isVisible('desk'), isFalse);
    expect(old.isVisible('tree'), isTrue);
    expect(old.isVisible('rug'), isTrue);
    expect(old.facingFor('desk'), 'y');
    expect(old.frameTemplate, 'auto');
    await old.save('old');
    final saved = (await SharedPreferences.getInstance()).getStringList(
      'room_furniture_v1_old',
    )!;
    expect(
      saved.any(
        (s) =>
            s.contains('sage') ||
            s.contains('blue') ||
            s.contains('oak') ||
            s.contains('canopy'),
      ),
      isFalse,
    );
    final room = old
        .withSet(FurnitureStyle.lunar)
        .withArtwork(ArtworkStyle.pearl)
        .withVisibility('tree', false);
    await room.save('new');
    final restored = await RoomFurnishings.load('new');
    expect(restored.artwork, ArtworkStyle.pearl);
    expect(restored.isVisible('desk'), isTrue);
    expect(restored.isVisible('tree'), isFalse);
    expect(
      () => room.withStyle('unknown', FurnitureStyle.lunar),
      throwsArgumentError,
    );
  });

  testWidgets(
    'shop changes the home, hides each slot and restores choices after reopening',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey<HomePageState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomePage(key: key, onStudy: () {}),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      key.currentState!.openStore();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      for (final kind in furnitureNames.keys) {
        final style = FurnitureStyle.lunar;
        final choice = find.byKey(Key('furniture-$kind-${style.name}'));
        await tester.ensureVisible(choice);
        await tester.pump();
        await tester.tap(choice);
        await tester.pump(const Duration(milliseconds: 100));
        expect(key.currentState!.scene.furnishings.styleFor(kind), style);
        final toggle = find.byKey(Key('furniture-visible-$kind'));
        await tester.ensureVisible(toggle);
        await tester.pump();
        await tester.tap(toggle);
        await tester.pump(const Duration(milliseconds: 100));
        expect(key.currentState!.scene.furnishings.isVisible(kind), isFalse);
      }
      for (final artwork in ArtworkStyle.values) {
        final choice = find.byKey(Key('painting-${artwork.name}'));
        await tester.ensureVisible(choice);
        await tester.pump();
        await tester.tap(choice);
        await tester.pump(const Duration(milliseconds: 100));
        expect(key.currentState!.scene.furnishings.artwork, artwork);
      }
      final paintingToggle = find.byKey(const Key('painting-visible'));
      await tester.ensureVisible(paintingToggle);
      await tester.pump();
      await tester.tap(paintingToggle);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        key.currentState!.scene.furnishings.isVisible('painting'),
        isFalse,
      );
      await tester.tap(find.byTooltip('关闭商店'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
      final reopened = GlobalKey<HomePageState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomePage(key: reopened, onStudy: () {}),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(reopened.currentState!.scene.furnishings.hidden, {
        ...furnitureNames.keys,
        'painting',
      });
      expect(
        reopened.currentState!.scene.furnishings.artwork,
        ArtworkStyle.sunflowers,
      );
      expect(
        reopened.currentState!.scene.furnishings.styleFor('desk'),
        FurnitureStyle.lunar,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'artwork selection preserves other choices and loads legacy records',
    () async {
      SharedPreferences.setMockInitialValues({
        'room_furniture_v1_owner-a': <String>[
          'desk|sage|0',
          'wall|blue|1',
          'painting|invalid|0',
          'painting|mona|invalid',
        ],
      });
      var room = await RoomFurnishings.load('owner-a');
      expect(room.artwork, ArtworkStyle.starry);
      expect(room.isVisible('painting'), isTrue);
      for (final artwork in ArtworkStyle.values) {
        room = room.withArtwork(artwork).withVisibility('painting', false);
        await room.save('owner-a');
        room = await RoomFurnishings.load('owner-a');
        expect(room.artwork, artwork);
        expect(room.isVisible('painting'), isFalse);
        expect(room.isVisible('desk'), isFalse);
        expect(room.styleFor('desk'), FurnitureStyle.lunar);
        expect(room.wall, WallStyle.lunar);
        final restored = room
            .withArtwork(artwork)
            .withWall(WallStyle.lunar)
            .withStyle('chair', FurnitureStyle.lunar)
            .withVisibility('chair', false);
        expect(restored.artwork, artwork);
        expect(restored.isVisible('painting'), isTrue);
      }
    },
  );

  testWidgets(
    'reopening the store waits for a pending save and retains it on the next choice',
    (tester) async {
      final key = GlobalKey<HomePageState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomePage(key: key, onStudy: () {}),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final home = key.currentState!;
      unawaited(home.openStore());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final gate = Completer<void>();
      final pending = home.changeFurniture(_DelayedFurnishings(gate));
      await tester.tap(find.byTooltip('关闭商店'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byTooltip('关闭商店'), findsNothing);
      unawaited(home.openStore());
      await tester.pump();
      expect(find.byTooltip('关闭商店'), findsNothing);
      gate.complete();
      await pending;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final chair = find.byKey(const Key('furniture-chair-lunar'));
      await tester.ensureVisible(chair);
      await tester.tap(chair);
      await tester.pump(const Duration(milliseconds: 100));
      final saved = await RoomFurnishings.load(null);
      expect(saved.isVisible('window-left'), isFalse);
      expect(saved.facingFor('desk'), 'x');
      expect(saved.styleFor('chair'), FurnitureStyle.lunar);
      await tester.tap(find.byTooltip('关闭商店'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reopening after a failed cached save retains the confirmed scene',
    (tester) async {
      final key = GlobalKey<HomePageState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomePage(key: key, onStudy: () {}),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final home = key.currentState!;
      await expectLater(
        home.changeFurniture(const _FailedCachedFurnishings()),
        throwsStateError,
      );
      unawaited(home.openStore());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(home.scene.furnishings.isVisible('window'), isTrue);
      expect(
        find.descendant(
          of: find.byKey(const Key('furniture-window-lunar')),
          matching: find.text('✓ 使用中'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('关闭商店'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed save leaves the selected furniture unchanged and offers retry',
    (tester) async {
      var fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FurnitureStore(
                initial: const RoomFurnishings(hidden: {'window'}),
                onChanged: (_) async {
                  if (fail) throw StateError('disk full');
                },
              ),
            ),
          ),
        ),
      );
      final choice = find.byKey(const Key('furniture-window-lunar'));
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pump();
      expect(find.text('家具未保存，请重试'), findsOneWidget);
      expect(
        find.descendant(of: choice, matching: find.text('已选 · 点击显示')),
        findsOneWidget,
      );
      fail = false;
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pump();
      expect(find.text('家具未保存，请重试'), findsNothing);
      expect(
        find.descendant(of: choice, matching: find.text('✓ 使用中')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _DelayedFurnishings extends RoomFurnishings {
  _DelayedFurnishings(this.gate)
    : super(hidden: {'window-left'}, facings: {'desk': 'x'});
  final Completer<void> gate;

  @override
  Future<void> save(String? ownerId) async {
    await gate.future;
    await super.save(ownerId);
  }
}

class _FailedCachedFurnishings extends RoomFurnishings {
  const _FailedCachedFurnishings() : super(hidden: const {'window'});

  @override
  Future<void> save(String? ownerId) async {
    // Simulate legacy preferences caching a value before native writing fails.
    await super.save(ownerId);
    throw StateError('native write failed after cache update');
  }
}
