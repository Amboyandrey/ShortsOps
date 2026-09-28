import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/providers.dart';
import 'common.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Status'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(supabaseProvider).auth.signOut(),
          ),
        ],
      ),
      body: AsyncBody(
        value: ref.watch(agentStatusProvider),
        data: (status) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _AgentCard(status: status, now: now),
            const SizedBox(height: 12),
            _UpcomingCard(now: now),
            const SizedBox(height: 12),
            const _RecentEventsCard(),
          ],
        ),
      ),
    );
  }
}

class _AgentCard extends ConsumerWidget {
  const _AgentCard({required this.status, required this.now});

  final AgentStatus? status;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = status;
    if (s == null) {
      return const Card(child: ListTile(title: Text('The laptop agent has not connected yet.')));
    }
    final online = s.isOnline(now);
    final ranToday = s.lastRunDate != null && DateTime.tryParse(s.lastRunDate!)?.day == now.day;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 12, color: online ? Colors.green : theme.colorScheme.error),
                const SizedBox(width: 8),
                Text(online ? 'Laptop online' : 'Laptop offline', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(ago(s.lastSeen, now), style: theme.textTheme.bodySmall),
              ],
            ),
            if (!online)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Showing the last known state. Commands wait until it is back.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const Divider(height: 24),
            _Fact('Daily run', s.paused ? 'Paused' : (ranToday ? 'Done today' : 'Pending (from 10:00)')),
            _Fact('Cron', s.cronInstalled == false ? 'Not installed' : 'Installed'),
            _Fact('Uploads left today', '${s.uploadsLeft ?? '-'}  (${compact(s.quotaUnitsUsed)} quota units used)'),
            _Fact('Disk', '${gigabytes(s.diskFreeBytes)} free · builds use ${gigabytes(s.outDirBytes)}'),
            if (s.runningCommand != null) const _Fact('Working on', 'a command, see Activity'),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Automatic daily run'),
              subtitle: const Text('Pause to stop cron building and uploading'),
              value: !s.paused,
              onChanged: (on) => sendCommand(context, ref, on ? 'resume' : 'pause', on ? 'Resume' : 'Pause'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(width: 150, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class _UpcomingCard extends ConsumerWidget {
  const _UpcomingCard({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videos = ref.watch(videosProvider).value ?? const [];
    final upcoming = videos.where((v) => !v.isLive(now)).toList()..sort((a, b) => a.publishAt!.compareTo(b.publishAt!));
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(title: Text('Scheduled (${upcoming.length})')),
          if (upcoming.isEmpty) const ListTile(dense: true, title: Text('Nothing scheduled.')),
          for (final v in upcoming.take(4))
            ListTile(
              dense: true,
              title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(when(v.publishAt!)),
            ),
        ],
      ),
    );
  }
}

class _RecentEventsCard extends ConsumerWidget {
  const _RecentEventsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final events = (ref.watch(eventsProvider).value ?? const []).take(5);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(title: Text('Recent')),
          for (final e in events)
            ListTile(
              dense: true,
              title: Text(e.title),
              subtitle: e.body == null ? null : Text(e.body!, maxLines: 2),
              trailing: Text(ago(e.createdAt, now)),
            ),
        ],
      ),
    );
  }
}
