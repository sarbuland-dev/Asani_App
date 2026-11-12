import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/net/connectivity.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/providers.dart';
import 'data/repositories/repositories.dart';

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

final _alertsProvider = StreamProvider<QueueAlert>((ref) => ref.watch(tokenRepositoryProvider).alerts);

final _openedRouteProvider = StreamProvider<String>((ref) {
  final push = ref.watch(pushServiceProvider);
  if (push == null) return const Stream.empty();
  return _startWith(push.takeInitialRoute(), push.openedRoutes);
});

Stream<String> _startWith(String? first, Stream<String> rest) async* {
  if (first != null) yield first;
  yield* rest;
}

class AsaniApp extends ConsumerWidget {
  const AsaniApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    // Tapping a notification opens the token (PRD N-6) or a pre-filled booking (F-09).
    ref.listen(_openedRouteProvider, (_, next) {
      final route = next.value;
      if (route != null) router.push(route);
    });

    // Queue notifications that arrive while the app is open (demo or FCM).
    ref.listen(_alertsProvider, (_, next) {
      final alert = next.value;
      if (alert == null) return;
      scaffoldMessengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 6),
          backgroundColor: alert.step.ahead == 0 ? AppColors.info : AppColors.textPrimary,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(alert.title, style: AppText.labelLarge.copyWith(color: AppColors.onPrimary)),
              const SizedBox(height: 2),
              Text(alert.body, style: AppText.bodyMedium.copyWith(color: AppColors.onPrimary.withValues(alpha: 0.9))),
            ],
          ),
          action: SnackBarAction(
            label: 'View',
            textColor: AppColors.primaryContainer,
            onPressed: () => router.push('/token/${alert.tokenId}'),
          ),
        ));
    });

    return MaterialApp.router(
      title: 'Asani',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      scaffoldMessengerKey: scaffoldMessengerKey,
      routerConfig: router,
      builder: (context, child) {
        // Support text scaling up to 1.3× (DESIGN.md §3.2).
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3)),
          child: OfflineBanner(child: child!),
        );
      },
    );
  }
}
