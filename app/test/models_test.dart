import 'package:flutter_test/flutter_test.dart';
import 'package:shortsops/data/models.dart';
import 'package:shortsops/router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('agent counts as offline after three missed heartbeats', () {
    final now = DateTime(2026, 9, 28, 12);
    final status = AgentStatus.fromRow({
      'last_seen': now.toUtc().subtract(const Duration(minutes: 2)).toIso8601String(),
      'paused': false,
    });
    expect(status.isOnline(now), isTrue);
    expect(status.isOnline(now.add(const Duration(minutes: 2))), isFalse);
  });

  test('a video without publish_at, or with one in the past, is live', () {
    final now = DateTime(2026, 9, 28, 12);
    Video v(String? at) => Video.fromRow({'video_id': 'x', 'title': 't', 'publish_at': at});
    expect(v(null).isLive(now), isTrue);
    expect(v(now.toUtc().subtract(const Duration(hours: 1)).toIso8601String()).isLive(now), isTrue);
    expect(v(now.toUtc().add(const Duration(hours: 1)).toIso8601String()).isLive(now), isFalse);
    expect(v(null).url.toString(), 'https://youtube.com/shorts/x');
  });

  test('building and failed topics are stuck', () {
    Topic t(String s) => Topic.fromRow({'id': 'a', 'topic': 'A', 'status': s, 'position': 0});
    expect(['pending', 'building', 'failed', 'skipped'].map((s) => t(s).isStuck), [false, true, true, false]);
  });

  test('only the owner role passes the router gate', () {
    Session session(Map<String, dynamic> meta) => Session(
      accessToken: 'x',
      tokenType: 'bearer',
      user: User(id: 'u', appMetadata: meta, userMetadata: const {}, aud: 'authenticated', createdAt: ''),
    );
    expect(isOwner(session({'role': 'owner'})), isTrue);
    expect(isOwner(session({'role': 'agent'})), isFalse);
    expect(isOwner(session({})), isFalse);
    expect(isOwner(null), isFalse);
  });
}
