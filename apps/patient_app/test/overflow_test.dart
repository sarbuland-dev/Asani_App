import 'dart:io';

import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:patient_app/app.dart';
import 'package:patient_app/core/router/app_router.dart';
import 'package:patient_app/core/utils/device.dart';
import 'package:asani_ui/asani_ui.dart';
import 'package:patient_app/data/demo/demo_backend.dart';
import 'package:patient_app/data/providers.dart';
import 'package:patient_app/features/shell/main_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opens every screen on small phones and with large text, and fails on any
/// layout overflow ("A RenderFlex overflowed by N pixels"). On the phone with
/// bottom buttons it also fails when text is still under the floating tab bar or
/// those buttons after scrolling to the end.
///
/// Verdana (wider than Inter) stands in for Inter so results are on the safe side.
/// Windows only; skipped elsewhere.
const _sizes = [
  (name: 'small 320x640 @1.0', size: Size(320, 640), scale: 1.0, bottom: 0.0),
  (name: 'phone 360x740 @1.3', size: Size(360, 740), scale: 1.3, bottom: 0.0),
  (name: 'tiny 320x568 @1.3', size: Size(320, 568), scale: 1.3, bottom: 0.0),
  // Android's three bottom buttons (48 dp).
  (name: 'bottom buttons 360x640', size: Size(360, 640), scale: 1.0, bottom: 48.0),
];

/// Texts on screen that end below the floating tab bar's top edge, or below the
/// top of the phone's bottom buttons on pages without the bar.
List<String> _hiddenAtBottom(WidgetTester tester, Size size, double bottom) {
  var limit = size.height - bottom;
  final barTexts = <Element>{};
  final bar = find.byType(AnimatedFlex);
  if (bar.evaluate().isNotEmpty) {
    limit = tester.getRect(bar.first).top - 5; // the bar's own top padding
    barTexts.addAll(find.descendant(of: bar, matching: find.byType(Text)).evaluate());
  }
  final hidden = <String>[];
  for (final e in find.byType(Text).evaluate()) {
    final box = e.renderObject;
    if (barTexts.contains(e) || box is! RenderBox || !box.hasSize) continue;
    final r = box.localToGlobal(Offset.zero) & box.size;
    if (r.bottom > limit + 0.5 && r.top < size.height && r.left < size.width && r.right > 0) {
      hidden.add('"${(e.widget as Text).data}" is under the bottom bar');
    }
  }
  return hidden;
}

Future<void> _loadFonts() async {
  final loader = FontLoader('Inter');
  for (final f in ['verdana.ttf', 'verdanab.ttf']) {
    final file = File('C:/Windows/Fonts/$f');
    if (file.existsSync()) loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  final hasFont = File('C:/Windows/Fonts/verdana.ttf').existsSync();

  setUpAll(() async {
    AppText.useGoogleFonts = false;
    if (hasFont) await _loadFonts();
  });

  for (final cfg in _sizes) {
    testWidgets('no overflow on any screen · ${cfg.name}', (tester) async {
      final problems = <String>[];
      final original = FlutterError.onError;
      String current = '';
      FlutterError.onError = (details) {
        final text = details.toString();
        if (!text.contains('overflowed')) {
          original?.call(details);
          return;
        }
        final what = RegExp(r'overflowed by [\d.]+ pixels on the \w+').firstMatch(text)?.group(0) ?? 'overflowed';
        final where = RegExp(r'lib[/\\][\w/\\]+\.dart:\d+').firstMatch(text)?.group(0) ?? '?';
        problems.add('$current → $what at $where');
      };

      tester.view.physicalSize = cfg.size * 3;
      tester.view.devicePixelRatio = 3;
      tester.view.padding = FakeViewPadding(bottom: cfg.bottom * 3);
      tester.view.viewPadding = FakeViewPadding(bottom: cfg.bottom * 3);
      tester.platformDispatcher.textScaleFactorTestValue = cfg.scale;
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });

      // ---- data: signed-out backend for login screens, demo account for the rest
      late DemoBackend backend;
      late String bookedId, calledId;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        backend = await DemoBackend.create();
        await backend.update(backend.settings.copyWith(autoAdvanceQueue: false));
      });

      final container = ProviderContainer(overrides: [
        backendProvider.overrideWithValue(backend),
        // Show the Xiaomi-only Autostart card so its guide is checked too.
        isXiaomiPhoneProvider.overrideWith((ref) async => true),
      ]);
      addTearDown(() {
        container.dispose();
        backend.dispose();
      });
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const AsaniApp()));
      final router = container.read(routerProvider);

      Future<void> settle() async {
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> visit(String label, String path) async {
        current = label;
        router.go(path);
        await settle();
        // Scroll every scrollable to the end so lower content is laid out too
        // (again, because lazy lists only learn their full length on the way).
        for (var pass = 0; pass < 3; pass++) {
          for (final s in find.byType(Scrollable).evaluate().toList()) {
            final state = (s as StatefulElement).state as ScrollableState;
            if (state.position.maxScrollExtent > 0) state.position.jumpTo(state.position.maxScrollExtent);
          }
          await settle();
        }
        if (cfg.bottom > 0) problems.addAll([for (final h in _hiddenAtBottom(tester, cfg.size, cfg.bottom)) '$label → $h']);
      }

      // First launch: intro pages (D-29), then the login screens.
      await visit('intro', '/intro');
      await tester.runAsync(() => backend.update(backend.settings.copyWith(introSeen: true)));
      await settle();
      await visit('email', '/login/email');
      await tester.runAsync(() => backend.sendEmailOtp('demo@asani.pk'));
      await settle();
      await visit('otp', '/login/otp');
      await tester.runAsync(() => backend.verifyEmailOtp('demo@asani.pk', DemoBackend.demoOtp));
      await settle();
      await visit('name & consent', '/login/profile');
      await tester.runAsync(() async {
        await backend.createProfile(name: 'Muhammad Abdullah Khan Niazi', age: 34, gender: Gender.male, phone: '3001234567');
        await backend.update(backend.settings.copyWith(primerShown: true, notificationsAllowed: false));
        final today = dayKey(DateTime.now());
        final shazia = (await backend.watchMyPatients().first).firstWhere((p) => p.name == 'Shazia Begum');
        final self = (await backend.watchMyPatients().first).first;
        bookedId = (await backend.bookToken(clinicId: 'c_alshifa', doctorId: 'd_ayesha', patientId: shazia.id, date: today)).id;
        calledId = (await backend.bookToken(clinicId: 'c_dha', doctorId: 'd_bilal', patientId: self.id, date: today)).id;
        for (var i = 0; i < 4; i++) {
          await backend.advanceQueue('d_bilal');
        }
      });
      await settle();

      final screens = <(String, String)>[
        ('home', '/home'),
        ('tokens', '/tokens'),
        ('family', '/family'),
        ('account', '/account'),
        ('search', '/search'),
        ('search shifa', '/search?q=shifa'),
        ('search empty', '/search?q=xyz'),
        ('search other city', '/search?q=clifton'),
        ('search doctors GP', '/search?tab=doctors&speciality=generalPhysician'),
        ('search doctors none', '/search?tab=doctors&speciality=kidney'),
        ('clinic', '/clinic/c_alshifa'),
        ('clinic suspended', '/clinic/c_rehman'),
        ('doctor profile', '/doctor/c_alshifa/d_ayesha'),
        ('doctor profile other', '/doctor/c_alshifa/d_sana'),
        ('booking', '/book/c_alshifa/d_sana'),
        ('booking success', '/booked/$bookedId'),
        ('token live', '/token/$bookedId'),
        ('token called', '/token/$calledId'),
        ('token past', '/token/t_h1'),
        ('token cancelled', '/token/t_h2'),
        ('slip', '/token/$bookedId/slip'),
        ('slip cancelled', '/token/t_h2/slip'),
        ('profile', '/family/p_shazia'),
        ('profile edit', '/family/p_shazia/edit'),
        ('family new', '/family/new'),
        ('primer', '/notifications'),
        ('notifications list', '/inbox'),
      ];
      for (final (label, path) in screens) {
        await visit(label, path);
      }

      // D-66: a clinic with one doctor shows its page instead of jumping to booking.
      await visit('clinic one doctor', '/clinic/c_modeltown');
      expect(router.routerDelegate.currentConfiguration.uri.path, '/clinic/c_modeltown');

      // Sheets and dialogs opened from the shell screens
      Future<void> openAndClose(String label, String path, Finder button) async {
        current = label;
        router.go(path); // not visit(): its scroll-to-end can unbuild the button
        await settle();
        await tester.ensureVisible(button.first);
        await settle();
        await tester.tap(button.first);
        await settle();
        rootNavigatorKey.currentState!.pop();
        await settle();
      }

      await openAndClose('city picker', '/home', find.text('Lahore'));
      await openAndClose('autostart guide', '/account', find.text('Show me how'));
      await openAndClose('log out dialog', '/account', find.text('Log out'));
      await openAndClose('delete account dialog', '/account', find.text('Delete account'));

      // Booking steps 2 and 3
      current = 'booking steps';
      router.go('/book/c_alshifa/d_ayesha?patient=p_ahmed');
      await settle();
      current = 'booking date';
      await settle();
      final next = find.text('Next');
      if (next.evaluate().isNotEmpty) {
        await tester.tap(next);
        await settle();
      }
      current = 'booking confirm';
      await settle();

      // Several active tokens → Home carousel
      await visit('home with tokens', '/home');

      FlutterError.onError = original;
      router.go('/home');
      await settle();
      expect(problems.toSet().toList(), isEmpty, reason: problems.toSet().join('\n'));
    }, skip: !hasFont);
  }
}

// Keeps imports used when the router API changes.
// ignore: unused_element
GoRouter _unused(GoRouter r) => r;
