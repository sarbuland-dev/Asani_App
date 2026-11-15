import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patient_app/core/widgets/keyboard_dismisser.dart';

void main() {
  late FocusNode first;
  late FocusNode second;
  var buttonTaps = 0;

  Widget app() => MaterialApp(
        builder: (context, child) => KeyboardDismisser(child: child!),
        home: Scaffold(
          body: Column(
            children: [
              TextField(key: const Key('first'), focusNode: first),
              TextField(key: const Key('second'), focusNode: second),
              ElevatedButton(onPressed: () => buttonTaps++, child: const Text('Go')),
              const Expanded(child: SizedBox.expand(key: Key('empty'))),
            ],
          ),
        ),
      );

  setUp(() {
    first = FocusNode();
    second = FocusNode();
    buttonTaps = 0;
  });

  tearDown(() {
    first.dispose();
    second.dispose();
  });

  testWidgets('tapping empty space closes the keyboard', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const Key('first')));
    await tester.pump();
    expect(first.hasFocus, isTrue);

    // Empty space has no hit target of its own; only the dismisser receives the tap.
    await tester.tap(find.byKey(const Key('empty')), warnIfMissed: false);
    await tester.pump();
    expect(first.hasFocus, isFalse);
  });

  testWidgets('tapping another field moves focus to it', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const Key('first')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('second')));
    await tester.pump();
    expect(second.hasFocus, isTrue);
  });

  testWidgets('buttons still work while a field is focused', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const Key('first')));
    await tester.pump();

    await tester.tap(find.text('Go'));
    await tester.pump();
    expect(buttonTaps, 1);
  });
}
