import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/launch.dart';
import '../../core/widgets/common.dart';
import '../../data/providers.dart';

/// S-04: name + consent on first login (PRD F-01).
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _name = TextEditingController();
  bool _agreed = false;
  bool _saving = false;
  late final _termsTap = TapGestureRecognizer()..onTap = () => openUrl(context, AppLinks.terms);
  late final _privacyTap = TapGestureRecognizer()..onTap = () => openUrl(context, AppLinks.privacy);

  @override
  void dispose() {
    _name.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().length >= 2 && _agreed;

  Future<void> _continue() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(authRepositoryProvider).completeProfile(_name.text);
    } catch (e) {
      if (mounted) showSnack(context, AppException.messageOf(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = AppText.bodyLarge.copyWith(
        color: AppColors.primary, fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: AppColors.primary);
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: FillScrollView(
          padding: const EdgeInsets.all(Gap.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HeaderBackButton(dark: true, onPressed: () => ref.read(authRepositoryProvider).signOut()),
              const SizedBox(height: Gap.xl),
              const IconBox(icon: Icons.person_outline_rounded, size: 52),
              const SizedBox(height: Gap.lg),
              Text("What's your name?", style: AppText.displaySmall.copyWith(fontSize: 28)),
              const SizedBox(height: Gap.sm),
              Text('Clinics will see this name on your token.', style: AppText.bodyMedium.copyWith(fontSize: 15)),
              const SizedBox(height: Gap.xl),
              Text('Full name', style: AppText.labelMedium),
              const SizedBox(height: Gap.sm),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                style: AppText.bodyLarge,
                decoration: const InputDecoration(hintText: 'e.g. Ali Khan'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: Gap.lg),
              InkWell(
                onTap: () => setState(() => _agreed = !_agreed),
                borderRadius: BorderRadius.circular(Radii.button),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                  child: Row(
                    children: [
                      Checkbox(value: _agreed, onChanged: (v) => setState(() => _agreed = v ?? false)),
                      Expanded(
                        child: Text.rich(TextSpan(style: AppText.bodyLarge.copyWith(fontSize: 15), children: [
                          const TextSpan(text: 'I agree to the '),
                          TextSpan(text: 'Terms', style: link, recognizer: _termsTap),
                          const TextSpan(text: ' and '),
                          TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacyTap),
                        ])),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _valid && !_saving ? _continue : null,
                child: _saving
                    ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onPrimary))
                    : const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
