import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import 'package:asani_ui/asani_ui.dart';
import '../../data/providers.dart';
import 'profile_form.dart';

/// S-14 add / edit family member.
class ProfileFormScreen extends ConsumerWidget {
  const ProfileFormScreen({super.key, this.patientId});
  final String? patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patients = ref.watch(myPatientsProvider).value;
    final existing = patientId == null ? null : patients?.where((p) => p.id == patientId).firstOrNull;
    if (patientId != null && existing == null) {
      return const LoadingScreen();
    }
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Board P6 S-14: green header with close and the centred title.
          Container(
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(Radii.header)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, Gap.sm, 20, 18),
                child: Row(children: [
                  const HeaderBackButton(icon: Icons.close_rounded),
                  Expanded(
                    child: Text(existing == null ? 'Add family member' : 'Edit profile',
                        textAlign: TextAlign.center,
                        style: AppText.labelLarge.copyWith(color: AppColors.onPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 44),
                ]),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Gap.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProfileForm(
                    existing: existing,
                    onSaved: (p) {
                      showSnack(context, existing == null ? '${p.name} added.' : 'Profile saved.');
                      context.pop(p);
                    },
                  ),
                  if (existing != null && !existing.isSelf) ...[
                    const SizedBox(height: Gap.md),
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                      onPressed: () async {
                        final ok = await confirmDialog(
                          context,
                          title: 'Remove ${existing.name}?',
                          message: 'You will not be able to book for this profile. Past visits stay with the clinic.',
                          confirmLabel: 'Remove',
                          danger: true,
                        );
                        if (!ok || !context.mounted) return;
                        try {
                          await ref.read(patientRepositoryProvider).removePatient(existing.id);
                          if (context.mounted) context.go('/family');
                        } catch (e) {
                          if (context.mounted) showSnack(context, AppException.messageOf(e));
                        }
                      },
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Remove profile'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
