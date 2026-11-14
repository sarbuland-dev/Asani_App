import 'dart:async';

import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:asani_ui/asani_ui.dart';
import '../../data/providers.dart';
import '../clinic/clinic_card.dart';
import '../../core/widgets/error_state.dart';

/// S-06 search: clinic name or area, filters as you type (250 ms debounce).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery = ''});
  final String initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final _controller = TextEditingController(text: widget.initialQuery);
  late String _query = widget.initialQuery;
  String? _filter; // null = All, '__open' = Open today, otherwise an area
  Timer? _debounce;

  static const _openToday = '__open';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => setState(() => _query = v));
    setState(() {}); // update clear button
  }

  void _setQuery(String q) {
    _controller.text = q;
    setState(() => _query = q);
  }

  @override
  Widget build(BuildContext context) {
    final city = ref.watch(selectedCityProvider);
    final clinicsAsync = ref.watch(clinicsProvider(city));
    final byClinic = ref.watch(doctorsByClinicProvider).value ?? const {};
    final now = pktNow();
    final all = clinicsAsync.value ?? const <Clinic>[];
    final areas = (all.map((c) => c.area).toSet().toList()..sort());

    final results = all.where((c) {
      if (!c.matches(_query)) return false;
      if (_filter == _openToday) return clinicOpenInfo(byClinic[c.id] ?? const [], now).open; // D-27: open now
      if (_filter != null) return c.area == _filter;
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.screen, Gap.sm),
              child: Row(children: [
                const HeaderBackButton(dark: true),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: widget.initialQuery.isEmpty,
                    textInputAction: TextInputAction.search,
                    style: AppText.bodyLarge,
                    onChanged: _onChanged,
                    decoration: InputDecoration(
                      hintText: 'Search clinic or area',
                      prefixIcon: const Icon(Icons.search_rounded),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.pill)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(Radii.pill), borderSide: const BorderSide(color: AppColors.primary)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(Radii.pill),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.6)),
                      suffixIcon: _controller.text.isEmpty
                          ? null
                          : IconButton(tooltip: 'Clear', icon: const Icon(Icons.close_rounded), onPressed: () => _setQuery('')),
                    ),
                  ),
                ),
              ]),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Gap.screen, vertical: Gap.sm),
                children: [
                  _chip('All', null),
                  _chip('Open now', _openToday, dot: true),
                  for (final a in areas) _chip(a, a),
                ],
              ),
            ),
            Expanded(
              child: clinicsAsync.when(
                loading: () => const Padding(padding: EdgeInsets.all(Gap.screen), child: SkeletonList()),
                error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(clinicsProvider(city))),
                data: (_) => results.isEmpty
                    ? SingleChildScrollView(
                        child: Column(children: [
                          EmptyState(
                            icon: Icons.search_off_rounded,
                            title: _query.trim().isEmpty ? 'No clinics match' : "No clinic found for '${_query.trim()}'",
                            message: 'Check the spelling, or search by area name.',
                          ),
                          Wrap(
                            spacing: Gap.sm,
                            runSpacing: Gap.sm,
                            alignment: WrapAlignment.center,
                            children: [
                              for (final a in areas)
                                ActionChip(
                                  label: Text(a),
                                  onPressed: () {
                                    setState(() => _filter = null);
                                    _setQuery(a);
                                  },
                                ),
                            ],
                          ),
                        ]),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.sm, Gap.screen, Gap.xl),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: Gap.md),
                            child: Text(
                              '${results.length} ${results.length == 1 ? 'clinic' : 'clinics'} found',
                              style: AppText.bodyMedium,
                            ),
                          ),
                          for (final c in results) ClinicCard(clinic: c, highlight: _query),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String? value, {bool dot = false}) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: Gap.sm),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        avatar: dot ? Container(width: 8, height: 8, decoration: BoxDecoration(color: selected ? AppColors.onPrimary : AppColors.success, shape: BoxShape.circle)) : null,
        labelStyle: AppText.labelMedium.copyWith(color: selected ? AppColors.onPrimary : AppColors.textPrimary),
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.surface,
        side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
        shape: const StadiumBorder(),
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }
}
