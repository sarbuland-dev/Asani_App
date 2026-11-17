import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:asani_ui/asani_ui.dart';
import '../../data/providers.dart';

/// S-00 intro pages ("C · Bold type", D-29): shown once, on the first launch,
/// before phone login. Big words, one idea per page; the words rise in one
/// after another each time a page opens (off when the OS asks for less motion).
class IntroScreen extends ConsumerStatefulWidget {
  const IntroScreen({super.key});

  @override
  ConsumerState<IntroScreen> createState() => _IntroScreenState();
}

class _IntroPage {
  const _IntroPage(this.words, this.body);

  /// One word per line; the last one is drawn in the brand green.
  final List<String> words;
  final String body;
}

const _pages = [
  _IntroPage(['Book', 'your', 'token.'], "Choose a clinic, a doctor and who it's for. Done in under a minute."),
  _IntroPage(['Wait', 'at', 'home.'], 'See who the clinic is serving now and how many patients are ahead of you, live.'),
  _IntroPage(['Go', 'when', 'called.'], 'We send at most 4 alerts per token: 3, 2 and 1 ahead, and your turn.'),
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
      _controller.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kStatusBarDark,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.sm, Gap.sm, 0),
                child: Row(children: [
                  const AsaniMark(size: 30, plusColor: AppColors.primary),
                  const SizedBox(width: Gap.xs),
                  Text('asani', style: AppText.titleMedium.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  // Hidden on the last page: "Get started" does the same job there.
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
                  itemBuilder: (_, i) => _BoldPage(page: _pages[i], active: i == _index),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.xl),
                child: Column(children: [
                  Semantics(
                    label: 'Page ${_index + 1} of ${_pages.length}',
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _pages.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutCubic,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _index ? 22 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: i == _index ? AppColors.primary : AppColors.border,
                              borderRadius: BorderRadius.circular(Radii.pill),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Gap.xl),
                  FilledButton(onPressed: _next, child: Text(_isLast ? 'Get started' : 'Next')),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One intro page. When it becomes [active], its words rise in one after
/// another, then the body text follows.
class _BoldPage extends StatefulWidget {
  const _BoldPage({required this.page, required this.active});
  final _IntroPage page;
  final bool active;

  @override
  State<_BoldPage> createState() => _BoldPageState();
}

class _BoldPageState extends State<_BoldPage> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.active) _play();
  }

  @override
  void didUpdateWidget(_BoldPage old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _play();
  }

  void _play() {
    // Respect the OS "reduce motion" setting (DESIGN.md §9).
    if (MediaQuery.disableAnimationsOf(context)) {
      _anim.value = 1;
    } else {
      _anim.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  /// Fade + slide up, starting at [start] (0..1 of the whole animation).
  Widget _rise(double start, Widget child) {
    final curve = CurvedAnimation(parent: _anim, curve: Interval(start, (start + 0.45).clamp(0, 1), curve: Curves.easeOutCubic));
    return AnimatedBuilder(
      animation: curve,
      builder: (_, c) => Opacity(
        opacity: curve.value,
        child: Transform.translate(offset: Offset(0, 24 * (1 - curve.value)), child: c),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final words = widget.page.words;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Read as one sentence by screen readers ("Book your token.").
              Semantics(
                header: true,
                label: words.join(' '),
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < words.length; i++)
                        _rise(
                          i * 0.15,
                          Text(
                            words[i],
                            style: AppText.displayLarge.copyWith(
                              color: i == words.length - 1 ? AppColors.primary : AppColors.textPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Gap.xl),
              _rise(0.5, Text(widget.page.body, style: AppText.bodyLarge.copyWith(color: AppColors.textSecondary))),
            ],
          ),
        ),
      ),
    );
  }
}
