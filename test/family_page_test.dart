import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/features/family/family_page.dart';

void main() {
  testWidgets(
    'applicant submits code without creating a home and sees pending',
    (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: FamilyPage(
            ownerId: 'B',
            call: (action, args) async {
              calls.add(action);
              if (action == 'request_family_join') {
                expect(args, {'code': 'abc123'});
                return {
                  'family': null,
                  'members': [],
                  'requests': [
                    {'status': 'pending'},
                  ],
                };
              }
              return {'family': null, 'members': [], 'requests': []};
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'abc123');
      await tester.ensureVisible(find.text('申请加入'));
      await tester.tap(find.text('申请加入'));
      await tester.pumpAndSettle();
      expect(find.text('等待邀请人确认'), findsOneWidget);
      expect(calls, ['family_state', 'request_family_join']);
    },
  );
  testWidgets('inviter approves selected request and sees updated members', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FamilyPage(
          ownerId: 'A',
          call: (action, args) async {
            if (action == 'decide_family_join') {
              expect(args, {'request_id': 'request-b', 'approve': true});
            }
            return {
              'family': {
                'id': 'home',
                'is_creator': true,
                'invite_code': 'abc',
              },
              'members': [
                {'user_id': 'A', 'is_me': true},
                if (action == 'decide_family_join')
                  {'user_id': 'B', 'is_me': false},
              ],
              'requests': action == 'decide_family_join'
                  ? []
                  : [
                      {
                        'id': 'request-b',
                        'applicant_id': 'B',
                        'status': 'pending',
                      },
                    ],
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('同意加入'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('同意加入'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 800));
    await tester.pumpAndSettle();
    expect(find.text('小屋成员 2/2'), findsOneWidget);
  });
}
