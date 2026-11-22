import 'dart:ui' as ui;

import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'package:asani_ui/asani_ui.dart';
import '../../data/providers.dart';

/// Full-screen token slip (board P5c, approved 2026-11-23): green header,
/// the slip card (clinic, status, tear line, big token, details, asani mark),
/// then Share slip / Save to gallery. A cancelled token is greyed with a red
/// CANCELLED stamp, a note and "Book a new token".
class TokenSlipScreen extends ConsumerStatefulWidget {
  const TokenSlipScreen({super.key, required this.tokenId});
  final String tokenId;

  @override
  ConsumerState<TokenSlipScreen> createState() => _TokenSlipScreenState();
}

class _TokenSlipScreenState extends ConsumerState<TokenSlipScreen> {
  final _boundary = GlobalKey();
  bool _sharing = false;
  bool _autoShared = false;

  Future<void> _share(Token token, Doctor doctor, Clinic clinic) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final box = _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      final image = await box?.toImage(pixelRatio: 3);
      final bytes = (await image?.toByteData(format: ui.ImageByteFormat.png))?.buffer.asUint8List();
      final text = 'Asani token ${token.label} · ${doctor.name}, ${clinic.name} · ${Fmt.longDay(token.date)}';
      await SharePlus.instance.share(ShareParams(
        text: text,
        files: bytes == null ? null : [XFile.fromData(bytes, mimeType: 'image/png', name: 'asani-token-${token.label}.png')],
      ));
    } catch (e, st) {
      AppLogger.error('Share slip failed', e, st);
      if (mounted) showSnack(context, "Couldn't share the slip. Please try again.");
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final token = ref.watch(tokenProvider(widget.tokenId)).value;
    final doctor = token == null ? null : ref.watch(doctorProvider(token.doctorId)).value;
    final clinic = token == null ? null : ref.watch(clinicProvider(token.clinicId)).value;
    if (token == null || doctor == null || clinic == null) {
      return const LoadingScreen(message: 'Loading your slip…');
    }
    final cancelled = token.status == TokenStatus.cancelled;
    if (!_autoShared && GoRouterState.of(context).uri.queryParameters['share'] == '1' && !cancelled) {
      _autoShared = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _share(token, doctor, clinic));
    }

    return StatusBarScrim(
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: SingleChildScrollView(
              child: Stack(children: [
                // Green header; the slip card overlaps its bottom edge.
                Container(
                  height: 190,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(Radii.header)),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, Gap.sm, 20, 0),
                      child: Row(children: [
                        const HeaderBackButton(),
                        Expanded(
                          child: Text('Token slip',
                              textAlign: TextAlign.center,
                              style: AppText.labelLarge.copyWith(color: AppColors.onPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 44),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    Text(cancelled ? 'This token can no longer be used' : 'Show this at reception when you arrive',
                        textAlign: TextAlign.center,
                        style: AppText.labelSmall.copyWith(color: AppColors.onPrimaryMuted, fontSize: 13)),
                    const SizedBox(height: 22),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: RepaintBoundary(
                        key: _boundary,
                        child: _SlipCard(token: token, doctor: doctor, clinic: clinic),
                      ),
                    ),
                    if (cancelled)
                      Container(
                        margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(color: AppColors.dangerContainer, borderRadius: BorderRadius.circular(14)),
                        child: Text(
                          [
                            'Cancelled${token.cancelledByClinic ? ' by clinic' : ''}'
                                '${token.cancelledAt == null ? '' : ' on ${DateFormat('EEE, d MMM, h:mm a').format(token.cancelledAt!)}'}',
                            ?token.cancelReason,
                          ].join(' · '),
                          style: AppText.bodyMedium.copyWith(color: AppColors.dangerText, fontSize: 13),
                        ),
                      ),
                    const SizedBox(height: Gap.lg),
                  ]),
                ),
              ]),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, Gap.lg),
              child: cancelled
                  ? FilledButton(
                      onPressed: () => context.push('/book/${token.clinicId}/${token.doctorId}?patient=${token.patientId}'),
                      child: const Text('Book a new token ›'),
                    )
                  : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      FilledButton.icon(
                        onPressed: _sharing ? null : () => _share(token, doctor, clinic),
                        icon: const Icon(Icons.ios_share_rounded),
                        label: const Text('Share slip'),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 52,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(backgroundColor: AppColors.surface),
                          onPressed: _sharing ? null : () => _share(token, doctor, clinic),
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('Save to gallery'),
                        ),
                      ),
                    ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The slip itself (also what Share / Save turns into an image).
class _SlipCard extends StatelessWidget {
  const _SlipCard({required this.token, required this.doctor, required this.clinic});
  final Token token;
  final Doctor doctor;
  final Clinic clinic;

  @override
  Widget build(BuildContext context) {
    final cancelled = token.status == TokenStatus.cancelled;
    final s = token.patientSnapshot;
    final age = s.age();
    final schedule = doctor.scheduleOn(parseDayKey(token.date));
    final isToday = token.date == dayKey(pktNow());
    final (String pill, Color pillBg, Color pillFg) = cancelled
        ? ('Cancelled', AppColors.dangerContainer, AppColors.dangerText)
        : token.status.isActive
            ? (isToday ? '● Live' : Fmt.relativeDay(token.date), AppColors.primaryContainer, AppColors.primary)
            : (token.status.label, AppColors.muted, AppColors.textSecondary);
    final faded = cancelled ? 0.45 : 1.0;

    Widget row(String k, String v, {bool last = false}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AppColors.border))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, style: AppText.bodyMedium.copyWith(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: AppText.labelMedium.copyWith(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
            ),
          ]),
        );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.14), blurRadius: 32, offset: const Offset(0, 16))],
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: cancelled ? AppColors.cream : AppColors.primary, borderRadius: BorderRadius.circular(14)),
                child: Text(Fmt.initials(clinic.name),
                    style: AppText.labelLarge.copyWith(color: cancelled ? AppColors.textSecondary : AppColors.onPrimary, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(clinic.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.labelLarge.copyWith(
                          fontWeight: FontWeight.w700, color: cancelled ? AppColors.textSecondary : AppColors.textPrimary)),
                  Text(clinic.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.labelSmall.copyWith(fontSize: 12)),
                ]),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: pillBg, borderRadius: BorderRadius.circular(Radii.pill)),
                child: Text(pill, style: AppText.labelSmall.copyWith(color: pillFg, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          const _TearLine(),
          Opacity(
            opacity: faded,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
              child: Column(children: [
                Text('TOKEN', style: AppText.overline.copyWith(fontSize: 11, letterSpacing: 1.6, color: AppColors.textSecondary)),
                FittedBox(
                  child: Text(token.label,
                      style: AppText.displaySmall.copyWith(
                          fontSize: 64, fontWeight: FontWeight.w800, height: 1.05, color: cancelled ? AppColors.textSecondary : AppColors.primary)),
                ),
                Text('Booked at ${DateFormat('h:mm a').format(token.createdAt)}', style: AppText.labelSmall.copyWith(fontSize: 12)),
              ]),
            ),
          ),
          Opacity(
            opacity: cancelled ? 0.7 : 1,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                row('Patient',
                    '${s.name}${s.relation == Relation.self ? '' : ' · ${s.relation.label}'}${age == null ? '' : ' · $age ${s.gender.short}'}'),
                row('Doctor', doctor.name),
                row('Date', Fmt.shortDay(token.date)),
                row('Session', schedule == null ? '—' : Fmt.timeRange(schedule), last: true),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
            child: Row(children: [
              Expanded(child: Text('Asani token slip', style: AppText.labelSmall.copyWith(fontSize: 12))),
              const AsaniMark(size: 18),
              const SizedBox(width: 6),
              Text('asani',
                  style: AppText.labelLarge.copyWith(
                      fontWeight: FontWeight.w800, color: cancelled ? AppColors.textSecondary : AppColors.primary)),
            ]),
          ),
        ]),
        if (cancelled)
          Positioned(
            left: 0,
            right: 0,
            top: 120,
            child: Center(
              child: Transform.rotate(
                angle: -0.21,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.82),
                    border: Border.all(color: AppColors.danger, width: 4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('CANCELLED',
                      style: AppText.headline.copyWith(color: AppColors.danger, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 3.6)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Dashed tear line with half-circle notches on both sides (board P5c).
class _TearLine extends StatelessWidget {
  const _TearLine();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 22,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: LayoutBuilder(builder: (context, c) {
                final n = (c.maxWidth / 10).floor();
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [for (var i = 0; i < n; i++) Container(width: 5, height: 2, color: AppColors.border)],
                );
              }),
            ),
          ),
          Positioned(left: -11, top: 0, child: _notch()),
          Positioned(right: -11, top: 0, child: _notch()),
        ]),
      );

  Widget _notch() => Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(color: AppColors.background, shape: BoxShape.circle),
      );
}
