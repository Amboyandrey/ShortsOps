"""Pure translations from the pipeline's local files to ShortsOps table rows."""

from __future__ import annotations

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

UPLOAD_COST = 1600  # YouTube Data API units per upload
DAILY_QUOTA = 10000
CONFIG_KEYS = {  # the config.yaml subset the app shows and may later edit
    "channel": ("niche", "subniches", "posts_per_day", "publish_times", "timezone"),
    "script": ("target_seconds", "max_seconds"),
    "voice": ("voice", "rate"),
    "upload": ("privacy",),
}


def topic_rows(topics: list[dict]) -> list[dict]:
    return [
        {
            "id": t["id"],
            "topic": t["topic"],
            "status": t.get("status", "pending"),
            "position": i,
            "subniche": t.get("subniche") or None,
            "hook": t.get("hook"),
            "why_it_works": t.get("why_it_works"),
            "fact_check_notes": t.get("fact_check_notes"),
            "inspired_by": t.get("inspired_by"),
            "video_id": t.get("video_id"),
            "out_dir": t.get("out_dir"),
            "created_at": t.get("created"),
            "format": t.get("format") or "story",
            "rank_count": t.get("rank_count") or None,
            "ranking_criterion": t.get("ranking_criterion") or None,
        }
        for i, t in enumerate(topics)
    ]


def video_rows(history: list[dict]) -> list[dict]:
    rows = []
    for h in history:
        if not h.get("video_id"):
            continue
        rows.append(
            {
                "video_id": h["video_id"],
                "topic_id": h.get("topic_id"),
                "build_id": (h.get("out_dir") or "").rstrip("/").rsplit("/", 1)[-1] or None,
                "topic": h.get("topic"),
                "title": h.get("title") or h.get("topic") or h["video_id"],
                "publish_at": h.get("publish_at"),
                "privacy": h.get("privacy"),
                "views": h.get("views"),
                "likes": h.get("likes"),
                "comments": h.get("comments"),
                "stats_updated_at": h.get("stats_updated"),
                "created_at": h.get("created"),
                "held": bool(h.get("held")),
                "confidence": h.get("confidence"),
            }
        )
    return rows


def build_row(build_id: str, meta: dict, size_bytes: int, created_at: str | None) -> dict:
    conf = meta.get("confidence")
    return {
        "id": build_id,
        "topic_id": (meta.get("topic") or {}).get("id"),
        "title": meta.get("title") or build_id,
        "description": meta.get("description"),
        "tags": list(meta.get("tags") or []),
        "confidence": int(conf) if isinstance(conf, (int, float)) else None,
        "fact_check": meta.get("fact_check"),
        "duration_s": meta.get("duration"),
        "mood": meta.get("mood"),
        "video_id": meta.get("video_id"),
        "size_bytes": size_bytes,
        "created_at": created_at,
    }


def competitor_rows(competitors: dict) -> list[dict]:
    return [
        {
            "ref": c["ref"],
            "name": c.get("name") or c["ref"],
            "top10_mean": c.get("top10_mean"),
            "median_views": c.get("median_views"),
            "max_views": c.get("max_views"),
            "top": c.get("top") or [],
        }
        for c in competitors.get("channels", [])
    ]


def config_subset(config: dict) -> dict:
    return {section: {k: config.get(section, {}).get(k) for k in keys} for section, keys in CONFIG_KEYS.items()}


def quota_units_used(history: list[dict], now: datetime) -> int:
    """Upload units spent since the quota reset at midnight US Pacific (mirrors facts_shorts.upload.quota_used)."""
    pac = ZoneInfo("America/Los_Angeles")
    now_p = now.astimezone(pac)
    reset = now_p.replace(hour=0, minute=0, second=0, microsecond=0)
    if now_p < reset:
        reset -= timedelta(days=1)
    n = sum(1 for h in history if h.get("created") and datetime.fromisoformat(h["created"]) >= reset)
    return n * UPLOAD_COST


def uploads_left(units_used: int, reserve: int = 400) -> int:
    return max(0, (DAILY_QUOTA - reserve - units_used) // UPLOAD_COST)
