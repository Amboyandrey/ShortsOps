import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/providers.dart';
import 'ui/activity_page.dart';
import 'ui/dashboard_page.dart';
import 'ui/queue_page.dart';
import 'ui/shell.dart';
import 'ui/sign_in_page.dart';
import 'ui/videos_page.dart';

/// Only a signed-in user whose app_metadata.role is 'owner' gets past sign-in; RLS enforces the same server-side.
bool isOwner(Session? session) => session?.user.appMetadata['role'] == 'owner';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(supabaseProvider).auth;
  final refresh = _AuthRefresh(auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);
  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = isOwner(auth.currentSession);
      final atSignIn = state.matchedLocation == '/sign-in';
      if (!signedIn) return atSignIn ? null : '/sign-in';
      return atSignIn ? '/dashboard' : null;
    },
    routes: [
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInPage()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/dashboard', builder: (_, _) => const DashboardPage())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/queue', builder: (_, _) => const QueuePage())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/videos', builder: (_, _) => const VideosPage())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/activity', builder: (_, _) => const ActivityPage())],
          ),
        ],
      ),
    ],
  );
});

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<AuthState> changes) {
    _sub = changes.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
