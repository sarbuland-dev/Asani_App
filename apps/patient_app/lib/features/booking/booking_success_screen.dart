import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:asani_ui/asani_ui.dart';
import 'package:asani_core/asani_core.dart';
import '../../data/providers.dart';
import '../token/token_slip.dart';

/// 09b Booking success (UI design).
class BookingSuccessScreen extends ConsumerWidget {
  const BookingSuccessScreen({super.key, required this.tokenId});
  final String tokenId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final token = ref.watch(tokenProvider(tokenId)).value;
    final doctor = token == null ? null : ref.watch(doctorProvider(token.doctorId)).value;
    final clinic = token == null ? null : ref.watch(clinicProvider(token.clinicId)).value;
    if (token == null || doctor == null || clinic == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final schedule = doctor.scheduleOn(DateTime.parse(token.date));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: HeaderBackButton(dark: true, icon: Icons.close_rounded, onPressed: () => context.go('/home')),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
                children: [
                  Center(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.6, end: 1),
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.elasticOut,
                      builder: (_, s, child) => Transform.scale(scale: s, child: child),
                      child: Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryContainer.withValues(alpha: 0.6)),
                        alignment: Alignment.center,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
                          child: const Icon(Icons.check_rounded, color: AppColors.onPrimary, size: 44),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: Gap.xl),
                  Text('Token booked!', textAlign: TextAlign.center, style: AppText.titleLarge.copyWith(fontSize: 26)),
                  const SizedBox(height: Gap.sm),
                  Text(token.label, textAlign: TextAlign.center, style: AppText.tokenDisplay),
                  const SizedBox(height: Gap.sm),
                  Text(
                    '${doctor.name} · ${Fmt.relativeDay(token.date).split(',').first}${schedule == null ? '' : ', ${Fmt.timeRangeShort(schedule)}'}',
                    textAlign: TextAlign.center,
                    style: AppText.bodyMedium.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: Gap.xl),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
                    child: TokenSlip(token: token, clinic: clinic, doctor: doctor, compact: true),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Gap.screen),
              child: Column(children: [
                FilledButton.icon(
                  onPressed: () => context.pushReplacement('/token/$tokenId'),
                  icon: const Icon(Icons.show_chart_rounded),
                  label: const Text('View live queue'),
                ),
                const SizedBox(height: Gap.md),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/token/$tokenId/slip'),
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share slip'),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
