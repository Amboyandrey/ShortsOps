from datetime import UTC, datetime

from shortsops_agent import mapping


def test_topic_rows_keep_queue_order_and_default_status():
    rows = mapping.topic_rows([{"id": "a", "topic": "A"}, {"id": "b", "topic": "B", "status": "built", "subniche": ""}])
    assert [(r["id"], r["position"], r["status"]) for r in rows] == [("a", 0, "pending"), ("b", 1, "built")]
    assert rows[1]["subniche"] is None


def test_video_rows_skip_entries_without_a_video_and_derive_build_id():
    rows = mapping.video_rows(
        [
            {"topic": "no upload"},
            {"video_id": "v1", "title": "T", "out_dir": "/x/data/out/20260928_1035_abc/"},
        ]
    )
    assert len(rows) == 1 and rows[0]["build_id"] == "20260928_1035_abc"


def test_build_row_tolerates_missing_fields():
    row = mapping.build_row("b1", {"confidence": 82.0, "topic": {"id": "t"}}, 10, None)
    assert row["confidence"] == 82 and row["topic_id"] == "t" and row["title"] == "b1" and row["tags"] == []


def test_config_subset_only_exposes_allowlisted_keys():
    cfg = {"channel": {"posts_per_day": 4, "secret_thing": 1}, "upload": {"privacy": "public", "category_id": "27"}}
    sub = mapping.config_subset(cfg)
    assert sub["channel"]["posts_per_day"] == 4 and "secret_thing" not in sub["channel"]
    assert sub["upload"] == {"privacy": "public"}


def test_quota_counts_uploads_since_pacific_midnight():
    now = datetime(2026, 9, 28, 20, 0, tzinfo=UTC)  # 13:00 in Los Angeles
    history = [
        {"created": "2026-09-28T08:00:00+00:00"},  # 01:00 LA today
        {"created": "2026-09-28T06:00:00+00:00"},  # 23:00 LA yesterday
        {"created": "2026-09-28T19:00:00+00:00"},
    ]
    used = mapping.quota_units_used(history, now)
    assert used == 2 * mapping.UPLOAD_COST
    assert mapping.uploads_left(used) == 4


def test_topic_rows_carry_format_and_default_old_topics_to_story():
    rows = mapping.topic_rows(
        [
            {"id": "old", "topic": "Why cats purr"},
            {"id": "r", "topic": "Top 5 densest", "format": "ranking", "rank_count": 5, "ranking_criterion": "g/cm³"},
        ]
    )
    assert (rows[0]["format"], rows[0]["rank_count"]) == ("story", None)
    assert (rows[1]["format"], rows[1]["rank_count"], rows[1]["ranking_criterion"]) == ("ranking", 5, "g/cm³")


def test_video_rows_carry_the_held_flag_and_confidence():
    rows = mapping.video_rows(
        [
            {"video_id": "a", "title": "A"},
            {"video_id": "b", "title": "B", "held": True, "confidence": 60, "privacy": "private"},
        ]
    )
    assert [(r["held"], r["confidence"]) for r in rows] == [(False, None), (True, 60)]
