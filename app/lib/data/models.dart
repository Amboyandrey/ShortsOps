/// Row types for the ShortsOps tables; each mirrors one table in supabase/migrations.
library;

DateTime? _ts(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

class Topic {
  const Topic({
    required this.id,
    required this.topic,
    required this.status,
    required this.position,
    this.subniche,
    this.hook,
    this.whyItWorks,
    this.factCheckNotes,
    this.videoId,
    this.format = 'story',
    this.rankCount,
    this.rankingCriterion,
  });

  factory Topic.fromRow(Map<String, dynamic> r) => Topic(
    id: r['id'] as String,
    topic: r['topic'] as String,
    status: r['status'] as String,
    position: r['position'] as int,
    subniche: r['subniche'] as String?,
    hook: r['hook'] as String?,
    whyItWorks: r['why_it_works'] as String?,
    factCheckNotes: r['fact_check_notes'] as String?,
    videoId: r['video_id'] as String?,
    format: r['format'] as String? ?? 'story',
    rankCount: r['rank_count'] as int?,
    rankingCriterion: r['ranking_criterion'] as String?,
  );

  final String id;
  final String topic;
  final String status;
  final int position;
  final String? subniche;
  final String? hook;
  final String? whyItWorks;
  final String? factCheckNotes;
  final String? videoId;

  /// 'story' (one fact told as a mini story) or 'ranking' (a countdown of measured entries).
  final String format;
  final int? rankCount;
  final String? rankingCriterion;

  bool get isRanking => format == 'ranking';

  /// Short label for the queue, e.g. 'Top 5'; the writer picks the size when none was given.
  String get formatLabel => isRanking ? (rankCount != null ? 'Top $rankCount' : 'Ranking') : 'Story';

  bool get isStuck => status == 'building' || status == 'failed';
}

class Video {
  const Video({
    required this.videoId,
    required this.title,
    this.publishAt,
    this.views,
    this.likes,
    this.comments,
    this.privacy,
  });

  factory Video.fromRow(Map<String, dynamic> r) => Video(
    videoId: r['video_id'] as String,
    title: r['title'] as String,
    publishAt: _ts(r['publish_at']),
    views: r['views'] as int?,
    likes: r['likes'] as int?,
    comments: r['comments'] as int?,
    privacy: r['privacy'] as String?,
  );

  final String videoId;
  final String title;
  final DateTime? publishAt;
  final int? views;
  final int? likes;
  final int? comments;
  final String? privacy;

  bool isLive(DateTime now) => publishAt == null || !publishAt!.isAfter(now);
  Uri get url => Uri.parse('https://youtube.com/shorts/$videoId');
}

class AgentStatus {
  const AgentStatus({
    required this.lastSeen,
    required this.paused,
    this.version,
    this.cronInstalled,
    this.lastRunDate,
    this.runningCommand,
    this.quotaUnitsUsed,
    this.uploadsLeft,
    this.diskFreeBytes,
    this.outDirBytes,
  });

  factory AgentStatus.fromRow(Map<String, dynamic> r) => AgentStatus(
    lastSeen: _ts(r['last_seen'])!,
    paused: r['paused'] as bool,
    version: r['version'] as String?,
    cronInstalled: r['cron_installed'] as bool?,
    lastRunDate: r['last_run_date'] as String?,
    runningCommand: r['running_command'] as String?,
    quotaUnitsUsed: r['quota_units_used'] as int?,
    uploadsLeft: r['uploads_left'] as int?,
    diskFreeBytes: r['disk_free_bytes'] as int?,
    outDirBytes: r['out_dir_bytes'] as int?,
  );

  /// The agent heartbeats every 60 s; three missed beats means the laptop is off or offline.
  static const offlineAfter = Duration(minutes: 3);

  final DateTime lastSeen;
  final bool paused;
  final String? version;
  final bool? cronInstalled;
  final String? lastRunDate;
  final String? runningCommand;
  final int? quotaUnitsUsed;
  final int? uploadsLeft;
  final int? diskFreeBytes;
  final int? outDirBytes;

  bool isOnline(DateTime now) => now.difference(lastSeen) < offlineAfter;
}

class Command {
  const Command({
    required this.id,
    required this.type,
    required this.payload,
    required this.status,
    required this.createdAt,
    this.finishedAt,
    this.error,
  });

  factory Command.fromRow(Map<String, dynamic> r) => Command(
    id: r['id'] as String,
    type: r['type'] as String,
    payload: Map<String, dynamic>.from(r['payload'] as Map? ?? const {}),
    status: r['status'] as String,
    createdAt: _ts(r['created_at'])!,
    finishedAt: _ts(r['finished_at']),
    error: r['error'] as String?,
  );

  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final String status;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final String? error;

  bool get isOpen => status == 'pending' || status == 'claimed';
}

class Run {
  const Run({
    required this.id,
    required this.kind,
    required this.status,
    required this.startedAt,
    this.step,
    this.error,
  });

  factory Run.fromRow(Map<String, dynamic> r) => Run(
    id: r['id'] as String,
    kind: r['kind'] as String,
    status: r['status'] as String,
    startedAt: _ts(r['started_at'])!,
    step: r['step'] as String?,
    error: r['error'] as String?,
  );

  final String id;
  final String kind;
  final String status;
  final DateTime startedAt;
  final String? step;
  final String? error;
}

class AppEvent {
  const AppEvent({required this.id, required this.kind, required this.title, required this.createdAt, this.body});

  factory AppEvent.fromRow(Map<String, dynamic> r) => AppEvent(
    id: r['id'] as int,
    kind: r['kind'] as String,
    title: r['title'] as String,
    createdAt: _ts(r['created_at'])!,
    body: r['body'] as String?,
  );

  final int id;
  final String kind;
  final String title;
  final DateTime createdAt;
  final String? body;
}
