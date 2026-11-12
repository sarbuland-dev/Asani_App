import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../features/admin/activity_screen.dart';
import '../../features/admin/admin_settings_screen.dart';
import '../../features/admin/clinic_detail_screen.dart';
import '../../features/admin/clinics_screen.dart';
import '../../features/admin/dashboard_screen.dart';
import '../../features/admin/defaulters_screen.dart';
import '../../features/admin/new_clinic_screen.dart';
import '../../features/admin/payments_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/billing/billing_screen.dart';
import '../../features/doctors/doctors_screen.dart';
import '../../features/followups/follow_ups_screen.dart';
import '../../features/help/help_screen.dart';
import '../../features/patients/patient_profile_screen.dart';
import '../../features/patients/patients_screen.dart';
import '../../features/queue/queue_board_screen.dart';
import '../../features/settings/clinic_settings_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/staff/staff_screen.dart';
import '../../features/summary/summary_screen.dart';

/// Where each role lands after login (§5.3).
String homeFor(StaffAccount? u) => switch (u?.role) {
      null => '/login',
      StaffRole.superAdmin => '/admin',
      _ => '/queue',
    };

/// Clinic pages only the Clinic Admin may open (§4.2).
const _adminOnly = ['/doctors', '/staff', '/settings', '/billing'];

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(currentUserProvider, (prev, next) {
    if (prev?.uid != next?.uid || prev?.role != next?.role) refresh.value++;
  });
  ref.onDispose(refresh.dispose);

  NoTransitionPage<void> page(Widget child) => NoTransitionPage(child: child);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: (context, state) {
      final user = ref.read(currentUserProvider);
      final path = state.uri.path;
      if (user == null) return path == '/login' ? null : '/login';
      if (path == '/login' || path == '/') return homeFor(user);
      final isAdminArea = path.startsWith('/admin');
      if (user.role == StaffRole.superAdmin) return isAdminArea ? null : '/admin';
      if (isAdminArea) return '/queue';
      if (user.clinicId == null) return '/login';
      if (_adminOnly.any(path.startsWith) && user.role != StaffRole.clinicAdmin) return '/queue';
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (c, s) => '/login'),
      GoRoute(path: '/login', pageBuilder: (c, s) => page(const LoginScreen())),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/queue', pageBuilder: (c, s) => page(ClinicScope(builder: (id) => QueueBoardScreen(id)))),
          GoRoute(path: '/patients', pageBuilder: (c, s) => page(ClinicScope(builder: (id) => PatientsScreen(id)))),
          GoRoute(
            path: '/patients/:id',
            pageBuilder: (c, s) => page(ClinicScope(builder: (id) => PatientProfileScreen(clinicId: id, patientId: s.pathParameters['id']!))),
          ),
          GoRoute(path: '/follow-ups', pageBuilder: (c, s) => page(ClinicScope(builder: (id) => FollowUpsScreen(id)))),
          GoRoute(path: '/summary', pageBuilder: (c, s) => page(ClinicScope(builder: (id) => SummaryScreen(id)))),
          GoRoute(path: '/doctors', pageBuilder: (c, s) => page(ClinicScope(builder: (id) => DoctorsScreen(id)))),
          GoRoute(path: '/staff', pageBuilder: (c, s) => page(ClinicScope(builder: (id) => StaffScreen(id)))),
          GoRoute(path: '/settings', pageBuilder: (c, s) => page(ClinicScope(builder: (id) => ClinicSettingsScreen(id)))),
          GoRoute(path: '/billing', pageBuilder: (c, s) => page(ClinicScope(builder: (id) => BillingScreen(id)))),
          GoRoute(path: '/help', pageBuilder: (c, s) => page(const HelpScreen())),
          // Super admin (§7)
          GoRoute(path: '/admin', pageBuilder: (c, s) => page(const AdminDashboardScreen())),
          GoRoute(path: '/admin/clinics', pageBuilder: (c, s) => page(ClinicsScreen(initialStatus: s.uri.queryParameters['status']))),
          GoRoute(path: '/admin/clinics/new', pageBuilder: (c, s) => page(const NewClinicScreen())),
          GoRoute(path: '/admin/clinics/:id', pageBuilder: (c, s) => page(ClinicDetailScreen(clinicId: s.pathParameters['id']!))),
          GoRoute(
            path: '/admin/clinics/:id/queue',
            pageBuilder: (c, s) => page(QueueBoardScreen(s.pathParameters['id']!, readOnly: true)),
          ),
          GoRoute(path: '/admin/payments', pageBuilder: (c, s) => page(const PaymentsScreen())),
          GoRoute(path: '/admin/defaulters', pageBuilder: (c, s) => page(const DefaultersScreen())),
          GoRoute(path: '/admin/activity', pageBuilder: (c, s) => page(const ActivityScreen())),
          GoRoute(path: '/admin/settings', pageBuilder: (c, s) => page(const AdminSettingsScreen())),
        ],
      ),
    ],
    errorPageBuilder: (c, s) => page(const Scaffold(body: Center(child: Text('Page not found')))),
  );
});

/// Gives a clinic page the logged-in staff member's clinic id.
class ClinicScope extends ConsumerWidget {
  const ClinicScope({super.key, required this.builder});
  final Widget Function(String clinicId) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(currentUserProvider)?.clinicId;
    if (id == null) return const SizedBox.shrink();
    return builder(id);
  }
}
