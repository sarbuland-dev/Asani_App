import 'package:asani_core/asani_core.dart';
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
        appBar: AppBar(
          title: const Text('Search'),
          bottom: const TabBar(tabs: [Tab(text: 'Clinics'), Tab(text: 'Doctors')]),
        ),
        body: TabBarView(children: [
          SearchScreen(initialQuery: initialQuery, embedded: true),
          DoctorsTab(initialSpeciality: speciality),
        ]),
      ),
    );
  }
}
