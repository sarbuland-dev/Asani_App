import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Board P11 "Page transition" (DESIGN.md §9, D-63): a page that opens on top
/// slides in from the right, iPhone style, while the old page moves aside and
/// dims. Back, or a swipe from the left edge, plays it in reverse. With the
/// phone's "Remove animations" on, the page just appears.
class AsaniPageTransitionsBuilder extends CupertinoPageTransitionsBuilder {
  const AsaniPageTransitionsBuilder();

  static const duration = Duration(milliseconds: 300);

  @override
  Duration get transitionDuration => duration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    return super.buildTransitions<T>(route, context, animation, secondaryAnimation, child);
  }
}

/// The same movement on every platform.
final asaniPageTransitions = PageTransitionsTheme(
  builders: {for (final p in TargetPlatform.values) p: const AsaniPageTransitionsBuilder()},
);
