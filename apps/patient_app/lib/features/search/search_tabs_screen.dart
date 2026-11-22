import 'package:asani_core/asani_core.dart';
import 'package:asani_ui/asani_ui.dart';
import 'package:flutter/material.dart';

import '../doctor_search/doctors_tab.dart';
import 'search_screen.dart';

/// Search with two tabs, Clinics | Doctors (PRD D-31). Plain placeholder shell.
class SearchTabsScreen extends StatelessWidget {
  const SearchTabsScreen({super.key, this.initialQuery = '', this.doctors = false, this.speciality});
  final String initialQuery;

  /// Open on the Doctors tab (`/search?tab=doctors`).
  final bool doctors;
  final Speciality? speciality;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: doctors ? 1 : 0,
      child: Scaffold(
        // Board P2 S-06: green header; cream tab indicator.
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          systemOverlayStyle: kStatusBarLight,
          titleTextStyle: AppText.titleMedium.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w700),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(Radii.header))),
          title: const Text('Search'),
          bottom: TabBar(
            labelColor: AppColors.onPrimary,
            unselectedLabelColor: AppColors.primarySoft,
            labelStyle: AppText.labelLarge,
            indicatorColor: AppColors.onPrimary,
            indicatorWeight: 3,
            dividerColor: Colors.transparent,
            tabs: const [Tab(text: 'Clinics'), Tab(text: 'Doctors')],
          ),
        ),
        body: TabBarView(children: [
          SearchScreen(initialQuery: initialQuery, embedded: true),
          DoctorsTab(initialSpeciality: speciality),
        ]),
      ),
    );
  }
}
