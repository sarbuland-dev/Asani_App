/// Widgets of the Super Admin screens (board page "Super admin"). They build
/// on the clinic kit, so both sides share one look.
library;

import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/clinic_kit.dart';
import '../../data/models.dart';

/// Header bar (title, subtitle, clinic search) over a scrolling body.
class AdminPage extends StatelessWidget {
  const AdminPage({super.key, required this.title, this.subtitle, this.actions = const [], this.search = true, this.searchBox, required this.children});
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// The "Search clinic, phone or email" box that opens the clinics list.
  final bool search;

  /// A page with its own search (the clinics list) passes it here.
  final Widget? searchBox;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          decoration: const BoxDecoration(color: AppColors.background, border: Border(bottom: BorderSide(color: AppColors.border))),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ClinicText.pageTitle.copyWith(fontSize: 22)),
                if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: ClinicText.small),
              ]),
            ),
            if (searchBox != null) ...[const SizedBox(width: 14), searchBox!] else if (search) ...[const SizedBox(width: 14), const AdminSearch()],
            for (final a in actions) ...[const SizedBox(width: 12), a],
          ]),
        ),
        Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(28, 20, 28, 28), children: children)),
      ]);
}

/// Clinic search. "/" focuses it. Without [onChanged], Enter opens the
/// clinics list with the words typed.
class AdminSearch extends StatefulWidget {
  const AdminSearch({super.key, this.controller, this.onChanged});
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  @override
  State<AdminSearch> createState() => _AdminSearchState();
}

class _AdminSearchState extends State<AdminSearch> {
  late final _text = widget.controller ?? TextEditingController();
  final _focus = FocusNode(debugLabel: 'admin-search');

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _focus.dispose();
    if (widget.controller == null) _text.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted || e.logicalKey != LogicalKeyboardKey.slash) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    if (FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<EditableTextState>() != null) return false;
    _focus.requestFocus();
    return true;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 300,
        child: TextField(
          controller: _text,
          focusNode: _focus,
          style: ClinicText.body,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search clinic, phone or email',
            prefixIcon: Icon(Icons.search_rounded, size: 18, color: AppColors.textSecondary),
            suffixIcon: Padding(padding: EdgeInsets.only(right: 10), child: Center(widthFactor: 1, child: Kbd('/'))),
          ),
          onChanged: widget.onChanged,
          onSubmitted: (v) {
            if (widget.onChanged == null && v.trim().isNotEmpty) context.go('/admin/clinics?q=${Uri.encodeQueryComponent(v.trim())}');
          },
        ),
      );
}

/// Sand segmented control with a white active tab (board `.tabs`).
class AdminTabs<T> extends StatelessWidget {
  const AdminTabs({super.key, required this.values, required this.selected, required this.label, required this.onChanged});
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: ClinicColors.creamDeep, borderRadius: BorderRadius.circular(14)),
        child: Wrap(spacing: 4, runSpacing: 4, children: [
          for (final v in values)
            Semantics(
              selected: v == selected,
              button: true,
              child: Material(
                color: v == selected ? AppColors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onChanged(v),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(label(v),
                        style: AppText.labelMedium.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: v == selected ? AppColors.primary : AppColors.textSecondary)),
                  ),
                ),
              ),
            ),
        ]),
      );
}

/// A drop-down drawn as a white pill; null is the "all" choice.
class FilterDrop<T> extends StatelessWidget {
  const FilterDrop({super.key, required this.value, required this.items, required this.label, required this.allLabel, required this.onChanged});
  final T? value;
  final List<T> items;
  final String Function(T) label;
  final String allLabel;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
        tooltip: allLabel,
        // Index into [items]; -1 is "all" (a null value would not be reported).
        onSelected: (i) => onChanged(i < 0 ? null : items[i]),
        itemBuilder: (_) => [
          PopupMenuItem(value: -1, child: Text(allLabel)),
          for (var i = 0; i < items.length; i++) PopupMenuItem(value: i, child: Text(label(items[i]))),
        ],
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(ClinicRadii.control), border: Border.all(color: AppColors.border)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(value == null ? allLabel : label(value as T), overflow: TextOverflow.ellipsis, style: ClinicText.body),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more_rounded, size: 18, color: AppColors.textSecondary),
          ]),
        ),
      );
}

String clinicStatusLabel(ClinicStatus s) => switch (s) {
      ClinicStatus.pilot => 'Pilot',
      ClinicStatus.active => 'Active',
      ClinicStatus.grace => 'Grace',
      ClinicStatus.suspended => 'Suspended',
      ClinicStatus.cancelled => 'Cancelled',
    };

/// Colour of a status in the dashboard bar.
Color clinicStatusBar(ClinicStatus s) => switch (s) {
      ClinicStatus.active => AppColors.cream,
      ClinicStatus.pilot => AppColors.primarySoft,
      ClinicStatus.grace => ClinicColors.chartAmber,
      ClinicStatus.suspended => ClinicColors.chartRed,
      ClinicStatus.cancelled => ClinicColors.sideSection,
    };

const _blueFg = AppColors.infoDark;
const _blueBg = AppColors.infoContainer;

class ClinicStatusChip extends StatelessWidget {
  const ClinicStatusChip(this.status, {super.key});
  final ClinicStatus status;

  @override
  Widget build(BuildContext context) {
    final label = clinicStatusLabel(status);
    return switch (status) {
      ClinicStatus.active => CChip.green(label),
      ClinicStatus.pilot => CChip(label, fg: _blueFg, bg: _blueBg, dot: true),
      ClinicStatus.grace => CChip.amber(label),
      ClinicStatus.suspended => CChip.red(label),
      ClinicStatus.cancelled => CChip(label, dot: true),
    };
  }
}

class LoginChip extends StatelessWidget {
  const LoginChip(this.status, {super.key});
  final LoginStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
        LoginStatus.active => CChip.green(status.label),
        LoginStatus.invited => CChip.amber(status.label),
        LoginStatus.disabled => CChip(status.label, dot: true),
      };
}

class InvoiceChip extends StatelessWidget {
  const InvoiceChip(this.status, {super.key});
  final InvoiceStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
        InvoiceStatus.paid => CChip.green(status.label),
        InvoiceStatus.unpaid => CChip.amber(status.label),
        InvoiceStatus.overdue => CChip.red(status.label),
        InvoiceStatus.waived => CChip(status.label, dot: true),
      };
}

/// "Label ........ value" line inside a card.
class InfoLine extends StatelessWidget {
  const InfoLine(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: ClinicText.small),
          const SizedBox(width: 12),
          Expanded(child: Text(value, textAlign: TextAlign.right, style: AppText.labelMedium.copyWith(fontSize: 13))),
        ]),
      );
}

/// A rounded progress bar made of coloured parts.
class SplitBar extends StatelessWidget {
  const SplitBar(this.parts, {super.key, this.height = 8, this.gap = 0, this.track = AppColors.cream});
  final List<(int, Color)> parts;
  final double height;
  final double gap;
  final Color track;

  @override
  Widget build(BuildContext context) {
    final shown = parts.where((p) => p.$1 > 0).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: shown.isEmpty
            ? ColoredBox(color: track)
            : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (i, p) in shown.indexed) ...[
                  if (i > 0 && gap > 0) SizedBox(width: gap),
                  Expanded(flex: p.$1, child: DecoratedBox(decoration: BoxDecoration(color: p.$2, borderRadius: BorderRadius.circular(gap > 0 ? 6 : 0)))),
                ],
              ]),
      ),
    );
  }
}

/// Cards side by side with equal height.
class CardRow extends StatelessWidget {
  const CardRow({super.key, required this.children, this.flex, this.gap = 16});
  final List<Widget> children;
  final List<int>? flex;
  final double gap;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(flex: flex?[i] ?? 1, child: children[i]),
          ],
        ]),
      );
}
