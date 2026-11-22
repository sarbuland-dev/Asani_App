import 'package:asani_core/asani_core.dart';
import 'package:asani_ui/asani_ui.dart';
import 'package:flutter/material.dart';

import '../doctor_search/doctors_tab.dart';
import 'search_screen.dart';

/// Search, opened from the two Home cards (board P2 S-06, P3 S-06b; PRD D-31
/// as amended by D-49): "Search by clinic" → the clinic search screen,
/// "Search by doctor" (`/search?tab=doctors`) → the doctor search screen.
/// Two separate screens, no tabs.
class SearchTabsScreen extends StatelessWidget {
  const SearchTabsScreen({super.key, this.initialQuery = '', this.doctors = false, this.speciality});
  final String initialQuery;

  /// Open "Search by doctor" (`/search?tab=doctors`).
  final bool doctors;
  final Speciality? speciality;

  @override
  Widget build(BuildContext context) {
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
      ),
      body: DoctorsTab(initialSpeciality: speciality),
    );
  }
}
