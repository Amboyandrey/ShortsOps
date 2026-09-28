import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shortsops/data/models.dart';
import 'package:shortsops/data/providers.dart';
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
}
