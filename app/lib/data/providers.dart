import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'repository.dart';

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final repositoryProvider = Provider<ShortsOpsRepository>((ref) => ShortsOpsRepository(ref.watch(supabaseProvider)));

final topicsProvider = StreamProvider<List<Topic>>((ref) => ref.watch(repositoryProvider).topics());
final videosProvider = StreamProvider<List<Video>>((ref) => ref.watch(repositoryProvider).videos());
final agentStatusProvider = StreamProvider<AgentStatus?>((ref) => ref.watch(repositoryProvider).agentStatus());
final commandsProvider = StreamProvider<List<Command>>((ref) => ref.watch(repositoryProvider).commands());
final runsProvider = StreamProvider<List<Run>>((ref) => ref.watch(repositoryProvider).runs());
final eventsProvider = StreamProvider<List<AppEvent>>((ref) => ref.watch(repositoryProvider).events());

/// Ticks every 30 s so "online" and relative times stay current without new data arriving.
final clockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now());
});

/// Videos uploaded privately for review, newest first; the laptop's mirror is the only source that knows about holds.
final heldVideosProvider = Provider<List<Video>>(
  (ref) => (ref.watch(videosProvider).value ?? const <Video>[]).where((v) => v.held).toList(),
);

final factCheckProvider = FutureProvider.family<String?, String>(
  (ref, buildId) => ref.watch(repositoryProvider).factCheck(buildId),
);
