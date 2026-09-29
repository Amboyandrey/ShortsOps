import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/providers.dart';
import 'common.dart';

class QueuePage extends ConsumerWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Topic queue'),
        actions: [
          IconButton(
            tooltip: 'Research 10 new topics',
            icon: const Icon(Icons.auto_awesome),
            onPressed: () async {
              if (await confirm(
                context,
                'Research new topics?',
                'Claude studies competitor Shorts and queues 10 ideas. Allowed once per hour.',
              )) {
                if (context.mounted) await sendCommand(context, ref, 'research', 'Research', {'n': 10});
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Topic'),
        onPressed: () => _addTopic(context, ref),
      ),
      body: AsyncBody(
        value: ref.watch(topicsProvider),
        data: (topics) {
          final pending = topics.where((t) => t.status == 'pending').toList();
          final stuck = topics.where((t) => t.isStuck).toList();
          final skipped = topics.where((t) => t.status == 'skipped').toList();
          // Topics added from the app that the laptop has not picked up yet, newest first.
          final waiting = (ref.watch(commandsProvider).value ?? const <Command>[])
              .where((c) => c.type == 'add_topic' && c.isOpen)
              .toList();
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              if (stuck.isNotEmpty) ...[const _Header('Needs attention'), for (final t in stuck) _TopicTile(topic: t)],
              _Header('Up next (${pending.length})'),
              for (final c in waiting) _WaitingTile(command: c),
              if (pending.isEmpty && waiting.isEmpty)
                const ListTile(title: Text('Queue is empty; the next run researches more.')),
              for (final (i, t) in pending.indexed) _TopicTile(topic: t, rank: i + 1),
              if (skipped.isNotEmpty) ...[
                _Header('Skipped (${skipped.length})'),
                for (final t in skipped) _TopicTile(topic: t),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _addTopic(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add a topic'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'e.g. Why octopuses have three hearts'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, controller.text.trim()), child: const Text('Queue first')),
        ],
      ),
    );
    controller.dispose();
    if (text == null || !context.mounted) return;
    if (text.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Topic needs at least 5 characters')));
      return;
    }
    await sendCommand(context, ref, 'add_topic', 'New topic', {'text': text});
  }
}

/// A topic added from the app that is still in Supabase, waiting for the laptop agent to add it to the queue.
class _WaitingTile extends ConsumerWidget {
  const _WaitingTile({required this.command});

  final Command command;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final adding = command.status == 'claimed';
    return ListTile(
      leading: Icon(adding ? Icons.sync : Icons.hourglass_top, size: 20),
      title: Text(command.payload['text'] as String? ?? ''),
      subtitle: Text(adding ? 'Adding to the queue…' : 'Waiting for the laptop · added ${ago(command.createdAt, now)}'),
      trailing: adding
          ? null
          : IconButton(
              tooltip: 'Cancel',
              icon: const Icon(Icons.close),
              onPressed: () => ref.read(repositoryProvider).cancel(command.id),
            ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _TopicTile extends ConsumerWidget {
  const _TopicTile({required this.topic, this.rank});

  final Topic topic;
  final int? rank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = topic;
    return ExpansionTile(
      leading: rank == null
          ? Icon(t.isStuck ? Icons.warning_amber : Icons.block, size: 20)
          : CircleAvatar(radius: 14, child: Text('$rank', style: const TextStyle(fontSize: 12))),
      title: Text(t.topic),
      subtitle: Text(t.isStuck ? 'Status: ${t.status}' : (t.subniche ?? ''), maxLines: 1),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (t.hook != null) _Detail('Hook', t.hook!),
        if (t.whyItWorks != null) _Detail('Why it should work', t.whyItWorks!),
        if (t.factCheckNotes != null) _Detail('Fact-check notes', t.factCheckNotes!),
        Wrap(spacing: 8, children: _actions(context, ref)),
      ],
    );
  }

  List<Widget> _actions(BuildContext context, WidgetRef ref) {
    final t = topic;
    return switch (t.status) {
      'pending' => [
        OutlinedButton(
          onPressed: () => sendCommand(context, ref, 'reorder_topics', 'Move to top', {
            'ids': [t.id],
          }),
          child: const Text('Move to top'),
        ),
        OutlinedButton(
          onPressed: () async {
            if (await confirm(
              context,
              'Build this Short now?',
              'The laptop writes, voices and renders it (a few minutes). It is not uploaded until the daily run or you approve it.',
            )) {
              if (context.mounted) await sendCommand(context, ref, 'make', 'Build', {'topic_id': t.id});
            }
          },
          child: const Text('Build now'),
        ),
        TextButton(
          onPressed: () => sendCommand(context, ref, 'skip_topic', 'Skip', {'id': t.id}),
          child: const Text('Skip'),
        ),
      ],
      'skipped' => [
        OutlinedButton(
          onPressed: () => sendCommand(context, ref, 'restore_topic', 'Restore', {'id': t.id}),
          child: const Text('Restore'),
        ),
      ],
      'building' || 'failed' => [
        OutlinedButton(
          onPressed: () async {
            if (await confirm(
              context,
              'Return to queue?',
              'Only do this if no build is running for it right now; it goes back to pending.',
            )) {
              if (context.mounted) await sendCommand(context, ref, 'reset_stuck', 'Reset', {'id': t.id});
            }
          },
          child: const Text('Return to queue'),
        ),
      ],
      _ => const [],
    };
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.text);

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        Text(text),
      ],
    ),
  );
}
