import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/providers.dart';

/// S-00 intro pages: shown once, on the first launch, before phone login (D-16).
class IntroScreen extends ConsumerStatefulWidget {
  const IntroScreen({super.key});

  @override
  ConsumerState<IntroScreen> createState() => _IntroScreenState();
}

class _IntroPage {
  const _IntroPage({required this.icon, required this.badge, required this.title, required this.body});
  final IconData icon;
  final IconData badge;
  final String title;
  final String body;
}

const _pages = [
  _IntroPage(
    icon: Icons.local_hospital_rounded,
    badge: Icons.search_rounded,
    title: 'Find your clinic',
    body: 'Search your clinic, pick a doctor and get your token in a few taps.',
  ),
  _IntroPage(
    icon: Icons.groups_rounded,
    badge: Icons.timer_outlined,
    title: 'Skip the waiting room',
    body: 'Watch the live queue from home and see how many patients are ahead of you.',
  ),
  _IntroPage(
    icon: Icons.notifications_rounded,
    badge: Icons.check_rounded,
    title: "We'll tell you when to go",
    body: "Get an alert when 3, 2 and 1 patients are ahead, and when it's your turn.",
  ),
];

class _IntroScreenState extends ConsumerState<IntroScreen> {
  final _controller = PageController();
  int _index = 0;

  bool get _isLast => _index == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.update(repo.settings.copyWith(introSeen: true));
    if (mounted) context.go('/login/phone');
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.sm, Gap.sm, 0),
              child: Row(children: [
                const AsaniMark(size: 28),
                const SizedBox(width: Gap.sm),
                Text('asani', style: AppText.titleMedium.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
                const Spacer(),
                AnimatedOpacity(
                  opacity: _isLast ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: TextButton(onPressed: _isLast ? null : _finish, child: const Text('Skip')),
                ),
              ]),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _IntroPageView(page: _pages[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.sm, Gap.xl, Gap.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _pages.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: Gap.xs),
                          width: i == _index ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _index ? AppColors.primary : AppColors.border,
                            borderRadius: BorderRadius.circular(Radii.pill),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: Gap.xl),
                  FilledButton(onPressed: _next, child: Text(_isLast ? 'Get started' : 'Next')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroPageView extends StatelessWidget {
  const _IntroPageView({required this.page});
  final _IntroPage page;

  @override
  Widget build(BuildContext context) {
    return FillScrollView(
      padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Center(
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryContainer.withValues(alpha: 0.5)),
              alignment: Alignment.center,
              child: Container(
                width: 140,
                height: 140,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryContainer),
                child: Stack(alignment: Alignment.center, children: [
                  Icon(page.icon, size: 72, color: AppColors.primary),
                  Positioned(
                    right: 22,
                    top: 22,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.surface, width: 3),
                      ),
                      child: Icon(page.badge, color: AppColors.onPrimary, size: 18),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: Gap.xxl),
          Text(page.title, style: AppText.displaySmall.copyWith(fontSize: 28), textAlign: TextAlign.center),
          const SizedBox(height: Gap.md),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: AppText.bodyLarge.copyWith(color: AppColors.textSecondary),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
