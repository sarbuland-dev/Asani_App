import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GradientHeader(
            child: Row(children: [
              const HeaderBackButton(),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text(existing == null ? 'Add family member' : 'Edit profile',
                    style: AppText.titleLarge.copyWith(color: AppColors.onPrimary)),
              ),
            ]),
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
