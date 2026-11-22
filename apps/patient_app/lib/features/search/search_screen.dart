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
  Timer? _debounce;

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
    final all = clinicsAsync.value ?? const <Clinic>[];
    final areas = (all.map((c) => c.area).toSet().toList()..sort());
    // D-50 "Recent": clinics this account booked before, latest first.
    final recent = (ref.watch(recentClinicsProvider).value ?? const <Clinic>[]).take(3).toList();
    final q = _query.trim();
    final results = all.where((c) => c.matches(_query)).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kStatusBarLight,
      child: Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Board P2 S-06 (D-50): back button + cream field inside the green header.
            Container(
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(Radii.header)),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.screen, Gap.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const HeaderBackButton(),
                const SizedBox(width: Gap.sm),
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
              const SizedBox(height: Gap.sm),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text('Clinics in $city · type a clinic name or area',
                    style: AppText.labelSmall.copyWith(color: AppColors.onPrimaryMuted, fontSize: 13)),
              ),
              ]),
                ),
              ),
            ),
            if (recent.isNotEmpty)
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Gap.screen, vertical: Gap.sm),
                  children: [
                    Center(child: Text('Recent', style: AppText.labelMedium.copyWith(color: AppColors.textSecondary))),
                    const SizedBox(width: Gap.sm),
                    for (final c in recent)
                      Padding(
                        padding: const EdgeInsets.only(right: Gap.sm),
                        child: ActionChip(
                          label: Text(c.name),
                          backgroundColor: AppColors.cream,
                          side: const BorderSide(color: AppColors.cream),
                          shape: const StadiumBorder(),
                          onPressed: () => _setQuery(c.name),
                        ),
                      ),
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
                                  onPressed: () => _setQuery(a),
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
                              q.isEmpty
                                  ? '${results.length} ${results.length == 1 ? 'clinic' : 'clinics'} in $city'
                                  : "${results.length} ${results.length == 1 ? 'clinic matches' : 'clinics match'} '$q'",
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
    ));
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
