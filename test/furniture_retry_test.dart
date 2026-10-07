import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/shop/shop_repository.dart';
import 'package:cat_library_demo/features/room/layout_draft.dart';

void main() {
  test(
    'offline cache is owner scoped and cleared from current family after leaving',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      String? family = 'F';
      final repo = ShopRepository(
        db,
        'A',
        rpc: (_, _) async => {
          'family_id': family,
          'products': <dynamic>[],
          'inventory': <dynamic>[],
          'layout': const RoomLayout([]).toJson(),
          'version': 8,
        },
      );
      await repo.load();
      expect((await repo.cached())!.version, 8);
      expect(await ShopRepository(db, 'B').cached(), isNull);
      await repo.storeDraft('F', LayoutDraft(const RoomLayout([]), 7));
      family = null;
      await repo.load();
      expect(await repo.cached(), isNull);
      expect((await repo.draft('F'))!.baseVersion, 7);
    },
  );
  test(
    'purchase reply loss is persisted; restart queries original receipt without spending again',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var charged = 0;
      Map<String, dynamic>? receipt;
      Future<Map<String, dynamic>> rpc(
        String method,
        Map<String, dynamic> p,
      ) async {
        if (method == 'furniture_request') {
          return receipt ?? {'status': 'not_found'};
        }
        charged++;
        receipt = {
          'status': 'purchased',
          'request_id': p['request_id'],
          'family_id': 'F',
        };
        throw TimeoutException('lost receipt');
      }

      final repo = ShopRepository(db, 'A', rpc: rpc);
      await expectLater(
        repo.purchase('F', 'lunar-chair'),
        throwsA(isA<TimeoutException>()),
      );
      expect(await repo.pending('F', 'purchase'), isNotNull);
      expect((await repo.pending('F', 'purchase'))!['target_family'], 'F');
      final reopened = ShopRepository(db, 'A', rpc: rpc);
      expect(
        (await reopened.reconcile('F', 'purchase'))!['status'],
        'purchased',
      );
      expect(charged, 1);
      expect(await reopened.pending('F', 'purchase'), isNull);
      expect(
        await ShopRepository(
          db,
          'B',
          rpc: rpc,
        ).pending('F', 'purchase_receipt'),
        isNull,
      );
      expect(await reopened.pending('OtherFamily', 'purchase_receipt'), isNull);
    },
  );
  test(
    'batch purchase persists quantity and forbids changing a pending batch',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = ShopRepository(
        db,
        'A',
        rpc: (method, p) async {
          if (method == 'furniture_request') return {'status': 'not_found'};
          throw TimeoutException('lost batch receipt');
        },
      );
      await expectLater(
        repo.purchase('F', 'chair', quantity: 2),
        throwsA(isA<TimeoutException>()),
      );
      expect((await repo.pending('F', 'purchase'))!['quantity'], 2);
      await expectLater(
        repo.purchase('F', 'chair', quantity: 1),
        throwsStateError,
      );
    },
  );
  test(
    'save reply loss followed by partner save preserves original receipt and draft',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      Map<String, dynamic>? receipt;
      var saves = 0;
      final repo = ShopRepository(
        db,
        'A',
        rpc: (method, p) async {
          if (method == 'furniture_request') {
            return receipt ?? {'status': 'not_found'};
          }
          saves++;
          receipt = {
            'status': 'saved',
            'request_id': p['request_id'],
            'family_id': 'F',
            'version': 13,
            'saved_layout': p['proposed'],
          };
          throw TimeoutException('lost');
        },
      );
      final draft = LayoutDraft(
        const RoomLayout([PlacedItem('c1', gx: 2)]),
        12,
      );
      await expectLater(
        repo.save('F', 'lease', draft),
        throwsA(isA<TimeoutException>()),
      );
      expect((await repo.draft('F'))!.baseVersion, 12);
      expect((await repo.reconcile('F', 'save'))!['version'], 13);
      expect(saves, 1);
      // A newer partner layout is not inferred to be this user's saved content.
      expect((await repo.draft('F'))!.layout.items.single.gx, 2);
    },
  );
  test(
    'rejected receipt clears pending operation but keeps editable draft',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = ShopRepository(
        db,
        'A',
        rpc: (m, p) async => m == 'furniture_request'
            ? {'status': 'not_found'}
            : {
                'status': 'rejected',
                'reason': 'version_conflict',
                'request_id': p['request_id'],
                'family_id': 'F',
              },
      );
      final result = await repo.save(
        'F',
        'lease',
        LayoutDraft(const RoomLayout([]), 1),
      );
      expect(result['reason'], 'version_conflict');
      expect(await repo.pending('F', 'save'), isNull);
      expect(await repo.draft('F'), isNotNull);
    },
  );
}
