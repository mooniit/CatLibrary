import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/features/study/study_reward.dart';

void main() {
  test('confirmed whole-minute examples and one-minute threshold', () {
    expect(studyCoinsForDuration(const Duration(seconds: 59)), 0);
    expect(studyCoinsForDuration(const Duration(minutes: 1)), 2);
    expect(studyCoinsForDuration(const Duration(minutes: 5, seconds: 30)), 10);
    expect(studyCoinsForDuration(const Duration(minutes: 6)), 12);
    expect(studyCoinsForDuration(const Duration(minutes: 6, seconds: 10)), 12);
    expect(studyCoinsForDuration(const Duration(minutes: 60)), 120);
    expect(
      () => studyCoinsForDuration(const Duration(seconds: -1)),
      throwsArgumentError,
    );
  });
}
