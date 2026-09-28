import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';
import '../data/providers.dart';
import 'common.dart';

class VideosPage extends ConsumerWidget {
  const VideosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Videos'),
        actions: [
          IconButton(
            tooltip: 'Refresh view counts',
            icon: const Icon(Icons.refresh),
            onPressed: () => sendCommand(context, ref, 'refresh_stats', 'Stats refresh'),
          ),
        ],
      ),
      body: AsyncBody(
        value: ref.watch(videosProvider),
        data: (videos) {
          final upcoming = videos.where((v) => !v.isLive(now)).toList()
            ..sort((a, b) => a.publishAt!.compareTo(b.publishAt!));
          final live = videos.where((v) => v.isLive(now)).toList();
          final total = live.fold<int>(0, (sum, v) => sum + (v.views ?? 0));
          return ListView(
            children: [
              ListTile(
                title: Text('${compact(total)} views across ${live.length} live Shorts'),
                subtitle: const Text('Counts come from the pipeline’s last stats refresh'),
              ),
              if (upcoming.isNotEmpty) const _Section('Scheduled'),
              for (final v in upcoming) _VideoTile(video: v, trailing: when(v.publishAt!)),
              const _Section('Live'),
              for (final v in live)
                _VideoTile(
                  video: v,
                  trailing: '${compact(v.views)} views\n${compact(v.likes)} likes',
                  flagPrivacy: true,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.video, required this.trailing, this.flagPrivacy = false});

  final Video video;
  final String trailing;

  /// Scheduled videos are private until publishAt by design; a live one that is still private needs a look.
  final bool flagPrivacy;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: flagPrivacy && video.privacy != null && video.privacy != 'public' ? Text(video.privacy!) : null,
    trailing: Text(trailing, textAlign: TextAlign.end, style: Theme.of(context).textTheme.bodySmall),
    onTap: () => launchUrl(video.url, mode: LaunchMode.externalApplication),
  );
}
