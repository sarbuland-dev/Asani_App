import 'package:asani_ui/asani_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => AppText.useGoogleFonts = false);

  /// Opens a second page and returns its left edge [after] the tap.
  Future<double> leftEdge(WidgetTester tester, Duration after, {bool reduceMotion = false}) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion), child: child!),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SizedBox.expand(key: Key('next')))),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(after);
    return tester.getTopLeft(find.byKey(const Key('next'))).dx;
  }

  testWidgets('P11: the new page slides in from the right and is there after 300 ms', (tester) async {
    expect(await leftEdge(tester, const Duration(milliseconds: 100)), greaterThan(0));
    await tester.pump(AsaniPageTransitionsBuilder.duration);
    expect(tester.getTopLeft(find.byKey(const Key('next'))).dx, 0);
  });

  testWidgets('P11: with "Remove animations" the page just appears', (tester) async {
    expect(await leftEdge(tester, const Duration(milliseconds: 16), reduceMotion: true), 0);
  });
}
