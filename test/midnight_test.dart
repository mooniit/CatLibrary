import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/core/time/business_day.dart';

void main() {
  test('23:59 to 00:01 splits into independent Beijing dates', () {
    expect(
      millisecondsByBusinessDay(
        DateTime.utc(2026, 9, 26, 15, 59),
        DateTime.utc(2026, 9, 26, 16, 1),
      ),
      {'2026-09-26': 60000, '2026-09-27': 60000},
    );
  });
  test('subseconds are preserved and exact midnight adds no phantom day', () {
    expect(
      millisecondsByBusinessDay(
        DateTime.utc(2026, 9, 26, 15, 59, 59, 500),
        DateTime.utc(2026, 9, 26, 16),
      ),
      {'2026-09-26': 500},
    );
  });
}
