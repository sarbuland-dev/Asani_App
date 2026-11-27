/// Widgets of the clinic screens, drawn from the screens board. Import this
/// instead of `desktop.dart`: here `AppColors` is Deep forest.
library;

import 'package:asani_core/asani_core.dart';
import 'package:asani_ui/asani_ui.dart';
import 'package:flutter/material.dart';

import '../theme/clinic_theme.dart';
import 'desktop.dart' show TableColumn;

export 'package:asani_ui/asani_ui.dart';

export '../theme/clinic_theme.dart';
export 'desktop.dart' hide AppColors;

/// Text styles of the board that the shared scale does not have.
abstract final class ClinicText {
  static TextStyle get pageTitle => AppText.titleLarge.copyWith(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.3);
  static TextStyle get cardTitle => AppText.titleSmall.copyWith(fontSize: 17, fontWeight: FontWeight.w800);
  static TextStyle get body => AppText.bodyMedium.copyWith(color: AppColors.textPrimary);
  static TextStyle get small => AppText.labelSmall.copyWith(fontSize: 12);
  static TextStyle get caps => AppText.overline.copyWith(fontSize: 11, letterSpacing: 1.2);

  /// Big numbers: token codes, KPI values.
  static TextStyle big(double size, {Color color = AppColors.textPrimary}) =>
      AppText.titleLarge.copyWith(fontSize: size, fontWeight: FontWeight.w800, color: color, height: 1.1, letterSpacing: -size * 0.02);
}

/// A clinic page: optional header row, then scrolling content.
class ClinicPage extends StatelessWidget {
  const ClinicPage({super.key, required this.title, this.subtitle, this.leading, this.actions = const [], required this.children});
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
        children: [
          PageHeader(title: title, subtitle: subtitle, leading: leading, actions: actions),
          const SizedBox(height: 18),
          ...children,
        ],
      );
}

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.leading, this.actions = const []});
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Row(children: [
        if (leading != null) ...[leading!, const SizedBox(width: 14)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: ClinicText.pageTitle),
            if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: AppText.bodyMedium.copyWith(fontSize: 13))],
          ]),
        ),
        for (final a in actions) ...[const SizedBox(width: 10), a],
      ]);
}

/// White card with a sand border.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.color = AppColors.surface, this.borderColor = AppColors.border, this.radius = ClinicRadii.card, this.onTap, this.borderWidth = 1});
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final Color borderColor;
  final double radius;
  final double borderWidth;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final inner = Padding(padding: padding, child: child);
    return Material(
      color: color,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: BorderSide(color: borderColor, width: borderWidth)),
      child: onTap == null ? inner : InkWell(onTap: onTap, child: inner),
    );
  }
}

/// Dark green block with two thin rings in the top right corner.
class HeroBlock extends StatelessWidget {
  const HeroBlock({super.key, required this.child, this.padding = const EdgeInsets.all(22), this.radius = ClinicRadii.hero});
  final Widget child;
  final EdgeInsets padding;
  final double radius;

  Widget _ring(double size) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.onPrimary.withValues(alpha: 0.07))),
        ),
      );

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: ClinicColors.heroGradient),
          child: Stack(children: [
            Positioned(right: -150, top: -210, child: _ring(420)),
            Positioned(right: -80, top: -140, child: _ring(280)),
            Padding(padding: padding, child: child),
          ]),
        ),
      );
}

/// Small pill: status, source, count.
class CChip extends StatelessWidget {
  const CChip(this.label, {super.key, this.fg = AppColors.textSecondary, this.bg = AppColors.cream, this.dot = false, this.icon, this.fontSize = 12});

  const CChip.green(this.label, {super.key, this.dot = true, this.icon, this.fontSize = 12})
      : fg = AppColors.successText,
        bg = AppColors.successContainer;
  const CChip.amber(this.label, {super.key, this.dot = true, this.icon, this.fontSize = 12})
      : fg = AppColors.warningText,
        bg = AppColors.warningContainer;
  const CChip.red(this.label, {super.key, this.dot = true, this.icon, this.fontSize = 12})
      : fg = AppColors.dangerText,
        bg = AppColors.dangerContainer;
  const CChip.tint(this.label, {super.key, this.dot = false, this.icon, this.fontSize = 12})
      : fg = AppColors.primary,
        bg = ClinicColors.tint;

  /// On the dark hero.
  CChip.onDark(this.label, {super.key, this.dot = false, this.icon, this.fontSize = 12})
      : fg = AppColors.onPrimary,
        bg = AppColors.onPrimary.withValues(alpha: 0.12);

  final String label;
  final Color fg;
  final Color bg;
  final bool dot;
  final IconData? icon;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.pill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot) ...[Container(width: 7, height: 7, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)), const SizedBox(width: 5)],
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 5)],
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.labelSmall.copyWith(color: fg, fontSize: fontSize, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

/// Token status on the clinic screens. The text is always shown.
class TokenStatusChip extends StatelessWidget {
  const TokenStatusChip(this.status, {super.key});
  final TokenStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
        TokenStatus.booked => CChip(status.label, dot: true),
        TokenStatus.arrived => CChip.green(status.label),
        TokenStatus.called => CChip(status.label, fg: AppColors.infoDark, bg: AppColors.infoContainer, dot: true),
        TokenStatus.completed => CChip.tint(status.label, dot: true),
        TokenStatus.onHold || TokenStatus.skipped => CChip.amber(status.label),
        TokenStatus.cancelled || TokenStatus.noShow => CChip.red(status.label),
      };
}

/// Initials in a circle (or rounded square with [radius]).
class Av extends StatelessWidget {
  const Av(this.name, {super.key, this.size = 40, this.bg = ClinicColors.tint, this.fg = AppColors.primary, this.radius});
  const Av.solid(this.name, {super.key, this.size = 40, this.radius})
      : bg = AppColors.primary,
        fg = AppColors.onPrimary;

  final String name;
  final double size;
  final Color bg;
  final Color fg;
  final double? radius;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius ?? size)),
        child: Text(Fmt.initials(name),
            style: AppText.labelMedium.copyWith(color: fg, fontSize: size * 0.33, fontWeight: FontWeight.w800, height: 1)),
      );
}

/// Rounded square with an icon.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.size = 40, this.bg = ClinicColors.tint, this.fg = AppColors.primary});
  final IconData icon;
  final double size;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.3)),
        child: Icon(icon, color: fg, size: size * 0.5),
      );
}

/// Keyboard key hint.
class Kbd extends StatelessWidget {
  const Kbd(this.text, {super.key, this.onDark = false});
  final String text;
  final bool onDark;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 22),
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: onDark ? AppColors.onPrimary.withValues(alpha: 0.08) : AppColors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: onDark ? AppColors.onPrimary.withValues(alpha: 0.3) : AppColors.borderStrong),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(text,
              style: AppText.labelSmall.copyWith(fontSize: 11, fontWeight: FontWeight.w700, height: 1, color: onDark ? AppColors.onPrimary : AppColors.textSecondary)),
        ),
      );
}

/// Cream pill with one filled choice.
class SegmentedPill<T> extends StatelessWidget {
  const SegmentedPill({super.key, required this.values, required this.selected, required this.label, required this.onChanged, this.activeBg = AppColors.primary, this.activeFg = AppColors.onPrimary});
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  final Color activeBg;
  final Color activeFg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(Radii.pill)),
        child: Wrap(spacing: 4, runSpacing: 4, children: [
          for (final v in values)
            Semantics(
              selected: v == selected,
              button: true,
              child: Material(
                color: v == selected ? activeBg : Colors.transparent,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => onChanged(v),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                    child: Text(label(v),
                        style: AppText.labelMedium.copyWith(
                            fontWeight: v == selected ? FontWeight.w700 : FontWeight.w600, color: v == selected ? activeFg : AppColors.textSecondary)),
                  ),
                ),
              ),
            ),
        ]),
      );
}

/// Round filter chip: filled when selected, cream otherwise.
class FilterPill extends StatelessWidget {
  const FilterPill(this.label, {super.key, required this.selected, required this.onTap, this.leading});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? AppColors.primary : AppColors.cream,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (leading != null) ...[leading!, const SizedBox(width: 6)],
                Text(label, style: AppText.labelSmall.copyWith(fontWeight: FontWeight.w700, color: selected ? AppColors.onPrimary : AppColors.textPrimary)),
              ]),
            ),
          ),
        ),
      );
}

/// Table with small caps headers, for use inside a [Panel] with no padding.
class SimpleTable extends StatelessWidget {
  const SimpleTable({super.key, required this.columns, required this.rows, this.onTap, this.rowColor, this.empty, this.capsHeaders = true});

  /// False: headers as written ("Date"), as on the patient history (W-14).
  final bool capsHeaders;
  final List<TableColumn> columns;
  final List<List<Widget>> rows;
  final void Function(int index)? onTap;

  /// Highlight of one row (selected, next up).
  final Color? Function(int index)? rowColor;
  final Widget? empty;

  Widget _line(List<Widget> cells) => Row(children: [
        for (var i = 0; i < columns.length; i++)
          Expanded(
            flex: columns[i].flex,
            child: Align(
              alignment: columns[i].align == TextAlign.right ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(padding: const EdgeInsets.only(right: 12), child: cells[i]),
            ),
          ),
      ]);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: _line([
            for (final c in columns)
              capsHeaders
                  ? Text(c.label.toUpperCase(), style: ClinicText.caps)
                  : Text(c.label, style: AppText.labelSmall.copyWith(fontWeight: FontWeight.w600)),
          ]),
        ),
        if (rows.isEmpty) empty ?? Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('Nothing here yet.', style: AppText.bodyMedium))),
        for (var i = 0; i < rows.length; i++)
          Material(
            color: rowColor?.call(i) ?? Colors.transparent,
            child: InkWell(
              onTap: onTap == null ? null : () => onTap!(i),
              child: Container(
                decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: AppColors.cream))),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                child: _line(rows[i]),
              ),
            ),
          ),
      ]);
}

/// Label above a field (12 px bold, board style).
class LabeledField extends StatelessWidget {
  const LabeledField(this.label, {super.key, required this.child, this.help, this.required = false});
  final String label;
  final Widget child;
  final String? help;
  final bool required;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text.rich(
          TextSpan(text: label, children: [if (required) TextSpan(text: ' *', style: TextStyle(color: AppColors.danger))]),
          style: AppText.labelSmall.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        child,
        if (help != null) ...[const SizedBox(height: 6), Text(help!, style: ClinicText.small)],
      ]);
}

/// Coloured note box inside cards and dialogs.
class NoteBox extends StatelessWidget {
  const NoteBox(this.text, {super.key, this.fg = AppColors.warningText, this.bg = AppColors.warningContainer, this.icon, this.action});
  const NoteBox.error(this.text, {super.key, this.icon, this.action})
      : fg = AppColors.dangerText,
        bg = AppColors.dangerContainer;
  const NoteBox.tint(this.text, {super.key, this.icon, this.action})
      : fg = AppColors.primary,
        bg = ClinicColors.tint;

  final String text;
  final Color fg;
  final Color bg;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(ClinicRadii.control)),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 10)],
          Expanded(child: Text(text, style: AppText.bodyMedium.copyWith(color: fg, fontSize: 13))),
          if (action != null) ...[const SizedBox(width: 10), action!],
        ]),
      );
}

/// A tear line with half-circle notches, between the parts of a token slip.
/// [notch] is the colour behind the slip.
class TearLine extends StatelessWidget {
  const TearLine({super.key, required this.notch});
  final Color notch;

  Widget _hole() => Container(width: 20, height: 20, decoration: BoxDecoration(color: notch, shape: BoxShape.circle));

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 20,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          const Padding(padding: EdgeInsets.symmetric(horizontal: 18), child: DashedLine(color: AppColors.borderStrong)),
          Positioned(left: -10, child: _hole()),
          Positioned(right: -10, child: _hole()),
        ]),
      );
}

/// Green dot with a slow ping: the page is live.
class LiveDot extends StatefulWidget {
  const LiveDot({super.key});

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
    const dot = DecoratedBox(decoration: BoxDecoration(color: ClinicColors.live, shape: BoxShape.circle), child: SizedBox.square(dimension: 8));
    return SizedBox.square(
      dimension: 8,
      child: Stack(clipBehavior: Clip.none, children: [
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            child: dot,
            builder: (_, child) => Opacity(opacity: (1 - _c.value) * 0.6, child: Transform.scale(scale: 1 + _c.value * 2, child: child)),
          ),
        ),
        dot,
      ]),
    );
  }
}

/// W-24: a button label that swaps to the logo loader and an "…ing" text.
class BusyLabel extends StatelessWidget {
  const BusyLabel({super.key, required this.busy, required this.busyText, required this.child, this.color = AppColors.onPrimary});
  final bool busy;
  final String busyText;
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => busy
      ? Row(mainAxisSize: MainAxisSize.min, children: [
          AsaniLoader(size: 22, color: color),
          const SizedBox(width: 10),
          Flexible(child: Text(busyText, overflow: TextOverflow.ellipsis, style: TextStyle(color: color))),
        ])
      : child;
}

/// Shimmering block that keeps a card's shape while it loads (W-24).
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.height});
  final double height;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ClinicRadii.card),
          gradient: LinearGradient(
            begin: Alignment(-3 + 4 * _c.value, 0),
            end: Alignment(-1 + 4 * _c.value, 0),
            colors: const [ClinicColors.creamDeep, ClinicColors.quiet, ClinicColors.creamDeep],
          ),
        ),
      ),
    );
  }
}
