import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'models.dart';
import 'youtube.dart';

/// Which Google account, if any, is linked for live YouTube data; null when not connected.
class YouTubeConnection extends AsyncNotifier<GoogleSignInAccount?> {
  static const _scopes = [YouTubeApi.scope];

  /// Native Google sign-in only; the web preview keeps showing the laptop's mirror.
  static bool get supported => !kIsWeb && AppConfig.googleServerClientId.isNotEmpty;

  GoogleSignIn get _google => GoogleSignIn.instance;

  @override
  Future<GoogleSignInAccount?> build() async {
    if (!supported) return null;
    await _google.initialize(serverClientId: AppConfig.googleServerClientId);
    final sub = _google.authenticationEvents.listen((event) {
      state = AsyncData(switch (event) {
        GoogleSignInAuthenticationEventSignIn(:final user) => user,
        GoogleSignInAuthenticationEventSignOut() => null,
      });
    }, onError: (Object _) {});
    ref.onDispose(sub.cancel);
    // Restores a previous connection without any UI; returns null the first time.
    return await _google.attemptLightweightAuthentication();
  }

  /// Must run from a button press: Google shows the account picker and the YouTube consent screen.
  Future<void> connect() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = await _google.authenticate(scopeHint: _scopes);
      await user.authorizationClient.authorizeScopes(_scopes);
      return user;
    });
  }

  Future<void> disconnect() async {
    await _google.disconnect();
    state = const AsyncData(null);
  }

  /// A current access token, silently renewed by Google Play services; null means consent is needed again.
  Future<String?> accessToken() async {
    final user = state.value;
    if (user == null) return null;
    final auth = await user.authorizationClient.authorizationForScopes(_scopes);
    return auth?.accessToken;
  }
}

final youTubeConnectionProvider = AsyncNotifierProvider<YouTubeConnection, GoogleSignInAccount?>(YouTubeConnection.new);

/// Live channel videos; loads once connected and on every pull-to-refresh.
class YouTubeVideos extends AsyncNotifier<List<Video>?> {
  @override
  Future<List<Video>?> build() async {
    final account = await ref.watch(youTubeConnectionProvider.future);
    if (account == null) return null;
    return _fetch();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_fetch);
  }

  Future<List<Video>> _fetch() async {
    final token = await ref.read(youTubeConnectionProvider.notifier).accessToken();
    if (token == null) throw const YouTubeApiException(401, 'YouTube access expired; reconnect');
    final client = http.Client();
    try {
      return await YouTubeApi(client, token).channelVideos();
    } finally {
      client.close();
    }
  }
}

final youTubeVideosProvider = AsyncNotifierProvider<YouTubeVideos, List<Video>?>(YouTubeVideos.new);

/// When the live data was last fetched, for the "updated" line.
final youTubeFetchedAtProvider = Provider<DateTime?>((ref) {
  final videos = ref.watch(youTubeVideosProvider);
  return videos.hasValue && videos.value != null ? DateTime.now() : null;
});
