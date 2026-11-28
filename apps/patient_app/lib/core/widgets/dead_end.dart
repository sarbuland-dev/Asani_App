import 'package:asani_ui/asani_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'error_state.dart';

/// A page with nothing to show (not found, or it failed to load). It always has
/// a way out: back when there is a page behind it, otherwise Home.
class _DeadEnd extends StatelessWidget {
  const _DeadEnd({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: Navigator.of(context).canPop()
              ? null // the normal back button
              : IconButton(tooltip: 'Home', onPressed: () => context.go('/home'), icon: const Icon(Icons.home_outlined)),
        ),
        body: Center(child: SingleChildScrollView(child: child)),
      );
}

/// A link or ID that points to nothing.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key, required this.icon, required this.title, required this.message});
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => _DeadEnd(
        child: EmptyState(icon: icon, title: title, message: message, actionLabel: 'Go to Home', onAction: () => context.go('/home')),
      );
}

/// A page that could not load (offline, server error), with Retry (DESIGN.md §6).
class LoadErrorScreen extends StatelessWidget {
  const LoadErrorScreen({super.key, required this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _DeadEnd(child: ErrorState(error: error, onRetry: onRetry));
}
