import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/providers.dart';

/// Loading, error and data states for a stream-backed list, in one place.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.data});

  final AsyncValue<T> value;
  final Widget Function(T) data;

  @override
  Widget build(BuildContext context) => value.when(
    data: data,
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (e, _) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Could not load: $e', textAlign: TextAlign.center),
      ),
    ),
  );
}

/// Sends a command and reports the outcome of queueing it; execution progress shows under Activity.
Future<void> sendCommand(
  BuildContext context,
  WidgetRef ref,
  String type,
  String label, [
  Map<String, dynamic> payload = const {},
]) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(repositoryProvider).send(type, payload);
    messenger.showSnackBar(SnackBar(content: Text('$label sent to the laptop')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$label failed: $e')));
  }
}

Future<bool> confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirm')),
        ],
      ),
    ) ??
    false;

String ago(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

String when(DateTime t) => DateFormat('EEE d MMM, HH:mm').format(t);
String compact(num? n) => n == null ? '-' : NumberFormat.compact().format(n);
String gigabytes(int? bytes) => bytes == null ? '-' : '${(bytes / 1e9).toStringAsFixed(1)} GB';
