// One test per bug from the 28 November 2026 QA run (B1 to B12).
import 'dart:io';

import 'package:asani_core/asani_core.dart';
import 'package:asani_ui/asani_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patient_app/app.dart';
import 'package:patient_app/core/router/app_router.dart';
import 'package:patient_app/core/utils/slip_saver.dart';
import 'package:patient_app/data/demo/demo_backend.dart';
import 'package:patient_app/data/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

late DemoBackend backend;
late ProviderContainer container;

Future<void> settle(WidgetTester t, [int n = 20]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Signed-in demo account on a 390x844 phone with a 44 dp status bar.
Future<void> start(WidgetTester t, {bool brokenTokens = false, List<String>? saved}) async {
  t.view.physicalSize = const Size(390, 844) * 2;
  t.view.devicePixelRatio = 2;
  t.view.padding = const FakeViewPadding(top: 88);
  t.view.viewPadding = const FakeViewPadding(top: 88);
  addTearDown(t.view.reset);
  await t.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    backend = await DemoBackend.create();
    await backend.update(backend.settings.copyWith(autoAdvanceQueue: false, introSeen: true, primerShown: true, notificationsAllowed: true));
  });
  container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      backendProvider.overrideWithValue(backend),
      if (saved != null) saveImageProvider.overrideWithValue((png, name) async => saved.add('$name ${png.length > 1000}')),
      if (brokenTokens) tokenProvider.overrideWith((ref, id) => Stream<Token?>.error(Exception("SocketException: offline"))),
    ],
  );
  addTearDown(() {
    container.dispose();
    backend.dispose();
  });
  await t.pumpWidget(UncontrolledProviderScope(container: container, child: const AsaniApp()));
  await settle(t);
  await t.runAsync(() async {
    await backend.sendEmailOtp('demo@asani.pk');
    await backend.verifyEmailOtp('demo@asani.pk', DemoBackend.demoOtp);
    await backend.createProfile(name: 'Ali Raza', age: 34, gender: Gender.male, phone: '3001234567');
  });
  await settle(t);
}

Future<void> go(WidgetTester t, String path) async {
  container.read(routerProvider).go(path);
  await settle(t);
}

void main() {
  setUpAll(() async {
    AppText.useGoogleFonts = false;
    final l = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      l.addFont(Future.value(
          ByteData.sublistView(File('assets/google_fonts/Inter-$w.ttf').readAsBytesSync())));
    }
    await l.load();
  });

  testWidgets('B1 in-app queue banner closes by itself after its 6 s duration', (t) async {
    await start(t);
    await t.runAsync(() async {
      final self = (await backend.watchMyPatients().first).first;
      await backend.bookToken(clinicId: 'c_dha', doctorId: 'd_bilal', patientId: self.id, date: dayKey(DateTime.now()));
      for (var i = 0; i < 4; i++) {
        await backend.advanceQueue('d_bilal');
      }
    });
    await settle(t);
    expect(find.byType(SnackBar), findsOneWidget, reason: 'precondition: banner shown');
    for (var i = 0; i < 60; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    await settle(t);
    expect(find.byType(SnackBar), findsNothing, reason: 'still on screen 60 s later');
  });

  testWidgets('B2 estimated wait has one "~"', (t) async {
    await start(t);
    await go(t, '/clinic/c_alshifa');
    expect(find.textContaining('~~'), findsNothing);
  });

  testWidgets('B3 Account shows the whole mobile number', (t) async {
    await start(t);
    await go(t, '/account');
    final p = t.renderObject<RenderParagraph>(find.descendant(of: find.text('+92 300 1234567').last, matching: find.byType(RichText)));
    expect(p.didExceedMaxLines, isFalse, reason: 'number is cut with "..." (width ${p.size.width})');
  });

  testWidgets('B4 token slip clinic initials match the rest of the app (AS)', (t) async {
    await start(t);
    late String id;
    await t.runAsync(() async {
      final self = (await backend.watchMyPatients().first).first;
      id = (await backend.bookToken(clinicId: 'c_alshifa', doctorId: 'd_ayesha', patientId: self.id, date: dayKey(DateTime.now()))).id;
    });
    await go(t, '/token/$id/slip');
    expect(find.text('AS'), findsWidgets);
    expect(find.text('AC'), findsNothing);
  });

  testWidgets('B5 no large gap between "Relation" and its chips', (t) async {
    await start(t);
    await go(t, '/family/new');
    final gap = t.getTopLeft(find.text('Mother').last).dy - t.getBottomLeft(find.text('Relation')).dy;
    final chipTop = t.getTopLeft(find.byType(GridView)).dy - t.getBottomLeft(find.text('Relation')).dy;
    final first = t.getTopLeft(find.descendant(of: find.byType(GridView), matching: find.byType(AnimatedContainer)).first).dy -
        t.getTopLeft(find.byType(GridView)).dy;
    expect(first, lessThan(2), reason: 'GridView adds ${first.toStringAsFixed(0)} dp above the first chip (label gap $chipTop, text gap $gap)');
  });

  for (final (label, path) in [
    ('token', '/token/does-not-exist'),
    ('clinic', '/clinic/does-not-exist'),
  ]) {
    testWidgets('B6 "$label not found" opened from a link has a way out, centred', (t) async {
      await start(t);
      await go(t, path);
      final title = find.textContaining('not found');
      expect(find.byType(BackButton).evaluate().length + find.byType(FilledButton).evaluate().length, greaterThan(0),
          reason: 'no back or home button');
      expect(t.getCenter(title).dx, closeTo(195, 3), reason: 'not centred');
    });
  }

  testWidgets('B7 booking link with an unknown doctor does not load forever', (t) async {
    await start(t);
    await go(t, '/book/c_alshifa/does-not-exist');
    await settle(t, 150);
    expect(find.byType(LoadingScreen), findsNothing, reason: 'still loading after 17 s, no error shown');
  });

  testWidgets('B8 token stream error is not reported as "Token not found"', (t) async {
    await start(t, brokenTokens: true);
    await go(t, '/token/t_h1');
    await settle(t, 40);
    expect(find.text('Token not found'), findsNothing);
  });

  testWidgets('B9 unknown link shows an Asani screen, not the default router page', (t) async {
    await start(t);
    await go(t, '/nope');
    expect(find.textContaining('GoException'), findsNothing);
    expect(find.text('Page Not Found'), findsNothing);
  });

  testWidgets("B10 booking calendar dates start right under the weekday row", (t) async {
    await start(t);
    await go(t, "/book/c_alshifa/d_sana");
    await t.tap(find.text("Continue"));
    await settle(t);
    final grid = find.byType(GridView);
    final firstCellTop = t.getTopLeft(find.descendant(of: grid, matching: find.byType(Text)).first).dy;
    final gap = firstCellTop - t.getBottomLeft(find.text("Mon")).dy;
    expect(gap, lessThan(40), reason: "blank band of ${gap.toStringAsFixed(0)} dp");
  });

  testWidgets('B11 "Save to gallery" saves the slip picture instead of sharing it', (t) async {
    final saved = <String>[];
    await start(t, saved: saved);
    late String id;
    await t.runAsync(() async {
      final self = (await backend.watchMyPatients().first).first;
      id = (await backend.bookToken(clinicId: 'c_alshifa', doctorId: 'd_ayesha', patientId: self.id, date: dayKey(DateTime.now()))).id;
    });
    await go(t, '/token/$id/slip');
    await t.tap(find.text('Save to gallery'));
    for (var i = 0; i < 20 && saved.isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump();
    }
    expect(saved, hasLength(1));
    expect(saved.single, startsWith('asani-token-'));
    expect(saved.single, endsWith('true'), reason: 'not a real picture');
    await settle(t);
    expect(find.text('Slip saved to your gallery.'), findsOneWidget);
  });

  testWidgets('B12 a page opened through the router slides in (D-63)', (t) async {
    await start(t);
    await go(t, '/home');
    container.read(routerProvider).push('/clinic/c_alshifa');
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    final page = find.byType(CustomScrollView).last;
    final midway = t.getTopLeft(page).dx;
    await settle(t);
    expect(midway, greaterThan(20), reason: 'the page appeared at once');
    expect(t.getTopLeft(find.byType(CustomScrollView).last).dx, 0);
  });

  testWidgets('B14 "Book again" opens the date step with an open day already chosen', (t) async {
    await start(t);
    late String patientId;
    await t.runAsync(() async => patientId = (await backend.watchMyPatients().first).first.id);
    await go(t, '/book/c_alshifa/d_sana?patient=$patientId');
    expect(find.text('Pick a date'), findsOneWidget, reason: 'precondition: starts on the date step');
    expect(find.text('No dates available'), findsNothing);
    await t.tap(find.text('Continue'));
    await settle(t);
    expect(find.text('Review and confirm'), findsOneWidget, reason: 'Continue must work without tapping a date');
  });

  testWidgets('Q1 a profile lists the active token apart, so the Visits list matches its count (D-68)', (t) async {
    await start(t);
    late String patientId;
    var completed = 0;
    await t.runAsync(() async {
      final shazia = (await backend.watchMyPatients().first).firstWhere((p) => p.name == 'Shazia Begum');
      patientId = shazia.id;
      await backend.bookToken(clinicId: 'c_alshifa', doctorId: 'd_ayesha', patientId: shazia.id, date: dayKey(DateTime.now()));
      completed = (await backend.watchMyTokens().first)
          .where((x) => x.patientId == shazia.id && x.status == TokenStatus.completed)
          .length;
    });
    await go(t, '/family/$patientId');
    expect(find.text('Visits · $completed'), findsOneWidget);
    expect(find.text('Active token'), findsOneWidget);
    expect(find.text('Visits'), completed > 0 ? findsOneWidget : findsNothing);
  });
}
