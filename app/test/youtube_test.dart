import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shortsops/data/youtube.dart';

Map<String, dynamic> apiVideo(String id, {String? publishAt, String privacy = 'public', String views = '10'}) => {
  'id': id,
  'snippet': {'title': 'Video $id #Shorts', 'publishedAt': '2026-09-20T01:00:00Z'},
  'status': {'privacyStatus': privacy, 'publishAt': ?publishAt},
  'statistics': {'viewCount': views, 'likeCount': '2', 'commentCount': '0'},
};

void main() {
  test('walks channel -> uploads playlist pages -> video details', () async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add(req.url.pathSegments.last);
      expect(req.headers['Authorization'], 'Bearer token');
      final q = req.url.queryParameters;
      final body = switch (req.url.pathSegments.last) {
        'channels' => {
          'items': [
            {
              'contentDetails': {
                'relatedPlaylists': {'uploads': 'UU1'},
              },
            },
          ],
        },
        'playlistItems' when q['pageToken'] == null => {
          'items': [
            {
              'contentDetails': {'videoId': 'a'},
            },
          ],
          'nextPageToken': 'p2',
        },
        'playlistItems' => {
          'items': [
            {
              'contentDetails': {'videoId': 'b'},
            },
          ],
        },
        'videos' => {
          'items': [apiVideo('a', views: '1234'), apiVideo('b', publishAt: '2026-10-01T01:00:00Z', privacy: 'private')],
        },
        _ => throw StateError('unexpected ${req.url}'),
      };
      expect(q['id'], anyOf(isNull, 'a,b'));
      return http.Response(jsonEncode(body), 200);
    });

    final videos = await YouTubeApi(client, 'token').channelVideos();

    expect(calls, ['channels', 'playlistItems', 'playlistItems', 'videos']);
    expect(videos.map((v) => v.title), ['Video a', 'Video b'], reason: 'the #Shorts suffix is dropped');
    expect(videos[0].views, 1234);
    expect(videos[1].privacy, 'scheduled');
    expect(videos[1].publishAt, DateTime.utc(2026, 10, 1, 1).toLocal());
  });

  test('an expired token surfaces as needsReauth', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'error': {'message': 'Invalid Credentials'},
        }),
        401,
      ),
    );
    await expectLater(
      YouTubeApi(client, 'old').channelVideos(),
      throwsA(isA<YouTubeApiException>().having((e) => e.needsReauth, 'needsReauth', isTrue)),
    );
  });

  test('an account without a channel gets a clear error', () async {
    final client = MockClient((_) async => http.Response(jsonEncode({'items': []}), 200));
    await expectLater(
      YouTubeApi(client, 't').channelVideos(),
      throwsA(isA<YouTubeApiException>().having((e) => e.message, 'message', contains('no YouTube channel'))),
    );
  });
}
