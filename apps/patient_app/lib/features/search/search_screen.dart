import 'dart:async';

import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:asani_ui/asani_ui.dart';
import '../../data/providers.dart';
import '../clinic/clinic_card.dart';
import '../../core/widgets/error_state.dart';

/// S-06 search: clinic name or area, filters as you type (250 ms debounce).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery = '', this.embedded = false});
  final String initialQuery;

  /// Inside the Clinics | Doctors tabs (D-31): the tab screen has the back button.
  final bool embedded;

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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kStatusBarDark,
      child: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.screen, Gap.sm),
              child: Row(children: [
                if (!widget.embedded) ...[
                  const HeaderBackButton(dark: true),
                  const SizedBox(width: Gap.sm),
                ],
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: widget.initialQuery.isEmpty,
                    textInputAction: TextInputAction.search,
                    style: AppText.bodyLarge,
                    onChanged: _onChanged,
                    // Board P2 S-06: cream field, rounded 14, green search icon.
                    decoration: InputDecoration(
                      hintText: 'Clinic name or area',
                      prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
                      filled: true,
                      fillColor: AppColors.cream,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
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
                          // Nothing in this city: offer cities where the search does match.
                          _OtherCities(query: _query, city: city),
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
                              '${results.length} ${results.length == 1 ? 'clinic' : 'clinics'} in $city',
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
    ));
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
        backgroundColor: AppColors.cream,
        side: BorderSide(color: selected ? AppColors.primary : AppColors.cream),
        shape: const StadiumBorder(),
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }
}

/// Empty search: other cities with matching clinics; tapping one switches the city.
class _OtherCities extends ConsumerWidget {
  const _OtherCities({required this.query, required this.city});
  final String query;
  final String city;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.trim().isEmpty) return const SizedBox.shrink();
    final cities = (ref.watch(citiesProvider).value ?? const <String>[]).where((c) => c != city);
    final hits = <(String, int)>[];
    for (final c in cities) {
      final n = (ref.watch(clinicsProvider(c)).value ?? const <Clinic>[]).where((x) => x.matches(query)).length;
      if (n > 0) hits.add((c, n));
    }
    if (hits.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(Gap.md),
      child: Column(children: [
        const Text('Found in other cities:'),
        Wrap(spacing: Gap.sm, children: [
          for (final (c, n) in hits)
            ActionChip(
              label: Text('$c ($n)'),
              onPressed: () => ref.read(authRepositoryProvider).setCity(c),
            ),
        ]),
      ]),
    );
  }
}
