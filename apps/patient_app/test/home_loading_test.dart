import 'dart:async';

import 'package:asani_core/asani_core.dart';
import 'package:asani_ui/asani_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patient_app/data/demo/demo_backend.dart';
import 'package:patient_app/data/providers.dart';
import 'package:patient_app/features/home/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() => AppText.useGoogleFonts = false);

  testWidgets('"How Asani works" waits until the tokens have loaded', (tester) async {
    tester.view.physicalSize = const Size(400, 900) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    late DemoBackend backend;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      backend = await DemoBackend.create();
    });
    backend.stopSimulator();
    final tokens = StreamController<List<Token>>();
    final container = ProviderContainer(overrides: [
      backendProvider.overrideWithValue(backend),
      myTokensProvider.overrideWith((ref) => tokens.stream),
    ]);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildAppTheme(), home: const HomeScreen()),
    ));
    await tester.pump(const Duration(seconds: 2));

    // Still loading: a placeholder, never the new-user guide.
    expect(find.text('How Asani works'), findsNothing);
    expect(find.text('Welcome to Asani,'), findsNothing);
    expect(find.byType(SkeletonList), findsWidgets);

    // Loaded with no tokens: this really is a new user.
    tokens.add(const []);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('How Asani works'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    container.dispose();
    backend.dispose();
    unawaited(tokens.close());
    await tester.pump(const Duration(minutes: 1));
  });
}
