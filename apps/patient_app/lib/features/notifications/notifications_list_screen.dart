import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/error_state.dart';
import '../../data/providers.dart';

/// S-19 Notifications list (PRD D-45). Plain placeholder UI.
/// Every push of the last 30 days; opening the list marks all read; a tap
/// opens the same place as the push.
class NotificationsListScreen extends ConsumerStatefulWidget {
  const NotificationsListScreen({super.key});

  @override
  ConsumerState<NotificationsListScreen> createState() => _NotificationsListScreenState();
}

class _NotificationsListScreenState extends ConsumerState<NotificationsListScreen> {
  /// Seen time from before this visit, so this visit can still show what was new.
  DateTime? _seenBefore;
  bool _marked = false;

  @override
  Widget build(BuildContext context) {
    final seen = ref.watch(notificationsSeenAtProvider);
    if (!_marked && seen.hasValue) {
      _marked = true;
      _seenBefore = seen.value;
      // Mark everything read once the list is open (D-45).
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(notificationRepositoryProvider).markAllSeen());
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ref.watch(notificationsProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(notificationsProvider)),
            data: (list) => list.isEmpty
                ? const Center(child: Text('No notifications in the last 30 days.'))
                : ListView(children: [
                    for (final n in list)
                      ListTile(
                        title: Text(n.title, style: TextStyle(fontWeight: n.unreadSince(_seenBefore) ? FontWeight.bold : FontWeight.normal)),
                        subtitle: Text('${n.body}\n${Fmt.dateTime(n.createdAt)}'),
                        isThreeLine: true,
                        onTap: () => context.push(n.route),
                      ),
                  ]),
          ),
    );
  }
}

/// Bell with the unread count, for the Home header.
class NotificationsBell extends ConsumerWidget {
  const NotificationsBell({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationsProvider);
    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => context.push('/inbox'),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: Icon(Icons.notifications_outlined, color: color),
      ),
    );
  }
}
