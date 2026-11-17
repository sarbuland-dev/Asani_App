import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// The "a" mark of the 2026-11-17 logo: an open bowl, a stem and a tail
/// that swings up to the right. One colour.
class AsaniMark extends StatelessWidget {
  const AsaniMark({super.key, this.size = 48, this.color = AppColors.primary, this.plusColor = AppColors.secondary});
  final double size;
  final Color color;

  /// Unused: the old mark had a plus in the bowl; the new logo has none.
  /// Kept so existing callers keep compiling.
  final Color plusColor;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _MarkPainter(color));
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn in the 100x100 box used by the SVG logo.
    final s = size.width / 100;
    canvas.save();
    canvas.scale(s);
    canvas.translate(2, -4);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Bowl: open at the top right, from just right of 12 o'clock round the
    // left and bottom to where it meets the stem.
    const deg = 3.14159265 / 180;
    canvas.drawArc(Rect.fromCircle(center: const Offset(40, 56), radius: 22), -80 * deg, -262 * deg, false, stroke);
    // Stem, then the tail swinging up to the right.
    final tail = Path()
      ..moveTo(62, 34)
      ..lineTo(62, 64)
      ..quadraticBezierTo(62, 80, 75, 74)
      ..lineTo(86, 62);
    canvas.drawPath(tail, stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color;
}

/// Logo tile: white rounded square with the teal mark.
class AsaniLogoTile extends StatelessWidget {
  const AsaniLogoTile({super.key, this.size = 72});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(size * 0.26)),
        alignment: Alignment.center,
        child: AsaniMark(size: size * 0.82),
      );
}

/// Teal gradient header with soft decorative circles (UI design).
class GradientHeader extends StatelessWidget {
  const GradientHeader({
    super.key,
    required this.child,
    this.gradient = AppColors.headerGradient,
    this.padding = const EdgeInsets.fromLTRB(Gap.screen, Gap.md, Gap.screen, Gap.xl),
    this.radius = Radii.header,
  });

  final Widget child;
  final Gradient gradient;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: gradient),
        child: Stack(
          children: [
            Positioned(right: -60, top: -50, child: _bubble(200)),
            Positioned(left: -40, bottom: -70, child: _bubble(150)),
            SafeArea(bottom: false, child: Padding(padding: padding, child: child)),
          ],
        ),
      ),
    );
  }

  Widget _bubble(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.onPrimary.withValues(alpha: 0.07)),
      );
}

/// Status bar styles. Light icons on teal / coloured headers, dark icons on
/// white screens. Transparent bar so the page colour shows through.
const kStatusBarLight = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light, // Android
  statusBarBrightness: Brightness.dark, // iOS
  systemStatusBarContrastEnforced: false,
);
const kStatusBarDark = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemStatusBarContrastEnforced: false,
);

/// For screens whose coloured header scrolls away: light status bar icons
/// and a solid strip behind the status bar, so scrolled content never runs
/// under the clock.
class StatusBarScrim extends StatelessWidget {
  const StatusBarScrim({super.key, required this.child, this.color = AppColors.primary});
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kStatusBarLight,
      child: Stack(children: [
        child,
        Positioned(top: 0, left: 0, right: 0, height: top, child: ColoredBox(color: color)),
      ]),
    );
  }
}

/// Small spinner inside a button while it works. Takes the button's own
/// foreground colour, so it stays visible when the button is disabled.
class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({super.key});

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: IconTheme.of(context).color),
      );
}

/// Dashed tear line, like on a paper token slip.
/// Painted, so it also works inside IntrinsicHeight / IntrinsicWidth.
class DashedLine extends StatelessWidget {
  const DashedLine({super.key, this.color = AppColors.border, this.axis = Axis.horizontal});
  final Color color;
  final Axis axis;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: axis == Axis.horizontal ? double.infinity : 1.5,
        height: axis == Axis.horizontal ? 1.5 : double.infinity,
        child: CustomPaint(painter: _DashPainter(color, axis)),
      );
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color, this.axis);
  final Color color;
  final Axis axis;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final length = axis == Axis.horizontal ? size.width : size.height;
    for (double d = 0; d < length; d += 9) {
      final rect = axis == Axis.horizontal
          ? Rect.fromLTWH(d, 0, 5, size.height)
          : Rect.fromLTWH(0, d, size.width, 5);
      canvas.drawRect(rect, p);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color || old.axis != axis;
}

/// A paper-ticket outline: rounded corners with two half-circle notches cut
/// into the top and bottom edges at [notchX] (where the stub tears off).
/// Use as a Material `shape` so ink splashes and clipping follow it.
class TicketBorder extends ShapeBorder {
  const TicketBorder({this.notchX = 76, this.notchRadius = 8, this.radius = Radii.card, this.side = BorderSide.none});
  final double notchX;
  final double notchRadius;
  final double radius;
  final BorderSide side;

  Path _path(Rect r) {
    final body = Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)));
    final notches = Path()
      ..addOval(Rect.fromCircle(center: Offset(r.left + notchX, r.top), radius: notchRadius))
      ..addOval(Rect.fromCircle(center: Offset(r.left + notchX, r.bottom), radius: notchRadius));
    return Path.combine(PathOperation.difference, body, notches);
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => _path(rect.deflate(side.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(_path(rect.deflate(side.width / 2)), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) =>
      TicketBorder(notchX: notchX * t, notchRadius: notchRadius * t, radius: radius * t, side: side.scale(t));
}

/// Round translucent back button used on gradient headers.
class HeaderBackButton extends StatelessWidget {
  const HeaderBackButton({super.key, this.onPressed, this.icon = Icons.chevron_left_rounded, this.dark = false});
  final VoidCallback? onPressed;
  final IconData icon;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
      child: Material(
        color: dark ? AppColors.muted : AppColors.onPrimary.withValues(alpha: 0.18),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed ?? () => Navigator.of(context).maybePop(),
          child: SizedBox.square(
            dimension: 44,
            child: Icon(icon, color: dark ? AppColors.textPrimary : AppColors.onPrimary, size: 28),
          ),
        ),
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(Gap.lg),
    this.color = AppColors.surface,
    this.borderColor = AppColors.border,
    this.radius = Radii.card,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color color;
  final Color borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: borderColor),
    );
    return Material(
      color: color,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// Small pill badge with an optional leading dot or icon.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.fg, required this.bg, this.dot = false, this.icon});
  final String label;
  final Color fg;
  final Color bg;
  final bool dot;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(width: 7, height: 7, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
          Flexible(
            child: Text(label,
                style: AppText.labelSmall.copyWith(color: fg, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// Token status chip. Text label always present (colour is never the only signal).
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final TokenStatus status;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (status) {
      TokenStatus.booked => (AppColors.warning, AppColors.warningContainer),
      TokenStatus.arrived => (AppColors.success, AppColors.successContainer),
      TokenStatus.called => (AppColors.info, AppColors.infoContainer),
      TokenStatus.completed => (AppColors.success, AppColors.successContainer),
      TokenStatus.onHold => (AppColors.warning, AppColors.warningContainer),
      TokenStatus.cancelled || TokenStatus.noShow || TokenStatus.skipped => (AppColors.danger, AppColors.dangerContainer),
    };
    return Pill(label: status.label, fg: fg, bg: bg, dot: true);
  }
}

class AvailabilityPill extends StatelessWidget {
  const AvailabilityPill({super.key, required this.availability, this.schedule});
  final DoctorAvailability availability;
  final DaySchedule? schedule;

  @override
  Widget build(BuildContext context) {
    return switch (availability) {
      DoctorAvailability.available => Pill(
          label: schedule == null ? 'Available today' : 'Available · ${Fmt.timeRangeShort(schedule!)}',
          fg: AppColors.success,
          bg: AppColors.successContainer,
          dot: true),
      DoctorAvailability.notStarted => Pill(
          label: schedule == null ? 'Not started yet' : 'Starts at ${Fmt.time(schedule!.start)}',
          fg: AppColors.warning,
          bg: AppColors.warningContainer,
          icon: Icons.schedule_rounded),
      DoctorAvailability.onLeave =>
        const Pill(label: 'On leave today', fg: AppColors.danger, bg: AppColors.dangerContainer, dot: true),
      DoctorAvailability.notScheduled =>
        const Pill(label: 'Not available today', fg: AppColors.textSecondary, bg: AppColors.muted, dot: true),
      DoctorAvailability.full =>
        const Pill(label: 'Tokens full', fg: AppColors.danger, bg: AppColors.dangerContainer, dot: true),
      DoctorAvailability.ended =>
        const Pill(label: 'Session ended', fg: AppColors.textSecondary, bg: AppColors.muted, dot: true),
    };
  }
}

class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 48, this.bg = AppColors.primary, this.fg = AppColors.onPrimary});
  final String name;
  final double size;
  final Color bg;
  final Color fg;

  /// Colour pair for a family member, based on relation.
  static (Color, Color) colorsFor(Relation r) => switch (r) {
        Relation.self => (AppColors.primary, AppColors.onPrimary),
        Relation.mother || Relation.father || Relation.spouse => (AppColors.avatarWarm, AppColors.warning),
        _ => (AppColors.avatarCool, AppColors.secondary),
      };

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Text(Fmt.initials(name),
            style: AppText.labelLarge.copyWith(color: fg, fontSize: size * 0.34, fontWeight: FontWeight.w700)),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Gap.xl, bottom: Gap.md),
        child: Row(
          children: [
            Expanded(child: Text(text, style: AppText.titleMedium.copyWith(fontWeight: FontWeight.w700))),
            ?trailing,
          ],
        ),
      );
}

/// Number tile: "Now serving A-7", "Ahead of you 3".
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.bg = AppColors.primaryContainer, this.fg = AppColors.primary, this.big = true});
  final String label;
  final String value;
  final Color bg;
  final Color fg;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.md + 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.button)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // One line, shrinking only if it must ("Now serving" never breaks in two).
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(label, maxLines: 1, softWrap: false, style: AppText.labelSmall.copyWith(color: AppColors.textSecondary)),
          ),
          const SizedBox(height: Gap.xs),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, .3), end: Offset.zero).animate(a), child: c)),
            // One line; shrinks only when it doesn't fit (narrow phones, large
            // system font), instead of breaking a word ("Any mome / nt").
            child: FittedBox(
              key: ValueKey(value),
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  maxLines: 1,
                  softWrap: false,
                  style: (big ? AppText.displaySmall : AppText.titleMedium).copyWith(color: fg, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.actionLabel, this.onAction});
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.xl, vertical: Gap.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(color: AppColors.primaryContainer, shape: BoxShape.circle),
            child: Icon(icon, size: 44, color: AppColors.primary),
          ),
          const SizedBox(height: Gap.xl),
          Text(title, style: AppText.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: Gap.sm),
          Text(message, style: AppText.bodyMedium.copyWith(fontSize: 15), textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: Gap.xl),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

/// Skeleton cards for loading lists (DESIGN.md §6: skeletons, not spinners).
class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key, this.count = 3, this.height = 92});
  final int count;
  final double height;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
      child: Column(
        children: [
          for (var i = 0; i < widget.count; i++)
            Container(
              height: widget.height,
              margin: const EdgeInsets.only(bottom: Gap.md),
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(Radii.card)),
            ),
        ],
      ),
    );
  }
}

/// Rounded square icon box used inside cards.
class IconBox extends StatelessWidget {
  const IconBox({super.key, required this.icon, this.bg = AppColors.primaryContainer, this.fg = AppColors.primary, this.size = 44});
  final IconData icon;
  final Color bg;
  final Color fg;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.button)),
        child: Icon(icon, color: fg, size: size * 0.5),
      );
}

/// A full-height column that scrolls when space runs out (small phones,
/// large text, open keyboard). Lets screens keep `Spacer`s safely.
class FillScrollView extends StatelessWidget {
  const FillScrollView({super.key, required this.child, this.padding = EdgeInsets.zero});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: (c.maxHeight - padding.vertical).clamp(0, double.infinity)),
            child: IntrinsicHeight(child: child),
          ),
        ),
      );
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Confirmation dialog; returns true when confirmed.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: AppText.titleLarge),
      content: Text(message, style: AppText.bodyLarge),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancelLabel)),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: danger ? AppColors.danger : AppColors.primary),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
