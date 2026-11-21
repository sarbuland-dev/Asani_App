import 'dart:ui' as ui;

import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import 'package:asani_ui/asani_ui.dart';
import '../../data/providers.dart';
import 'token_slip.dart';

/// Token slip screen: save or share the slip as an image.
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

    return Scaffold(
      backgroundColor: AppColors.primaryContainer,
      appBar: AppBar(
        backgroundColor: AppColors.primaryContainer,
        leading: const Padding(padding: EdgeInsets.only(left: Gap.sm), child: Center(child: HeaderBackButton(dark: true))),
        leadingWidth: 64,
        centerTitle: true,
        title: Text('Token slip', style: AppText.titleMedium),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.md, Gap.xl, Gap.lg),
                child: RepaintBoundary(
                  key: _boundary,
                  child: TokenSlip(token: token, clinic: clinic, doctor: doctor),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Gap.screen),
              child: cancelled
                  ? Column(children: [
                      Container(
                        padding: const EdgeInsets.all(Gap.md),
                        decoration: BoxDecoration(color: AppColors.dangerContainer, borderRadius: BorderRadius.circular(Radii.button)),
                        child: Row(children: [
                          const Icon(Icons.cancel_outlined, color: AppColors.danger),
                          const SizedBox(width: Gap.sm),
                          Expanded(
                            child: Text(
                              'This token was cancelled${token.cancelledAt == null ? '' : ' on ${Fmt.dateTime(token.cancelledAt!)}'}. The slip is no longer valid.',
                              style: AppText.bodyMedium.copyWith(color: AppColors.danger),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: Gap.md),
                      FilledButton(
                        onPressed: () => context.push('/book/${token.clinicId}/${token.doctorId}?patient=${token.patientId}'),
                        child: const Text('Book a new token'),
                      ),
                    ])
                  : Column(children: [
                      FilledButton.icon(
                        onPressed: _sharing ? null : () => _share(token, doctor, clinic),
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Save to gallery'),
                      ),
                      const SizedBox(height: Gap.md),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(backgroundColor: AppColors.surface),
                          onPressed: _sharing ? null : () => _share(token, doctor, clinic),
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('Share on WhatsApp'),
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
