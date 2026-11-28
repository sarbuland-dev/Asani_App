import 'package:asani_ui/asani_ui.dart';
import 'package:flutter/material.dart';

typedef MemberVisits = ({String name, int visits});

/// Family summary (board P13, D-65): completed visits as one bar per member
/// (most visits first), then the family's live tokens and pending follow-ups.
/// A number that is zero is not shown; with no visits there is no chart.
class FamilySummaryCard extends StatelessWidget {
  const FamilySummaryCard({
    super.key,
    required this.members,
    required this.liveTokens,
    required this.followUps,
    required this.onLiveTokens,
    required this.onFollowUps,
  });

  final List<MemberVisits> members;
  final int liveTokens;
  final int followUps;
  final VoidCallback onLiveTokens;
  final VoidCallback? onFollowUps;

  @override
  Widget build(BuildContext context) {
    final total = members.fold(0, (sum, m) => sum + m.visits);
    // Most visits first; members with the same number keep their usual order.
    final order = List.generate(members.length, (i) => i)
      ..sort((a, b) {
        final byVisits = members[b].visits.compareTo(members[a].visits);
        return byVisits != 0 ? byVisits : a.compareTo(b);
      });
    final sorted = [for (final i in order) members[i]];
    final chips = [
      if (liveTokens > 0)
        _SummaryChip(
          icon: Icons.confirmation_number_outlined,
          label: '$liveTokens live ${liveTokens == 1 ? 'token' : 'tokens'}',
          color: AppColors.primaryContainer,
          onColor: AppColors.primary,
          onTap: onLiveTokens,
        ),
      if (followUps > 0)
        _SummaryChip(
          icon: Icons.event_outlined,
          label: '$followUps ${followUps == 1 ? 'follow-up' : 'follow-ups'}',
          // Lime marks follow-ups, as on Home.
          color: AppColors.lime.withValues(alpha: 0.18),
          onColor: AppColors.onLimeMuted,
          onTap: onFollowUps,
        ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(Gap.lg, 14, Gap.lg, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (total > 0) ...[
          Row(children: [
            Expanded(
              child: Text('$total ${total == 1 ? 'visit' : 'visits'} so far',
                  style: AppText.labelLarge.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            Text('by member', style: AppText.labelSmall),
          ]),
          const SizedBox(height: 10),
          _Bars(members: sorted),
          if (chips.isNotEmpty) const SizedBox(height: Gap.sm),
        ],
        if (chips.isNotEmpty)
          Row(children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: Gap.sm),
              Expanded(child: chips[i]),
            ],
          ]),
      ]),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.members});

  /// Already sorted: the first has the most visits.
  final List<MemberVisits> members;

  static const _colors = [AppColors.primary, AppColors.lime, AppColors.primaryLight, AppColors.primarySoft];
  static const _gap = 10.0;
  static const _tallest = 62.0;

  @override
  Widget build(BuildContext context) {
    final most = members.first.visits;
    return LayoutBuilder(builder: (context, box) {
      // Up to four bars fill the card. With more, the row scrolls sideways and
      // part of the fifth stays in view to show there is more.
      final n = members.length;
      final slots = n <= 4 ? n.toDouble() : 4.4;
      final width = (box.maxWidth - _gap * (n <= 4 ? n - 1 : 4)) / slots;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: n <= 4 ? const NeverScrollableScrollPhysics() : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              SizedBox(width: width, child: _bar(members[i], most, _colors[i % _colors.length])),
            ],
          ],
        ),
      );
    });
  }

  Widget _bar(MemberVisits m, int most, Color color) {
    final first = m.name.trim().split(RegExp(r'\s+')).first;
    return Semantics(
      label: '$first: ${m.visits} ${m.visits == 1 ? 'visit' : 'visits'}',
      excludeSemantics: true,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${m.visits}', style: AppText.labelSmall.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Container(
          width: 34,
          height: m.visits == 0 ? 4 : 10 + (_tallest - 10) * m.visits / most,
          decoration: BoxDecoration(
            color: m.visits == 0 ? AppColors.border : color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(9), bottom: Radius.circular(4)),
          ),
        ),
        const SizedBox(height: 4),
        Text(first, style: AppText.labelSmall.copyWith(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.icon, required this.label, required this.color, required this.onColor, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final Color onColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: Gap.xs),
              child: Row(children: [
                Icon(icon, size: 16, color: onColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label,
                      style: AppText.labelSmall.copyWith(color: onColor, fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
