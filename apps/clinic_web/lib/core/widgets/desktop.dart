import 'dart:async';

import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../errors/app_exception.dart';
import 'package:asani_ui/asani_ui.dart';

export 'package:asani_ui/asani_ui.dart';
export 'error_state.dart';

/// Standard page: title row with actions, then content.
class PageScaffold extends StatelessWidget {
  const PageScaffold({super.key, required this.title, this.subtitle, this.actions = const [], required this.child, this.scroll = true, this.leading});
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;
  final bool scroll;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xxl, Gap.xl, Gap.xxl, Gap.lg),
      child: Row(children: [
        if (leading != null) ...[leading!, const SizedBox(width: Gap.md)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppText.displaySmall.copyWith(fontSize: 26)),
            if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: AppText.bodyMedium)],
          ]),
        ),
        for (final a in actions) ...[const SizedBox(width: Gap.sm), a],
      ]),
    );
    final body = Padding(padding: const EdgeInsets.fromLTRB(Gap.xxl, 0, Gap.xxl, Gap.xxl), child: child);
    if (!scroll) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, Expanded(child: body)]);
    return SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, body]));
  }
}

/// Number card for dashboards and summaries.
class KpiCard extends StatelessWidget {
  const KpiCard({super.key, required this.label, required this.value, required this.icon, this.fg = AppColors.primary, this.bg = AppColors.primaryContainer, this.hint, this.onTap, this.danger = false});
  final String label;
  final String value;
  final IconData icon;
  final Color fg;
  final Color bg;
  final String? hint;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      color: danger ? AppColors.dangerContainer : AppColors.surface,
      borderColor: danger ? AppColors.danger.withValues(alpha: 0.3) : AppColors.border,
      child: Row(children: [
        IconBox(icon: icon, bg: danger ? AppColors.surface : bg, fg: danger ? AppColors.danger : fg, size: 48),
        const SizedBox(width: Gap.lg),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: AppText.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(value, style: AppText.titleLarge.copyWith(fontWeight: FontWeight.w800, color: danger ? AppColors.danger : AppColors.textPrimary)),
            if (hint != null) Text(hint!, style: AppText.labelSmall.copyWith(color: AppColors.textMuted)),
          ]),
        ),
      ]),
    );
  }
}

/// Grid of cards that wraps by available width.
class CardGrid extends StatelessWidget {
  const CardGrid({super.key, required this.children, this.minWidth = 240, this.spacing = Gap.lg});
  final List<Widget> children;
  final double minWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final cols = (c.maxWidth / minWidth).floor().clamp(1, children.length.clamp(1, 6));
        final w = (c.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(spacing: spacing, runSpacing: spacing, children: [for (final ch in children) SizedBox(width: w, child: ch)]);
      });
}

class TableColumn {
  const TableColumn(this.label, {this.flex = 1, this.align = TextAlign.left});
  final String label;
  final int flex;
  final TextAlign align;
}

/// Wide table inside a card (lists of clinics, staff, invoices …).
class AppTable extends StatelessWidget {
  const AppTable({super.key, required this.columns, required this.rows, this.onTap, this.empty});
  final List<TableColumn> columns;
  final List<List<Widget>> rows;
  final void Function(int index)? onTap;
  final Widget? empty;

  Widget _cell(TableColumn c, Widget child) => Expanded(
        flex: c.flex,
        child: Align(
          alignment: c.align == TextAlign.right ? Alignment.centerRight : (c.align == TextAlign.center ? Alignment.center : Alignment.centerLeft),
          child: Padding(padding: const EdgeInsets.only(right: Gap.md), child: child),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: AppColors.muted,
          padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
          child: Row(children: [
            for (final c in columns) _cell(c, Text(c.label.toUpperCase(), style: AppText.overline.copyWith(fontSize: 11, letterSpacing: 0.8))),
          ]),
        ),
        if (rows.isEmpty) empty ?? const Padding(padding: EdgeInsets.all(Gap.xl), child: Center(child: Text('Nothing here yet.'))),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(),
          InkWell(
            onTap: onTap == null ? null : () => onTap!(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
              child: Row(children: [for (var j = 0; j < columns.length; j++) _cell(columns[j], rows[i][j])]),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Two-line cell: bold main text + small secondary line.
class TwoLine extends StatelessWidget {
  const TwoLine(this.title, this.subtitle, {super.key});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(title, style: AppText.labelMedium, overflow: TextOverflow.ellipsis),
        if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!, style: AppText.labelSmall, overflow: TextOverflow.ellipsis),
      ]);
}

/// Doctor letter badge (A, B, C…).
class LetterBadge extends StatelessWidget {
  const LetterBadge(this.letter, {super.key, this.size = 36, this.inverted = false});
  final String letter;
  final double size;
  final bool inverted;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: inverted ? AppColors.onPrimary.withValues(alpha: 0.2) : AppColors.primaryContainer,
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: Text(letter,
            style: AppText.labelLarge.copyWith(color: inverted ? AppColors.onPrimary : AppColors.primary, fontWeight: FontWeight.w800, fontSize: size * 0.45)),
      );
}

class SessionPill extends StatelessWidget {
  const SessionPill(this.status, {super.key, this.onDark = false});
  final SessionStatus status;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = switch (status) {
      SessionStatus.notStarted => ('Not started', AppColors.textSecondary, AppColors.muted),
      SessionStatus.running => ('Running', AppColors.success, AppColors.successContainer),
      SessionStatus.paused => ('Paused', AppColors.warning, AppColors.warningContainer),
      SessionStatus.ended => ('Ended', AppColors.textSecondary, AppColors.muted),
    };
    return Pill(label: label, fg: fg, bg: bg, dot: true);
  }
}

class SourcePill extends StatelessWidget {
  const SourcePill(this.source, {super.key});
  final TokenSource source;

  @override
  Widget build(BuildContext context) => source == TokenSource.app
      ? const Pill(label: 'App', fg: AppColors.secondary, bg: AppColors.avatarCool, icon: Icons.phone_iphone_rounded)
      : const Pill(label: 'Walk-in', fg: AppColors.textSecondary, bg: AppColors.muted, icon: Icons.directions_walk_rounded);
}

class ClinicStatusPill extends StatelessWidget {
  const ClinicStatusPill(this.status, {super.key});
  final ClinicStatus status;

  static (String, Color, Color) style(ClinicStatus s) => switch (s) {
        ClinicStatus.pilot => ('Pilot', AppColors.info, AppColors.infoContainer),
        ClinicStatus.active => ('Active', AppColors.success, AppColors.successContainer),
        ClinicStatus.grace => ('Grace', AppColors.warning, AppColors.warningContainer),
        ClinicStatus.suspended => ('Suspended', AppColors.danger, AppColors.dangerContainer),
        ClinicStatus.cancelled => ('Cancelled', AppColors.textSecondary, AppColors.muted),
      };

  @override
  Widget build(BuildContext context) {
    final (l, fg, bg) = style(status);
    return Pill(label: l, fg: fg, bg: bg, dot: true);
  }
}

class InvoicePill extends StatelessWidget {
  const InvoicePill(this.status, {super.key});
  final InvoiceStatus status;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (status) {
      InvoiceStatus.unpaid => (AppColors.warning, AppColors.warningContainer),
      InvoiceStatus.overdue => (AppColors.danger, AppColors.dangerContainer),
      InvoiceStatus.paid => (AppColors.success, AppColors.successContainer),
      InvoiceStatus.waived => (AppColors.textSecondary, AppColors.muted),
    };
    return Pill(label: status.label, fg: fg, bg: bg, dot: true);
  }
}

class LoginStatusPill extends StatelessWidget {
  const LoginStatusPill(this.status, {super.key});
  final LoginStatus status;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (status) {
      LoginStatus.invited => (AppColors.info, AppColors.infoContainer),
      LoginStatus.active => (AppColors.success, AppColors.successContainer),
      LoginStatus.disabled => (AppColors.textSecondary, AppColors.muted),
    };
    return Pill(label: status.label, fg: fg, bg: bg, dot: true);
  }
}

class FollowUpPill extends StatelessWidget {
  const FollowUpPill(this.status, {super.key});
  final FollowUpStatus status;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (status) {
      FollowUpStatus.pending => (AppColors.warning, AppColors.warningContainer),
      FollowUpStatus.booked => (AppColors.info, AppColors.infoContainer),
      FollowUpStatus.done => (AppColors.success, AppColors.successContainer),
      FollowUpStatus.missed => (AppColors.danger, AppColors.dangerContainer),
    };
    return Pill(label: status.label, fg: fg, bg: bg, dot: true);
  }
}

/// Coloured banner strip (grace, suspended, read-only, info).
class Banner2 extends StatelessWidget {
  const Banner2({super.key, required this.text, this.icon = Icons.info_outline_rounded, this.fg = AppColors.warning, this.bg = AppColors.warningContainer, this.action});
  final String text;
  final IconData icon;
  final Color fg;
  final Color bg;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.button)),
        child: Row(children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: Gap.md),
          Expanded(child: Text(text, style: AppText.labelMedium.copyWith(color: fg))),
          ?action,
        ]),
      );
}

/// Standard dialog frame: title, body, actions; fixed width for desktop.
class AppDialog extends StatelessWidget {
  const AppDialog({super.key, required this.title, required this.child, this.actions = const [], this.width = 520, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(Gap.xl),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.md, Gap.sm),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: AppText.titleLarge),
                  if (subtitle != null) Text(subtitle!, style: AppText.bodyMedium),
                ]),
              ),
              IconButton(tooltip: 'Close (Esc)', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.sm, Gap.xl, Gap.lg), child: child)),
          if (actions.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.md, Gap.xl, Gap.lg),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: Gap.sm), actions[i]],
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Label above a field, for forms.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, required this.child});
  final String text;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: AppText.labelMedium.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          child,
        ]),
      );
}

/// Runs [action]; shows its error in a snackbar. Returns true on success.
Future<bool> runAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await showBusyWhile(context, action);
    if (success != null && context.mounted) showSnack(context, success);
    return true;
  } catch (e) {
    if (context.mounted) showSnack(context, AppException.messageOf(e));
    return false;
  }
}

/// Shows a centred circular progress card ("Please wait…") over the whole
/// app while [work] talks to the backend, and blocks other clicks. Appears
/// only after 250 ms, so quick actions don't flicker.
Future<T> showBusyWhile<T>(BuildContext context, Future<T> Function() work, {String message = 'Please wait…'}) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  OverlayEntry? entry;
  final timer = Timer(const Duration(milliseconds: 250), () {
    if (overlay == null || !overlay.mounted) return;
    entry = OverlayEntry(builder: (_) => _BusyOverlay(message: message));
    overlay.insert(entry!);
  });
  try {
    return await work();
  } finally {
    timer.cancel();
    entry?.remove();
  }
}

class _BusyOverlay extends StatelessWidget {
  const _BusyOverlay({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Stack(children: [
        const ModalBarrier(dismissible: false, color: Color(0x33000000)),
        Center(
          child: Material(
            color: AppColors.surface,
            elevation: 8,
            borderRadius: BorderRadius.circular(Radii.card),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.xl, vertical: Gap.lg),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const AsaniLoader(size: 32),
                const SizedBox(width: Gap.lg),
                Text(message, style: AppText.titleMedium),
              ]),
            ),
          ),
        ),
      ]);
}

/// Asks for a short reason (cancel, waive, suspend). Null = dismissed.
Future<String?> askReason(BuildContext context, {required String title, required List<String> options, String confirmLabel = 'Confirm', bool danger = true, String? note}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _ReasonDialog(title: title, options: options, confirmLabel: confirmLabel, danger: danger, note: note),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.options, required this.confirmLabel, required this.danger, this.note});
  final String title;
  final List<String> options;
  final String confirmLabel;
  final bool danger;
  final String? note;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  late String _choice = widget.options.first;
  final _other = TextEditingController();

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOther = _choice == 'Other';
    final reason = isOther ? _other.text.trim() : _choice;
    return AppDialog(
      title: widget.title,
      width: 440,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
        FilledButton(
          style: widget.danger ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: reason.isEmpty ? null : () => Navigator.pop(context, reason),
          child: Text(widget.confirmLabel),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Reason', style: AppText.labelMedium.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: Gap.sm),
        Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
          for (final o in widget.options) ChoiceChip(label: Text(o), selected: _choice == o, onSelected: (_) => setState(() => _choice = o)),
        ]),
        if (isOther) ...[
          const SizedBox(height: Gap.md),
          TextField(controller: _other, autofocus: true, maxLength: 80, decoration: const InputDecoration(hintText: 'Short reason'), onChanged: (_) => setState(() {})),
        ],
        if (widget.note != null) ...[
          const SizedBox(height: Gap.md),
          Text(widget.note!, style: AppText.labelSmall),
        ],
      ]),
    );
  }
}
