import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// The only place the app talks to Supabase: live table streams in, commands out.
class ShortsOpsRepository {
  ShortsOpsRepository(this._db);

  final SupabaseClient _db;

  Stream<List<Topic>> topics() => _db
      .from('topics')
      .stream(primaryKey: ['id'])
      .order('position', ascending: true)
      .map((rows) => rows.map(Topic.fromRow).toList());

  Stream<List<Video>> videos() => _db
      .from('videos')
      .stream(primaryKey: ['video_id'])
      .order('publish_at')
      .map((rows) => rows.map(Video.fromRow).toList());

  Stream<AgentStatus?> agentStatus() => _db
      .from('agent_status')
      .stream(primaryKey: ['id'])
      .map((rows) => rows.isEmpty ? null : AgentStatus.fromRow(rows.first));

  Stream<List<Command>> commands() => _db
      .from('commands')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .limit(50)
      .map((rows) => rows.map(Command.fromRow).toList());

  Stream<List<Run>> runs() => _db
      .from('runs')
      .stream(primaryKey: ['id'])
      .order('started_at')
      .limit(20)
      .map((rows) => rows.map(Run.fromRow).toList());

  Stream<List<AppEvent>> events() => _db
      .from('events')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .limit(50)
      .map((rows) => rows.map(AppEvent.fromRow).toList());

  /// Queues a command for the laptop agent; it expires unless picked up within [ttl].
  Future<void> send(String type, [Map<String, dynamic> payload = const {}, Duration ttl = const Duration(hours: 1)]) =>
      _db.from('commands').insert({
        'type': type,
        'payload': payload,
        'expires_at': DateTime.now().toUtc().add(ttl).toIso8601String(),
      });

  Future<void> cancel(String commandId) =>
      _db.from('commands').update({'status': 'cancelled'}).eq('id', commandId).eq('status', 'pending');
}
