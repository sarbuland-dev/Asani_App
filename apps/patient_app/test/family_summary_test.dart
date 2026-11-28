import 'package:asani_ui/asani_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patient_app/features/family/family_summary.dart';

void main() {
  setUpAll(() => AppText.useGoogleFonts = false);

  Future<void> show(WidgetTester tester, {required List<MemberVisits> members, int live = 0, int followUps = 0, List<String>? taps}) {
    return tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: FamilySummaryCard(
              members: members,
              liveTokens: live,
              followUps: followUps,
              onLiveTokens: () => taps?.add('tokens'),
              onFollowUps: () => taps?.add('followUp'),
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('totals the visits, puts the most first and both buttons work (D-65)', (tester) async {
    final taps = <String>[];
    await show(tester,
        members: const [(name: 'Zara Ali', visits: 2), (name: 'Ali Raza', visits: 6)], live: 1, followUps: 2, taps: taps);

    expect(find.text('8 visits so far'), findsOneWidget);
    expect(tester.getCenter(find.text('Ali')).dx, lessThan(tester.getCenter(find.text('Zara')).dx));

    await tester.tap(find.text('1 live token'));
    await tester.tap(find.text('2 follow-ups'));
    expect(taps, ['tokens', 'followUp']);
  });

  testWidgets('hides a zero button, and the chart when there are no visits', (tester) async {
    await show(tester, members: const [(name: 'Ali Raza', visits: 0)], followUps: 1);

    expect(find.text('1 follow-up'), findsOneWidget);
    expect(find.textContaining('live token'), findsNothing);
    expect(find.textContaining('so far'), findsNothing);
    expect(find.text('by member'), findsNothing);
  });

  testWidgets('more than four members scroll sideways', (tester) async {
    await show(tester, members: [for (var i = 6; i > 0; i--) (name: 'M$i', visits: i)]);

    final last = find.text('M1');
    final before = tester.getCenter(last).dx;
    await tester.drag(find.byType(SingleChildScrollView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(tester.getCenter(last).dx, lessThan(before));
  });
}
