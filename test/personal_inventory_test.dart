import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/features/room/layout_draft.dart';

void main() {
  test(
    'personal inventory includes own grants and cat souvenirs, never guesses null ownership',
    () {
      InventoryInstance item(Map<String, dynamic> fields) =>
          InventoryInstance.fromJson({
            'id': 'item',
            'sku': 'souvenir-palace',
            'source': 'test_grant',
            ...fields,
          });
      expect(item({'purchased_by': 'me'}).belongsTo('me'), isTrue);
      expect(item({'purchased_by': 'other'}).belongsTo('me'), isFalse);
      expect(
        item({'source_cat_owner': 'me', 'source': 'souvenir'}).belongsTo('me'),
        isTrue,
      );
      expect(
        item({
          'source_cat_owner': 'other',
          'source': 'souvenir',
        }).belongsTo('me'),
        isFalse,
      );
      expect(item({}).belongsTo('me'), isFalse);
    },
  );
}
