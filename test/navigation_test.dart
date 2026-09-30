import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/app/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('four destinations and collapsed home menu fit a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const CatLibraryApp(preview: true));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byTooltip('打开功能菜单'), findsOneWidget);
    expect(find.byTooltip('布置猫窝'), findsNothing);
    await tester.tap(find.byIcon(Icons.menu_book_outlined));
    await tester.pump();
    expect(find.text('阅读功能筹备中'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pump();
    expect(find.text('外语学习'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pump();
    expect(find.byTooltip('打开功能菜单'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
