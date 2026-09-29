import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shortsops/data/models.dart';
import 'package:shortsops/data/providers.dart';
import 'package:shortsops/data/repository.dart';
import 'package:shortsops/ui/queue_page.dart';

Topic topic(String id, String status, int position) =>
    Topic.fromRow({'id': id, 'topic': 'Topic $id', 'status': status, 'position': position, 'hook': 'Hook $id'});

void main() {
  testWidgets('queue groups topics and offers the right actions', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          topicsProvider.overrideWith(
            (ref) => Stream.value([
              topic('stuck', 'building', 0),
              topic('a', 'pending', 1),
              topic('b', 'pending', 2),
              topic('done', 'uploaded', 3),
              topic('s', 'skipped', 4),
            ]),
          ),
        ],
        child: const MaterialApp(home: QueuePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('Up next (2)'), findsOneWidget);
    expect(find.text('Skipped (1)'), findsOneWidget);
    expect(find.text('Topic done'), findsNothing, reason: 'uploaded topics are not part of the queue');

    await tester.tap(find.text('Topic a'));
    await tester.pumpAndSettle();
    expect(find.text('Hook a'), findsOneWidget);
    expect(find.text('Move to top'), findsOneWidget);
    expect(find.text('Build now'), findsOneWidget);

    await tester.tap(find.text('Topic stuck'));
    await tester.pumpAndSettle();
    expect(find.text('Return to queue'), findsOneWidget);
  });

  testWidgets('topics added while the laptop is away show as waiting, cancellable until picked up', (tester) async {
    final now = DateTime(2026, 9, 29, 12);
    Command command(String id, String status, String text) => Command.fromRow({
      'id': id,
      'type': 'add_topic',
      'payload': {'text': text},
      'status': status,
      'created_at': now.subtract(const Duration(hours: 2)).toUtc().toIso8601String(),
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          topicsProvider.overrideWith((ref) => Stream.value([topic('a', 'pending', 0)])),
          clockProvider.overrideWith((ref) => Stream.value(now)),
          commandsProvider.overrideWith(
            (ref) => Stream.value([
              command('c1', 'pending', 'Why flamingos are pink'),
              command('c2', 'claimed', 'Why cats purr'),
              command('c3', 'done', 'Already in the queue'),
            ]),
          ),
        ],
        child: const MaterialApp(home: QueuePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Why flamingos are pink'), findsOneWidget);
    expect(find.text('Waiting for the laptop · added 2 h ago'), findsOneWidget);
    expect(find.text('Adding to the queue…'), findsOneWidget);
    expect(find.text('Already in the queue'), findsNothing, reason: 'finished commands are real topics by now');
    expect(find.byTooltip('Cancel'), findsOneWidget, reason: 'only a command not yet claimed can be cancelled');
  });

  test('queue edits outlive a day offline; builds and uploads do not', () {
    expect(ShortsOpsRepository.ttlFor('add_topic'), greaterThan(const Duration(days: 5)));
    expect(ShortsOpsRepository.ttlFor('reorder_topics'), lessThan(const Duration(days: 7)), reason: 'database cap');
    for (final risky in ['make', 'publish_now', 'approve_upload', 'reset_stuck', 'research']) {
      expect(ShortsOpsRepository.ttlFor(risky), const Duration(hours: 1), reason: risky);
    }
  });
}
