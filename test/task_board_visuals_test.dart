import 'package:cat_library_demo/app/app_theme.dart';
import 'package:cat_library_demo/features/tasks/task_board_visuals.dart';
import 'package:cat_library_demo/features/tasks/task_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    for (final width in [320.0, 768.0]) {
      testWidgets(
        'bookmarks remain readable at $width and large text in $brightness',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var starts = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(brightness),
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 1000),
                    textScaler: const TextScaler.linear(1.6),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      const TaskBoardHeading(),
                      const TaskSectionTitle(
                        '每周特别任务',
                        icon: Icons.auto_stories_outlined,
                        trailing: IconButton(
                          onPressed: null,
                          icon: Icon(Icons.refresh),
                          tooltip: '刷新周任务',
                        ),
                      ),
                      TaskActivityCard(
                        activity: TaskActivity.language,
                        rewardCaption: '上次核对 3/12 鹰镑',
                        issued: 3,
                        onStart: () => starts++,
                      ),
                      const TaskActivityCard(
                        activity: TaskActivity.exercise,
                        rewardCaption: '今日奖励待核对',
                        issued: null,
                        onStart: null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('今日书签'), findsOneWidget);
          await tester.ensureVisible(find.byTooltip('开始外语学习'));
          await tester.tap(find.byTooltip('开始外语学习'));
          expect(starts, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
