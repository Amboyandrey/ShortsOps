import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/providers.dart';
import 'common.dart';

class ActivityPage extends ConsumerWidget {
  const ActivityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final runs = ref.watch(runsProvider).value ?? const <Run>[];
    final active = runs.where((r) => r.status == 'running').toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: AsyncBody(
        value: ref.watch(commandsProvider),
        data: (commands) => ListView(
          children: [
            for (final r in active)
              Card(
                margin: const EdgeInsets.all(12),
                child: ListTile(
                  leading: const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                  title: Text('Running ${r.kind}'),
                  subtitle: Text('Step: ${r.step ?? 'starting'} · started ${ago(r.startedAt, now)}'),
                ),
              ),
            if (commands.isEmpty) const ListTile(title: Text('No commands yet.')),
            for (final c in commands) _CommandTile(command: c, now: now),
          ],
        ),
      ),
    );
  }
}

class _CommandTile extends ConsumerWidget {
  const _CommandTile({required this.command, required this.now});

  final Command command;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = command;
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (c.status) {
      'done' => (Icons.check_circle, Colors.green),
      'failed' => (Icons.error, scheme.error),
      'pending' => (Icons.schedule, scheme.outline),
      'claimed' => (Icons.sync, scheme.primary),
      _ => (Icons.remove_circle_outline, scheme.outline),
    };
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(c.type.replaceAll('_', ' ')),
      subtitle: Text([c.status, ago(c.createdAt, now), if (c.error != null) c.error!].join(' · '), maxLines: 3),
      trailing: c.status == 'pending'
          ? IconButton(
              tooltip: 'Cancel',
              icon: const Icon(Icons.close),
              onPressed: () => ref.read(repositoryProvider).cancel(c.id),
            )
          : null,
    );
  }
}
