import 'package:asani_core/asani_core.dart';
import 'package:asani_ui/asani_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../doctor_search/doctors_tab.dart';
import '../home/home_screen.dart' show showCityPicker;
import 'search_screen.dart';

/// Search, opened from the two Home cards (board P2 S-06, P3 S-06b; PRD D-31
/// as amended by D-49): "Search by clinic" → the clinic search screen,
/// "Search by doctor" (`/search?tab=doctors`) → the doctor search screen.
/// Two separate screens, no tabs.
class SearchTabsScreen extends ConsumerWidget {
  const SearchTabsScreen({super.key, this.initialQuery = '', this.doctors = false, this.speciality});
  final String initialQuery;

  /// Open "Search by doctor" (`/search?tab=doctors`).
  final bool doctors;
  final Speciality? speciality;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Clinic search has its own header and back button.
    if (!doctors) return SearchScreen(initialQuery: initialQuery);
    return Scaffold(
      // Board P3 S-06b: green header "Search by doctor".
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        systemOverlayStyle: kStatusBarLight,
        titleTextStyle: AppText.titleMedium.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w700),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(Radii.header))),
        title: const Text('Search by doctor'),
        // D-50: city chip + one line under the title, as on the board.
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ActionChip(
              label: Text('${ref.watch(selectedCityProvider)} ▾'),
              onPressed: () => showCityPicker(context, ref),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(32),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Pick a speciality to see doctors near you',
                  style: AppText.labelSmall.copyWith(color: AppColors.onPrimaryMuted, fontSize: 13)),
            ),
          ),
        ),
      ),
      body: DoctorsTab(initialSpeciality: speciality),
    );
  }
}
