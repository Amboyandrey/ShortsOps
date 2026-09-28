import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!AppConfig.isComplete) {
    runApp(const _MissingConfig());
    return;
  }
  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabasePublishableKey);
  runApp(const ProviderScope(child: ShortsOpsApp()));
}

class ShortsOpsApp extends ConsumerWidget {
  const ShortsOpsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const seed = Color(0xFF10B981);
    return MaterialApp.router(
      title: 'ShortsOps',
      routerConfig: ref.watch(routerProvider),
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
    );
  }
}

class _MissingConfig extends StatelessWidget {
  const _MissingConfig();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Build with --dart-define-from-file=env.json (SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY).'),
        ),
      ),
    ),
  );
}
