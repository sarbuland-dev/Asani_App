import 'package:asani_ui/asani_ui.dart';
import 'package:flutter/widgets.dart';

/// Space to leave under the last item of a scrolling page, so it can always be
/// scrolled clear of whatever covers the bottom: on the tabs the floating bar
/// plus the phone's own buttons, elsewhere just the phone's buttons or gesture
/// line. [gap] is the breathing room above that.
double bottomClearance(BuildContext context, [double gap = Gap.xl]) => MediaQuery.paddingOf(context).bottom + gap;
