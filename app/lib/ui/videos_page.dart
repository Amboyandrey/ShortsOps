import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';
import '../data/providers.dart';
import '../data/youtube.dart';
import '../data/youtube_connection.dart';
import 'common.dart';

class VideosPage extends ConsumerWidget {
  const VideosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(youTubeConnectionProvider);
    final connected = connection.value != null;
    final live = ref.watch(youTubeVideosProvider);
    // Live YouTube data when we have it; the laptop's mirror otherwise (not connected, or a failed fetch).
    final fromYouTube = connected && live.value != null;
    final source = fromYouTube ? AsyncData(live.value!) : ref.watch(videosProvider);

    Future<void> refresh() async {
      if (connected) {
        await ref.read(youTubeVideosProvider.notifier).refresh();
      } else {
        await sendCommand(context, ref, 'refresh_stats', 'Stats refresh');
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Videos'),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: refresh),
          if (connected)
            PopupMenuButton<String>(
              onSelected: (_) => ref.read(youTubeConnectionProvider.notifier).disconnect(),
              itemBuilder: (_) => [const PopupMenuItem(value: 'disconnect', child: Text('Disconnect YouTube'))],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: AsyncBody(
          value: source,
          data: (videos) => _VideoList(
            videos: videos,
            header: _SourceBanner(
              fromYouTube: fromYouTube,
              connecting: connection.isLoading,
              error: live.error,
              connectError: connection.error,
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceBanner extends ConsumerWidget {
  const _SourceBanner({required this.fromYouTube, required this.connecting, this.error, this.connectError});

  final bool fromYouTube;
  final bool connecting;
  final Object? error;
  final Object? connectError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (fromYouTube) {
      final at = ref.watch(youTubeFetchedAtProvider);
      return ListTile(
        dense: true,
        leading: const Icon(Icons.bolt, color: Colors.red),
        title: const Text('Live from YouTube'),
        subtitle: Text(at == null ? 'Pull down to refresh' : 'Updated ${DateFormat.Hm().format(at)} · pull to refresh'),
      );
    }
    final reauth = error is YouTubeApiException && (error as YouTubeApiException).needsReauth;
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error != null ? 'Could not reach YouTube: $error' : 'Showing the laptop’s copy',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              YouTubeConnection.supported
                  ? 'Connect YouTube to see live views for every video on your channel, even when the laptop is off.'
                  : 'Live YouTube data is available in the Android app.',
              style: theme.textTheme.bodySmall,
            ),
            if (connectError != null) ...[
              const SizedBox(height: 8),
              Text(describeConnectError(connectError!), style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (YouTubeConnection.supported) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: connecting
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.smart_display),
                label: Text(reauth || error != null ? 'Reconnect YouTube' : 'Connect YouTube'),
                onPressed: connecting ? null : () => ref.read(youTubeConnectionProvider.notifier).connect(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VideoList extends ConsumerWidget {
  const _VideoList({required this.videos, required this.header});

  final List<Video> videos;
  final Widget header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final upcoming = videos.where((v) => !v.isLive(now)).toList()..sort((a, b) => a.publishAt!.compareTo(b.publishAt!));
    final live = videos.where((v) => v.isLive(now)).toList()
      ..sort((a, b) => (b.publishAt ?? now).compareTo(a.publishAt ?? now));
    final total = live.fold<int>(0, (sum, v) => sum + (v.views ?? 0));
    // AlwaysScrollable so pull-to-refresh works even when the list is short.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        header,
        ListTile(title: Text('${compact(total)} views across ${live.length} live Shorts')),
        if (upcoming.isNotEmpty) const _Section('Scheduled'),
        for (final v in upcoming) _VideoTile(video: v, trailing: when(v.publishAt!)),
        const _Section('Live'),
        for (final v in live)
          _VideoTile(video: v, trailing: '${compact(v.views)} views\n${compact(v.likes)} likes', flagPrivacy: true),
      ],
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
