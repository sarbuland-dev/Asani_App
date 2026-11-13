import 'package:asani_ui/asani_ui.dart';
import 'package:flutter/material.dart';

import '../errors/app_exception.dart';

/// Error state with this app's error messages (DESIGN.md §6). The other
/// shared widgets live in packages/asani_ui.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, this.error, this.onRetry});
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Something went wrong',
        message: error == null ? 'Please try again.' : AppException.messageOf(error!),
        actionLabel: onRetry == null ? null : 'Retry',
        onAction: onRetry,
      );
}
