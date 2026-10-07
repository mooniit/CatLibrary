import 'dart:math';
import '../../core/storage/app_database.dart';
import '../../core/sync/cloud_client.dart';
import '../room/layout_draft.dart';

typedef FurnitureRpc =
    Future<Map<String, dynamic>> Function(String, Map<String, dynamic>);

String furnitureRequestId() {
  final random = Random.secure(),
      bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class FurnitureState {
  FurnitureState.fromJson(this.raw)
    : familyId = raw['family_id'],
      version = raw['version'] ?? 0,
      layout = RoomLayout.fromJson(raw['layout']),
      products = {
        for (final p in raw['products'] as List)
          p['sku'] as String: FurnitureProduct.fromJson(
            Map<String, dynamic>.from(p),
          ),
      },
      inventory = [
        for (final i in raw['inventory'] as List) InventoryInstance.fromJson(i),
      ];
  final Map<String, dynamic> raw;
  final String? familyId;
  final int version;
  final RoomLayout layout;
  final Map<String, FurnitureProduct> products;
  final List<InventoryInstance> inventory;
  bool get configured => raw['configured'] == true;
  bool get testScope => raw['test_scope'] == true;
  PlacementRules get rules => PlacementRules(
    products,
    inventory,
    categoryLimits: raw['category_limits'] == null
        ? const {'desk': 1, 'bed': 1, 'tree': 1}
        : Map<String, int>.from(raw['category_limits']),
    slots: raw['slots'] == null
        ? const {
            'window-left': 'window',
            'window-right': 'window',
            'art-left-back': 'art',
            'art-left-front': 'art',
            'art-right-back': 'art',
            'art-right-front': 'art',
            'rug': 'rug',
            'wall': 'wall',
            'floor': 'floor',
          }
        : Map<String, String>.from(raw['slots']),
  );
}

/// Requests are persisted before network I/O, and looked up before every retry.
class ShopRepository {
  ShopRepository(this.database, this.ownerId, {FurnitureRpc? rpc}) : _rpc = rpc;
  final AppDatabase database;
  final String ownerId;
  final FurnitureRpc? _rpc;
  bool _purchaseBusy = false, _saveBusy = false;
  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic> params,
  ) async {
    if (_rpc != null) return _rpc(method, params);
    final client = await CloudClient.connect();
    if (client.auth.currentUser?.id != ownerId) throw StateError('身份已改变');
    final result = Map<String, dynamic>.from(
      await client
              .rpc(method, params: params)
              .timeout(const Duration(seconds: 10))
          as Map,
    );
    if (client.auth.currentUser?.id != ownerId) throw StateError('身份已改变');
    return result;
  }

  Future<FurnitureState> load() async {
    final raw = await call('furniture_state', {});
    final state = FurnitureState.fromJson(raw);
    if (state.familyId != null) {
      await database.putFurnitureLocal(ownerId, state.familyId!, 'cache', raw);
      await database.putFurnitureLocal(ownerId, 'current', 'index', {
        'family_id': state.familyId,
      });
    } else {
      await database.removeFurnitureLocal(ownerId, 'current', 'index');
    }
    return state;
  }

  Future<FurnitureState?> cached() async {
    final index = await database.furnitureLocal(ownerId, 'current', 'index');
    if (index == null) return null;
    final raw = await database.furnitureLocal(
      ownerId,
      index['family_id'],
      'cache',
    );
    return raw == null ? null : FurnitureState.fromJson(raw);
  }

  Future<Map<String, dynamic>?> pending(String family, String kind) =>
      database.furnitureLocal(ownerId, family, kind);
  Future<Map<String, dynamic>> _resolve(
    String family,
    String kind,
    Map<String, dynamic> request,
    String method,
  ) async {
    var result = await call('furniture_request', {
      'target_request': request['request_id'],
    });
    if (result['status'] == 'not_found') result = await call(method, request);
    if (!['purchased', 'saved', 'rejected'].contains(result['status']) ||
        result['request_id'] != request['request_id'] ||
        (result['family_id'] != null && result['family_id'] != family)) {
      throw StateError('无法核对正式回执');
    }
    await database.transaction(() async {
      await database.putFurnitureLocal(
        ownerId,
        family,
        '${kind}_receipt',
        result,
      );
      await database.removeFurnitureLocal(ownerId, family, kind);
    });
    return result;
  }

  Future<Map<String, dynamic>> purchase(
    String family,
    String sku, {
    int quantity = 1,
  }) async {
    if (quantity < 1 || quantity > 64) throw ArgumentError.value(quantity);
    if (_purchaseBusy) throw StateError('正在核对购买');
    _purchaseBusy = true;
    try {
      var request = await pending(family, 'purchase');
      if (request != null &&
          (request['product_sku'] != sku ||
              (request['quantity'] ?? 1) != quantity)) {
        throw StateError('请先核对上次购买');
      }
      if (request == null) {
        request = {
          'request_id': furnitureRequestId(),
          'product_sku': sku,
          'target_family': family,
          if (quantity != 1) 'quantity': quantity,
        };
        await database.putFurnitureLocal(ownerId, family, 'purchase', request);
      }
      return await _resolve(family, 'purchase', request, 'purchase_furniture');
    } finally {
      _purchaseBusy = false;
    }
  }

  Future<Map<String, dynamic>?> reconcile(String family, String kind) async {
    final request = await pending(family, kind);
    if (request == null) return null;
    return _resolve(
      family,
      kind,
      request,
      kind == 'purchase' ? 'purchase_furniture' : 'save_room_layout',
    );
  }

  Future<Map<String, dynamic>> editor(String action, String token) =>
      call('room_editor', {'action': action, 'editor_token': token});
  Future<LayoutDraft?> draft(String family) async {
    final raw = await pending(family, 'draft');
    return raw == null ? null : LayoutDraft.fromJson(raw);
  }

  Future<void> storeDraft(String family, LayoutDraft draft) =>
      database.putFurnitureLocal(ownerId, family, 'draft', draft.toJson());
  Future<void> discardDraft(String family) async {
    if (await pending(family, 'save') != null) throw StateError('先核对待保存请求');
    await database.removeFurnitureLocal(ownerId, family, 'draft');
  }

  Future<Map<String, dynamic>> save(
    String family,
    String token,
    LayoutDraft draft,
  ) async {
    if (_saveBusy) throw StateError('正在核对保存');
    _saveBusy = true;
    try {
      if (draft.preview != null) throw StateError('请先确认或取消单品预览');
      await storeDraft(family, draft);
      var request = await pending(family, 'save');
      if (request == null) {
        request = {
          'request_id': furnitureRequestId(),
          'editor_token': token,
          'expected_version': draft.baseVersion,
          'proposed': draft.layout.toJson(),
        };
        await database.putFurnitureLocal(ownerId, family, 'save', request);
      }
      return await _resolve(family, 'save', request, 'save_room_layout');
    } finally {
      _saveBusy = false;
    }
  }
}

String furnitureReason(String? reason) => switch (reason) {
  'insufficient_balance' => '余额不足，未扣款',
  'purchase_limit' => '已达到家庭购买上限',
  'product_unavailable' => '此商品尚未开放购买',
  'family_required' => '请先创建或加入小屋',
  'family_changed' => '家庭已变化，本次购买未扣款，请刷新后重新购买',
  'policy_unconfirmed' => '编辑规则尚待确认',
  'editor_busy' => '另一位成员正在编辑，其他功能仍可使用',
  'lease_expired' => '编辑权已过期，草稿已保留，请重新获取',
  'version_conflict' => '家庭已有新布局，草稿已保留，请先查看最新版本',
  'inventory_missing' => '物件不属于家庭库存',
  'duplicate_instance' => '同一物件不能重复摆放',
  'category_limit' => '超出房间类别上限',
  'cell_conflict' => '家具占格冲突',
  'out_of_bounds' => '家具超出地板边界',
  'slot_conflict' => '固定挂位已占用',
  'fixed_position' => '窗、挂画和地毯不可自由移动',
  _ => '布局或商品信息无效，请核对后再试',
};
