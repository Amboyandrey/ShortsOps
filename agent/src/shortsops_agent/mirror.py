"""Keeps the ShortsOps tables equal to the pipeline's local files, writing only rows that changed."""

from __future__ import annotations

import hashlib
import json
import logging
from datetime import UTC, datetime
from pathlib import Path

import yaml
from supabase import AsyncClient

from . import mapping
from .settings import Settings

log = logging.getLogger(__name__)
CHUNK = 200
LOW_CONFIDENCE = 70  # the pipeline refuses to upload below this


def _load_json(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return default
    except json.JSONDecodeError:
        # caught mid-write despite the pipeline's atomic replace; the next change event resyncs
        log.warning("skipping unreadable %s", path.name)
        return None


def _digest(row: dict) -> str:
    return hashlib.sha256(json.dumps(row, sort_keys=True, default=str).encode()).hexdigest()


def _dir_size(path: Path) -> int:
    return sum(f.stat().st_size for f in path.rglob("*") if f.is_file())


class Mirror:
    def __init__(self, client: AsyncClient, settings: Settings):
        self.db = client
        self.s = settings
        self.known: dict[str, dict[str, str]] = {}  # table -> key -> row digest
        self.build_sizes: dict[str, tuple[float, int]] = {}  # build id -> (meta mtime, bytes)
        self.primed = False  # events fire only for changes seen after the first full sync

    async def _sync(self, table: str, key: str, rows: list[dict]) -> list[dict]:
        """Upsert changed rows, delete vanished ones; returns rows that were new to the table."""
        if table not in self.known:
            res = await self.db.table(table).select(key).execute()
            self.known[table] = {r[key]: "" for r in res.data}
        known = self.known[table]
        current = {r[key]: _digest(r) for r in rows}
        changed = [r for r in rows if known.get(r[key]) != current[r[key]]]
        added = [r for r in rows if r[key] not in known]
        stamp = datetime.now(UTC).isoformat()
        for i in range(0, len(changed), CHUNK):
            batch = [{**r, "synced_at": stamp} for r in changed[i : i + CHUNK]]
            await self.db.table(table).upsert(batch, on_conflict=key).execute()
        gone = [k for k in known if k not in current]
        for i in range(0, len(gone), CHUNK):
            await self.db.table(table).delete().in_(key, gone[i : i + CHUNK]).execute()
        self.known[table] = current
        if changed or gone:
            log.info("%s: %d upserted, %d deleted", table, len(changed), len(gone))
        return added

    async def topics(self) -> None:
        data = _load_json(self.s.data / "topics.json", [])
        if data is not None:
            await self._sync("topics", "id", mapping.topic_rows(data))

    async def videos(self) -> None:
        data = _load_json(self.s.data / "history.json", [])
        if data is not None:
            await self._sync("videos", "video_id", mapping.video_rows(data))

    async def competitors(self) -> None:
        data = _load_json(self.s.data / "competitors.json", {"channels": []})
        if data is not None:
            await self._sync("competitors", "ref", mapping.competitor_rows(data))

    async def config(self) -> None:
        try:
            cfg = yaml.safe_load((self.s.pipeline_dir / "config.yaml").read_text(encoding="utf-8"))
        except (OSError, yaml.YAMLError) as e:
            log.warning("config.yaml unreadable: %s", e)
            return
        row = {"id": 1, "config": mapping.config_subset(cfg)}
        await self._sync("config_snapshot", "id", [row])

    async def builds(self) -> None:
        rows = []
        for meta_path in sorted((self.s.data / "out").glob("*/meta.json")):
            meta = _load_json(meta_path, None)
            if meta is None:
                continue
            build = meta_path.parent
            mtime = meta_path.stat().st_mtime
            cached = self.build_sizes.get(build.name)
            size = cached[1] if cached and cached[0] == mtime else _dir_size(build)
            self.build_sizes[build.name] = (mtime, size)
            created = datetime.fromtimestamp(build.stat().st_ctime, UTC).isoformat()
            rows.append(mapping.build_row(build.name, meta, size, created))
        added = await self._sync("builds", "id", rows)
        if self.primed:
            for b in added:
                await self._announce_build(b)

    async def _announce_build(self, b: dict) -> None:
        conf = b.get("confidence")
        if conf is not None and conf < LOW_CONFIDENCE:
            await self.event(
                "low_confidence",
                f"Needs review: {b['title']}",
                f"Fact-check confidence {conf} is below {LOW_CONFIDENCE}; it will not auto-upload.",
                {"build": b["id"]},
            )
        else:
            await self.event("short_built", f"Built: {b['title']}", None, {"build": b["id"]})

    async def event(self, kind: str, title: str, body: str | None, ref: dict) -> None:
        await self.db.table("events").insert({"kind": kind, "title": title[:200], "body": body, "ref": ref}).execute()

    async def everything(self) -> None:
        for step in (self.topics, self.videos, self.competitors, self.config, self.builds):
            await step()
        self.primed = True
