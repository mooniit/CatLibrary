import 'package:cat_library_demo/app/app.dart';
import 'package:cat_library_demo/app/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('settings theme persists and restores on next launch', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const CatLibraryApp(preview: true));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.tap(find.byTooltip('打开功能菜单'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('白色简约'), findsOneWidget);
    expect(find.text('暗色夜晚'), findsOneWidget);

    await tester.tap(find.text('暗色夜晚'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('主题未保存，请重试'), findsNothing);
    expect(await loadAppTheme(), ThemeMode.dark);
    expect(
      Theme.of(tester.element(find.text('暗色夜晚'))).brightness,
      Brightness.dark,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      CatLibraryApp(preview: true, initialThemeMode: await loadAppTheme()),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.tap(find.byTooltip('打开功能菜单'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      Theme.of(tester.element(find.text('暗色夜晚'))).brightness,
      Brightness.dark,
    );
    expect(tester.takeException(), isNull);
  });
}
