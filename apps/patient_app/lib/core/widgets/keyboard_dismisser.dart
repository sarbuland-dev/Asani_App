import 'package:flutter/material.dart';

/// Closes the keyboard when the user taps anywhere outside a text field.
///
/// Wrapped once around the whole app in `MaterialApp.builder`, so every screen
/// gets this without extra code. Hit testing is translucent, so taps still reach
/// the widgets underneath. A tap on another field or a button is won by that
/// widget in the gesture arena, so focus moves and buttons work as normal.
class KeyboardDismisser extends StatelessWidget {
  const KeyboardDismisser({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }
}
