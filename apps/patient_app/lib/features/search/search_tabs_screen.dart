import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';

import '../doctor_search/doctors_tab.dart';
import 'search_screen.dart';

/// Search, opened from the two Home cards (board P2 S-06, P3 S-06b; PRD D-31
/// as amended by D-49): "Search by clinic" → the clinic search screen,
/// "Search by doctor" (`/search?tab=doctors`) → the doctor search screen.
/// Two separate screens, no tabs; each draws its own green header.
class SearchTabsScreen extends StatelessWidget {
  const SearchTabsScreen({super.key, this.initialQuery = '', this.doctors = false, this.speciality});
  final String initialQuery;

  /// Open "Search by doctor" (`/search?tab=doctors`).
  final bool doctors;
  final Speciality? speciality;

  @override
  Widget build(BuildContext context) {
    if (!doctors) return SearchScreen(initialQuery: initialQuery);
    return Scaffold(body: DoctorsTab(initialSpeciality: speciality));
  }
}
