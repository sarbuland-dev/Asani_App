import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:asani_ui/asani_ui.dart';
import '../../data/providers.dart';

/// S-00 intro pages (D-29 copy, board P1 layout): shown once, on the first
/// launch, before phone login. A green top with a small card picture of the
/// idea, the title and text below, dots and a round Next button. The words
/// rise in when a page opens (off when the OS asks for less motion).
class IntroScreen extends ConsumerStatefulWidget {
  const IntroScreen({super.key});

  @override
  ConsumerState<IntroScreen> createState() => _IntroScreenState();
}

enum _Art { book, queue, turn }

class _IntroPage {
  const _IntroPage(this.words, this.body, this.art);

  /// The title; the last word is drawn in the brand green.
  final List<String> words;
  final String body;
  final _Art art;
}

const _pages = [
  _IntroPage(['Book', 'your', 'token.'], "Choose a clinic, a doctor and who it's for. Done in under a minute.", _Art.book),
  _IntroPage(['Wait', 'at', 'home.'], 'See who the clinic is serving now and how many patients are ahead of you, live.', _Art.queue),
  _IntroPage(['Go', 'when', 'called.'], 'We send at most 4 alerts per token: 3, 2 and 1 ahead, and your turn.', _Art.turn),
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
    final top = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kStatusBarLight,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _Page(page: _pages[i], active: i == _index, topInset: top),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.sm, Gap.xl, Gap.xl),
                child: Row(children: [
                  Semantics(
                    label: 'Page ${_index + 1} of ${_pages.length}',
                    child: Row(children: [
                      for (var i = 0; i < _pages.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          margin: const EdgeInsets.only(right: 6),
                          width: i == _index ? 26 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _index ? AppColors.primary : AppColors.border,
                            borderRadius: BorderRadius.circular(Radii.pill),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(width: Gap.md),
                  // Shrinks on tiny phones with large text instead of overflowing.
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(fit: BoxFit.scaleDown, child: _NextButton(last: _isLast, onTap: _next)),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round arrow button; on the last page it widens to "Get started".
class _NextButton extends StatelessWidget {
  const _NextButton({required this.last, required this.onTap});
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: last ? 'Get started' : 'Next',
      excludeSemantics: true,
      child: Material(
        color: AppColors.primary,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: SizedBox(
              height: 64,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: last ? Gap.xl : 20),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (last) ...[
                    Text('Get started', style: AppText.labelLarge.copyWith(color: AppColors.onPrimary)),
                    const SizedBox(width: Gap.sm),
                  ],
                  const Icon(Icons.arrow_forward_rounded, color: AppColors.onPrimary, size: 26),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One intro page: green top with the picture card, then title and text.
class _Page extends ConsumerStatefulWidget {
  const _Page({required this.page, required this.active, required this.topInset});
  final _IntroPage page;
  final bool active;
  final double topInset;

  @override
  ConsumerState<_Page> createState() => _PageState();
}

class _PageState extends ConsumerState<_Page> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.active) _play();
  }

  @override
  void didUpdateWidget(_Page old) {
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
    final curve = CurvedAnimation(parent: _anim, curve: Interval(start, (start + 0.5).clamp(0, 1), curve: Curves.easeOutCubic));
    return AnimatedBuilder(
      animation: curve,
      builder: (_, c) => Opacity(
        opacity: curve.value,
        child: Transform.translate(offset: Offset(0, 20 * (1 - curve.value)), child: c),
      ),
      child: child,
    );
  }

  Future<void> _skip() async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.update(repo.settings.copyWith(introSeen: true));
    if (mounted) context.go('/login/phone');
  }

  @override
  Widget build(BuildContext context) {
    final words = widget.page.words;
    final isLast = widget.page == _pages.last;
    return LayoutBuilder(builder: (context, box) {
      // The green top takes a bit over half the page on normal phones.
      final headerH = (box.maxHeight * 0.56).clamp(300.0, 480.0);
      return SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: headerH,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            padding: EdgeInsets.fromLTRB(Gap.xl, widget.topInset + Gap.sm, Gap.sm, Gap.xl),
            child: Column(children: [
              Row(children: [
                const AsaniMark(size: 28, color: AppColors.onPrimary),
                const SizedBox(width: Gap.sm),
                Text('asani', style: AppText.titleMedium.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w800, fontSize: 20)),
                const Spacer(),
                // Hidden on the last page: "Get started" does the same job there.
                if (!isLast)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: AppColors.onPrimary),
                    onPressed: _skip,
                    child: const Text('Skip'),
                  )
                else
                  const SizedBox(height: kMinTap),
              ]),
              const SizedBox(height: Gap.lg),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: Gap.lg),
                  // A picture, not content: fixed text size, hidden from screen readers.
                  child: _rise(
                    0,
                    ExcludeSemantics(
                      child: MediaQuery.withNoTextScaling(child: FittedBox(child: _Picture(art: widget.page.art))),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 30, 28, Gap.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Read as one sentence by screen readers ("Book your token.").
              Semantics(
                header: true,
                label: words.join(' '),
                child: ExcludeSemantics(
                  child: _rise(
                    0.15,
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${words.take(words.length - 1).join(' ')} '),
                        TextSpan(text: words.last, style: const TextStyle(color: AppColors.primary)),
                      ]),
                      style: AppText.headline.copyWith(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Gap.md),
              _rise(0.35, Text(widget.page.body, style: AppText.bodyLarge.copyWith(color: AppColors.textSecondary, height: 1.55))),
            ]),
          ),
        ]),
      );
    });
  }
}

/// The card picture on the green top: two softer layers behind a cream card.
class _Picture extends StatelessWidget {
  const _Picture({required this.art});
  final _Art art;

  static const _w = 300.0;

  @override
  Widget build(BuildContext context) {
    // The card sets the size; the two layers peek out above it, whatever
    // its height (each page's card is a different height).
    Widget layer(double inset, double top, double bottom, Color c) => Positioned(
          left: inset,
          right: inset,
          top: top,
          bottom: bottom,
          child: DecoratedBox(decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(28))),
        );
    return SizedBox(
      width: _w + 28,
      child: Stack(children: [
        layer(30, 0, 40, AppColors.primaryMid),
        layer(16, 20, 20, AppColors.primaryLight),
        Padding(padding: const EdgeInsets.only(top: 44), child: _card()),
      ]),
    );
  }

  Widget _card() {
    final body = switch (art) {
      _Art.book => const _BookCard(),
      _Art.queue => const _QueueCard(),
      _Art.turn => const _TurnCard(),
    };
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(24)),
      child: body,
    );
  }
}

Widget _doctorRow() => Row(children: [
      Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
        child: Text('AM', style: AppText.labelMedium.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w700)),
      ),
      const SizedBox(width: Gap.md),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Dr. Ayesha Malik', style: AppText.labelMedium.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
        Text('General Physician · Al-Shifa', style: AppText.labelSmall),
      ]),
    ]);

Widget _stat(String label, String value, {Color color = AppColors.textPrimary, bool end = false}) => Column(
      crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.labelSmall.copyWith(fontSize: 11)),
        Text(value, style: AppText.titleLarge.copyWith(fontSize: 26, fontWeight: FontWeight.w800, color: color)),
      ],
    );

Widget _white(Widget child) => Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
      child: child,
    );

class _BookCard extends StatelessWidget {
  const _BookCard();

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _doctorRow(),
        const SizedBox(height: 14),
        _white(Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _stat('Your token', 'A-11', color: AppColors.primary),
          _stat('Ahead of you', '3', end: true),
        ])),
        const SizedBox(height: 14),
        Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(14)),
          child: Text('Book token ›', style: AppText.labelMedium.copyWith(color: AppColors.onPrimary)),
        ),
      ]);
}

class _QueueCard extends StatelessWidget {
  const _QueueCard();

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('LIVE QUEUE', style: AppText.overline.copyWith(color: AppColors.primary, fontSize: 11)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(Radii.pill)),
            child: Text('● Live', style: AppText.labelSmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: Gap.md),
        _white(Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _stat('Now serving', 'A-8'),
          _stat('Ahead', '3', color: AppColors.primary),
          _stat('Est. wait', '30m', end: true),
        ])),
        const SizedBox(height: 14),
        Row(children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: i < 2 ? AppColors.primary : AppColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ]),
        const SizedBox(height: Gap.sm),
        Text('Token A-11 · Shazia Begum', style: AppText.labelSmall),
      ]);
}

class _TurnCard extends StatelessWidget {
  const _TurnCard();

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          for (final s in ['3', '2', '1'])
            Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.only(right: 6),
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              child: Text(s, style: AppText.labelMedium.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w800)),
            ),
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.info, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, size: 18, color: AppColors.surface),
          ),
          const Spacer(),
          Flexible(child: Text('4 alerts', style: AppText.labelSmall, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(gradient: AppColors.calledGradient, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
              child: const Icon(Icons.notifications_active_outlined, color: AppColors.info),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Your turn now', style: AppText.labelLarge.copyWith(color: AppColors.surface, fontWeight: FontWeight.w800)),
                Text('Token A-11 · go to Dr. Ayesha', style: AppText.labelSmall.copyWith(color: AppColors.infoContainer)),
              ]),
            ),
          ]),
        ),
      ]);
}
