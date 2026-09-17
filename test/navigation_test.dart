import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/app/app.dart';

void main() {
  testWidgets('four destinations and home entries fit a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const CatLibraryApp());
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('商店'), findsOneWidget);
    expect(find.text('相册'), findsOneWidget);
    expect(find.byTooltip('设置'), findsOneWidget);
    await tester.tap(find.text('阅读'));
    await tester.pump();
    expect(find.text('阅读功能筹备中'), findsOneWidget);
    await tester.tap(find.text('任务板'));
    await tester.pump();
    expect(find.text('外语学习'), findsOneWidget);
    await tester.tap(find.text('猫窝'));
    await tester.pump();
    await tester.tap(find.text('布置猫窝'));
    await tester.pump();
    await tester.tap(find.text('阅读'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('离开布置？'), findsOneWidget);
    await tester.tap(find.text('继续布置'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('保存预览'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
