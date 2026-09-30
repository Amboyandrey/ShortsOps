import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';
import '../data/providers.dart';
import 'common.dart';

/// Status-tab reminder that some Shorts are waiting, privately, for the owner's review.
class HeldReminderCard extends ConsumerWidget {
  const HeldReminderCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final held = ref.watch(heldVideosProvider);
    if (held.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: ListTile(
        leading: Icon(Icons.rate_review, color: scheme.onErrorContainer),
        title: Text(
          held.length == 1 ? '1 Short needs your review' : '${held.length} Shorts need your review',
          style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Uploaded privately: the fact-check was not confident enough to publish on its own.',
          style: TextStyle(color: scheme.onErrorContainer),
        ),
        trailing: Icon(Icons.chevron_right, color: scheme.onErrorContainer),
        onTap: () => context.go('/videos'),
      ),
    );
  }
}

/// One held video: why it was held, a link to watch it on YouTube, and the publish actions.
class HeldVideoTile extends ConsumerWidget {
  const HeldVideoTile({super.key, required this.video});

  final Video video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = video;
    final notes = v.buildId == null ? null : ref.watch(factCheckProvider(v.buildId!));
    return ExpansionTile(
      leading: const Icon(Icons.lock_outline),
      title: Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('Private · fact-check confidence ${v.confidence ?? '?'}'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Why it was held', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(notes?.value ?? (notes?.isLoading ?? false ? 'Loading the fact-check notes…' : 'No notes recorded.')),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Watch on YouTube'),
              onPressed: () => launchUrl(v.url, mode: LaunchMode.externalApplication),
            ),
            FilledButton(
              onPressed: () async {
                if (await confirm(context, 'Publish this Short?', 'It goes into the next free publish slot.')) {
                  if (context.mounted) {
                    await sendCommand(context, ref, 'approve_video', 'Publish', {'video_id': v.videoId});
                  }
                }
              },
              child: const Text('Publish next slot'),
            ),
            TextButton(
              onPressed: () async {
                if (await confirm(context, 'Publish right now?', 'It goes public immediately.')) {
                  if (context.mounted) {
                    await sendCommand(context, ref, 'approve_video', 'Publish now', {
                      'video_id': v.videoId,
                      'now': true,
                    });
                  }
                }
              },
              child: const Text('Publish now'),
            ),
          ],
        ),
      ],
    );
  }
}
