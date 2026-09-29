import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Read-only YouTube Data API calls for the signed-in channel; about 9 quota units per refresh.
class YouTubeApi {
  YouTubeApi(this._http, this._accessToken);

  static const scope = 'https://www.googleapis.com/auth/youtube.readonly';
  static const _base = 'https://www.googleapis.com/youtube/v3';

  /// Newest uploads first; four pages of the uploads playlist cover months of daily Shorts.
  static const maxVideos = 200;

  final http.Client _http;
  final String _accessToken;

  Future<List<Video>> channelVideos() async {
    final channel = await _get('channels', {'part': 'contentDetails', 'mine': 'true'});
    final items = channel['items'] as List? ?? const [];
    if (items.isEmpty) throw const YouTubeApiException(404, 'This Google account has no YouTube channel');
    final uploads = items.first['contentDetails']['relatedPlaylists']['uploads'] as String;

    final ids = <String>[];
    String? page;
    do {
      final res = await _get('playlistItems', {
        'part': 'contentDetails',
        'playlistId': uploads,
        'maxResults': '50',
        'pageToken': ?page,
      });
      ids.addAll((res['items'] as List).map((i) => i['contentDetails']['videoId'] as String));
      page = res['nextPageToken'] as String?;
    } while (page != null && ids.length < maxVideos);

    final videos = <Video>[];
    for (var i = 0; i < ids.length; i += 50) {
      final batch = ids.sublist(i, i + 50 > ids.length ? ids.length : i + 50);
      final res = await _get('videos', {'part': 'snippet,statistics,status', 'id': batch.join(',')});
      videos.addAll((res['items'] as List).map((v) => videoFromApi(v as Map<String, dynamic>)));
    }
    return videos;
  }

  Future<Map<String, dynamic>> _get(String path, Map<String, String> query) async {
    final res = await _http.get(
      Uri.parse('$_base/$path').replace(queryParameters: query),
      headers: {'Authorization': 'Bearer $_accessToken'},
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      final message = (body['error'] as Map?)?['message'] as String? ?? 'HTTP ${res.statusCode}';
      throw YouTubeApiException(res.statusCode, message);
    }
    return body;
  }
}

/// Scheduled videos are private with a future publishAt; everything else counts from its publish time.
Video videoFromApi(Map<String, dynamic> v) {
  final snippet = v['snippet'] as Map<String, dynamic>;
  final status = v['status'] as Map<String, dynamic>? ?? const {};
  final stats = v['statistics'] as Map<String, dynamic>? ?? const {};
  final scheduled = status['publishAt'] as String?;
  int? count(String key) => int.tryParse(stats[key] as String? ?? '');
  return Video(
    videoId: v['id'] as String,
    title: (snippet['title'] as String).replaceAll(RegExp(r'\s*#shorts\s*$', caseSensitive: false), ''),
    publishAt: DateTime.parse(scheduled ?? snippet['publishedAt'] as String).toLocal(),
    views: count('viewCount'),
    likes: count('likeCount'),
    comments: count('commentCount'),
    privacy: scheduled != null ? 'scheduled' : status['privacyStatus'] as String?,
  );
}

class YouTubeApiException implements Exception {
  const YouTubeApiException(this.status, this.message);

  final int status;
  final String message;

  /// 401 means the access token expired or was revoked; a fresh authorization fixes it.
  bool get needsReauth => status == 401;

  @override
  String toString() => 'YouTube: $message';
}
