import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shortsops/data/models.dart';
import 'package:shortsops/data/providers.dart';
import 'package:shortsops/ui/held_review.dart';
import 'package:shortsops/ui/videos_page.dart';

final now = DateTime(2026, 9, 30, 12);

Video video(String id, {bool held = false}) => Video.fromRow({
  'video_id': id,
  'title': 'Video $id',
  'publish_at': held ? null : now.subtract(const Duration(days: 1)).toUtc().toIso8601String(),
  'views': 10,
  'privacy': held ? 'private' : 'public',
  'held': held,
  'confidence': held ? 60 : 90,
  'build_id': 'build_$id',
});

List<Override> overrides() => [
  videosProvider.overrideWith((ref) => Stream.value([video('live1'), video('bite', held: true)])),
  clockProvider.overrideWith((ref) => Stream.value(now)),
  factCheckProvider.overrideWith((ref, buildId) async => 'Bite-force figures are estimates for $buildId.'),
];

void main() {
  testWidgets('a held video is listed once, under review, with its notes and publish actions', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: const MaterialApp(home: VideosPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Held for review (1)'), findsOneWidget);
    expect(find.text('Video bite'), findsOneWidget, reason: 'not repeated in the Live list');
    expect(find.text('Private · fact-check confidence 60'), findsOneWidget);
    expect(find.text('10 views across 1 live Shorts'), findsOneWidget, reason: 'held videos are not counted as live');

    await tester.tap(find.text('Video bite'));
    await tester.pumpAndSettle();
    expect(find.text('Bite-force figures are estimates for build_bite.'), findsOneWidget);
    expect(find.text('Watch on YouTube'), findsOneWidget);
    expect(find.text('Publish next slot'), findsOneWidget);
    expect(find.text('Publish now'), findsOneWidget);
  });

  testWidgets('the Status reminder appears only while something is held', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: const MaterialApp(home: Scaffold(body: HeldReminderCard())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 Short needs your review'), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(), // a fresh scope: Riverpod forbids changing overrides on an existing one
        overrides: [
          videosProvider.overrideWith((ref) => Stream.value([video('live1')])),
        ],
        child: const MaterialApp(home: Scaffold(body: HeldReminderCard())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('need'), findsNothing);
  });
}
