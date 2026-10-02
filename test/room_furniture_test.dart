import 'dart:async';

import 'package:cat_library_demo/features/room/room_furniture.dart';
import 'package:cat_library_demo/features/room/furniture_store.dart';
import 'package:cat_library_demo/features/home/home_page.dart';
import 'package:cat_library_demo/room_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'five fixed slots retain independent styles and visibility after reload',
    () async {
      expect(
        RoomLayout.defaults.keys,
        unorderedEquals(['window', 'chair', 'bookshelf', 'bed', 'desk']),
      );
      var room = const RoomFurnishings(wall: WallStyle.blue);
      for (final kind in RoomLayout.defaults.keys) {
        room = room
            .withStyle(kind, FurnitureStyle.sage)
            .withVisibility(kind, false);
      }
      await room.save('owner-a');
      final restored = await RoomFurnishings.load('owner-a');
      expect(restored.wall, WallStyle.blue);
      for (final kind in RoomLayout.defaults.keys) {
        expect(restored.styleFor(kind), FurnitureStyle.sage);
        expect(restored.isVisible(kind), isFalse);
      }
      final changed = restored.withStyle('desk', FurnitureStyle.cream);
      expect(changed.isVisible('desk'), isTrue);
      expect(changed.isVisible('chair'), isFalse);
      expect(changed.styleFor('chair'), FurnitureStyle.sage);
      expect(changed.wall, WallStyle.blue);
      expect((await RoomFurnishings.load('owner-b')).isVisible('desk'), isTrue);
      final preview = await RoomFurnishings.load(null);
      expect(preview.wall, WallStyle.sage);
      expect(preview.styleFor('desk'), FurnitureStyle.sage);
      expect(RoomLayout.defaults['bookshelf'], const GridPoint(0.08, 3.2));
      expect(RoomLayout.defaults['bed'], const GridPoint(9.7, 2.1));
    },
  );

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
        final choice = find.byKey(Key('furniture-$kind-sage'));
        await tester.ensureVisible(choice);
        await tester.pump();
        await tester.tap(choice);
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          key.currentState!.scene.furnishings.styleFor(kind),
          FurnitureStyle.sage,
        );
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
        FurnitureStyle.sage,
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
        expect(room.styleFor('desk'), FurnitureStyle.sage);
        expect(room.wall, WallStyle.blue);
        final restored = room
            .withArtwork(artwork)
            .withWall(WallStyle.blue)
            .withStyle('chair', FurnitureStyle.sage)
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
      final chair = find.byKey(const Key('furniture-chair-cream'));
      await tester.ensureVisible(chair);
      await tester.tap(chair);
      await tester.pump(const Duration(milliseconds: 100));
      final saved = await RoomFurnishings.load(null);
      expect(saved.styleFor('window'), FurnitureStyle.cream);
      expect(saved.styleFor('chair'), FurnitureStyle.cream);
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
      expect(home.scene.furnishings.styleFor('window'), FurnitureStyle.sage);
      expect(
        find.descendant(
          of: find.byKey(const Key('furniture-window-sage')),
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
                initial: const RoomFurnishings(),
                onChanged: (_) async {
                  if (fail) throw StateError('disk full');
                },
              ),
            ),
          ),
        ),
      );
      final choice = find.byKey(const Key('furniture-window-sage'));
      await tester.tap(choice);
      await tester.pump();
      expect(find.text('家具未保存，请重试'), findsOneWidget);
      expect(
        find.descendant(of: choice, matching: find.text('选用窗户')),
        findsOneWidget,
      );
      fail = false;
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
    : super(
        styles: {
          for (final kind in furnitureNames.keys)
            kind: kind == 'window' ? FurnitureStyle.cream : FurnitureStyle.sage,
        },
      );
  final Completer<void> gate;

  @override
  Future<void> save(String? ownerId) async {
    await gate.future;
    await super.save(ownerId);
  }
}

class _FailedCachedFurnishings extends RoomFurnishings {
  const _FailedCachedFurnishings()
    : super(styles: const {'window': FurnitureStyle.cream});

  @override
  Future<void> save(String? ownerId) async {
    // Simulate legacy preferences caching a value before native writing fails.
    await super.save(ownerId);
    throw StateError('native write failed after cache update');
  }
}
