"""The agent loop: sign in, mirror the pipeline, heartbeat, and execute app commands one at a time."""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging
import shutil
import subprocess
import time
from datetime import UTC, datetime, timedelta
from importlib.metadata import version

from supabase import AsyncClient, acreate_client
from watchdog.events import (
    FileClosedEvent,
    FileCreatedEvent,
    FileDeletedEvent,
    FileModifiedEvent,
    FileMovedEvent,
    FileSystemEvent,
    FileSystemEventHandler,
)
from watchdog.observers import Observer

from . import mapping, settings
from .commands import Rejected, to_argv
from .mirror import Mirror
from .runner import pipeline_lock, pipeline_locked, run_cli

log = logging.getLogger("shortsops_agent")
HEARTBEAT_S = 60
POLL_S = 60  # fallback when the realtime socket is down
OFFLINE_AFTER = timedelta(minutes=3)  # same threshold the app uses to show "offline"
RESCAN_S = 300  # full resync in case a file event was missed
DEBOUNCE_S = 2
DISK_SCAN_S = 600  # sizing data/out walks ~18 GB, so do it rarely

# Which mirror step a changed path should trigger.
WATCHED = {
    "topics.json": "topics",
    "history.json": "videos",
    "competitors.json": "competitors",
    "config.yaml": "config",
    "meta.json": "builds",
}


class _Changes(FileSystemEventHandler):
    def __init__(self, loop: asyncio.AbstractEventLoop, dirty: set[str], wake: asyncio.Event):
        self.loop, self.dirty, self.wake = loop, dirty, wake

    # Only writes count: the agent's own heartbeat opens history.json every minute, and read-only
    # open/close events would otherwise keep waking the sync loop for nothing.
    WRITES = (FileModifiedEvent, FileCreatedEvent, FileMovedEvent, FileDeletedEvent, FileClosedEvent)

    def on_any_event(self, event: FileSystemEvent) -> None:
        if not isinstance(event, self.WRITES):
            return
        path = str(getattr(event, "dest_path", "") or event.src_path)
        step = WATCHED.get(path.rsplit("/", 1)[-1])
        if step:
            self.loop.call_soon_threadsafe(self._mark, step)

    def _mark(self, step: str) -> None:
        self.dirty.add(step)
        self.wake.set()


class Agent:
    def __init__(self, s: settings.Settings, db: AsyncClient):
        self.s, self.db = s, db
        self.mirror = Mirror(db, s)
        self.dirty: set[str] = set()
        self.files_changed = asyncio.Event()
        self.command_waiting = asyncio.Event()
        self.status_changed = asyncio.Event()  # report right after a command instead of waiting a minute
        self.last_ok: dict[str, float] = {}
        self.running: str | None = None
        self.out_bytes: int | None = None
        self.announced_live: set[str] = set()

    # ------------------------------------------------------------------ status

    async def heartbeat(self) -> None:
        data = self.s.data
        hist_file = data / "history.json"
        history = json.loads(hist_file.read_text(encoding="utf-8")) if hist_file.exists() else []
        used = mapping.quota_units_used(history, datetime.now(UTC))
        cron = subprocess.run(["crontab", "-l"], capture_output=True, text=True).stdout
        last_run = (data / ".last_run").read_text().strip() if (data / ".last_run").exists() else None
        await (
            self.db.table("agent_status")
            .upsert(
                {
                    "id": 1,
                    "last_seen": datetime.now(UTC).isoformat(),
                    "version": version("shortsops-agent"),
                    "paused": (data / ".paused").exists(),
                    "cron_installed": "run_daily.sh" in cron,
                    "last_run_date": last_run,
                    "running_command": self.running,
                    "quota_units_used": used,
                    "uploads_left": mapping.uploads_left(used),
                    "disk_free_bytes": shutil.disk_usage(self.s.pipeline_dir).free,
                    "out_dir_bytes": self.out_bytes,
                }
            )
            .execute()
        )
        await self._announce_live(history)

    async def _announce_online(self) -> None:
        """Only a return from real downtime is news; a quick service restart is not."""
        res = await self.db.table("agent_status").select("last_seen").execute()
        if res.data:
            gap = datetime.now(UTC) - datetime.fromisoformat(res.data[0]["last_seen"])
            if gap < OFFLINE_AFTER:
                return
            body = f"Back after {int(gap.total_seconds() // 60)} min offline"
        else:
            body = None
        await self.mirror.event("agent_online", "Laptop agent online", body, {})

    async def _announce_live(self, history: list[dict]) -> None:
        now = datetime.now(UTC)
        live = {
            h["video_id"]: h
            for h in history
            if h.get("video_id") and h.get("publish_at") and datetime.fromisoformat(h["publish_at"]) <= now
        }
        if not self.announced_live:  # first pass: everything already live counts as announced
            self.announced_live = set(live) or {""}
            return
        for vid in live.keys() - self.announced_live:
            await self.mirror.event(
                "went_live",
                f"Live: {live[vid].get('title', vid)}",
                f"https://youtube.com/shorts/{vid}",
                {"video_id": vid},
            )
            self.announced_live.add(vid)

    async def size_out_dir(self) -> None:
        out = self.s.data / "out"
        self.out_bytes = await asyncio.to_thread(lambda: sum(f.stat().st_size for f in out.rglob("*") if f.is_file()))

    # ------------------------------------------------------------------ commands

    async def drain_commands(self) -> None:
        while True:
            res = await self.db.rpc("claim_command").execute()
            if not res.data:
                return
            await self.execute(res.data[0])

    async def execute(self, cmd: dict) -> None:
        cid, kind = cmd["id"], cmd["type"]
        log.info("command %s %s", kind, cid)
        run_id = None
        try:
            spec, argv = to_argv(kind, cmd.get("payload") or {}, self.s.data)
            wait = spec.min_interval_s - (time.monotonic() - self.last_ok.get(kind, -1e9))
            if wait > 0:
                raise Rejected(f"{kind} ran recently; try again in {int(wait // 60) + 1} min")
            self.running = cid
            if spec.uses_pipeline_lock:
                run = await self.db.table("runs").insert({"kind": kind, "command_id": cid}).execute()
                run_id = run.data[0]["id"]

            async def on_step(step: str) -> None:
                if run_id:
                    await self.db.table("runs").update({"step": step}).eq("id", run_id).execute()

            if spec.uses_pipeline_lock:
                with pipeline_lock(self.s.data):
                    code, output = await run_cli(self.s, argv, spec.timeout_s, on_step)
            else:
                code, output = await run_cli(self.s, argv, spec.timeout_s)
            if code != 0:
                raise Rejected(output.splitlines()[-1] if output else f"exit code {code}")
            self.last_ok[kind] = time.monotonic()
            await self._finish(cid, run_id, "done", result={"output": output[-2000:]})
        except Rejected as e:
            await self._finish(cid, run_id, "failed", error=str(e)[:1000])
            await self.mirror.event("command_failed", f"{kind} failed", str(e)[:500], {"command_id": cid})
        except Exception as e:  # never let one command kill the agent
            log.exception("command %s crashed", cid)
            await self._finish(cid, run_id, "failed", error=f"agent error: {e}"[:1000])
        finally:
            self.running = None
            self.dirty.update(WATCHED.values())
            self.files_changed.set()
            self.status_changed.set()

    async def _finish(
        self, cid: str, run_id: str | None, status: str, result: dict | None = None, error: str | None = None
    ) -> None:
        now = datetime.now(UTC).isoformat()
        await (
            self.db.table("commands")
            .update({"status": status, "finished_at": now, "result": result, "error": error})
            .eq("id", cid)
            .execute()
        )
        if run_id:
            await (
                self.db.table("runs")
                .update({"status": "succeeded" if status == "done" else "failed", "finished_at": now, "error": error})
                .eq("id", run_id)
                .execute()
            )

    # ------------------------------------------------------------------ loops

    async def sync_loop(self) -> None:
        steps = {
            "topics": self.mirror.topics,
            "videos": self.mirror.videos,
            "competitors": self.mirror.competitors,
            "config": self.mirror.config,
            "builds": self.mirror.builds,
        }
        last_rescan = time.monotonic()
        while True:
            wait = max(0.0, RESCAN_S - (time.monotonic() - last_rescan))
            try:
                await asyncio.wait_for(self.files_changed.wait(), wait)
                await asyncio.sleep(DEBOUNCE_S)  # let a burst of writes settle
            except TimeoutError:
                pass
            # The full resync runs on schedule however busy the files are, as a net for missed events.
            if time.monotonic() - last_rescan >= RESCAN_S:
                self.dirty.update(steps)
                last_rescan = time.monotonic()
            self.files_changed.clear()
            # Emptied in place: the file watcher holds a reference to this exact set.
            todo = set(self.dirty)
            self.dirty.clear()
            for name in todo:
                try:
                    await steps[name]()
                except Exception:
                    log.exception("sync of %s failed; retrying on the next change", name)
                    self.dirty.add(name)

    async def command_loop(self) -> None:
        while True:
            try:
                await self.drain_commands()
            except Exception:
                log.exception("claiming commands failed")
            with contextlib.suppress(TimeoutError):
                await asyncio.wait_for(self.command_waiting.wait(), POLL_S)
            self.command_waiting.clear()

    async def heartbeat_loop(self) -> None:
        last_scan = 0.0
        while True:
            if time.monotonic() - last_scan > DISK_SCAN_S:
                await self.size_out_dir()
                last_scan = time.monotonic()
            try:
                await self.heartbeat()
            except Exception:
                log.exception("heartbeat failed")
            with contextlib.suppress(TimeoutError):
                await asyncio.wait_for(self.status_changed.wait(), HEARTBEAT_S)
            self.status_changed.clear()

    async def run(self) -> None:
        await self.mirror.everything()
        if pipeline_locked(self.s.data):
            log.info("a pipeline run is in progress; long commands will wait for it")
        await self._announce_online()

        channel = self.db.channel("agent-commands")
        channel.on_postgres_changes(
            "INSERT", schema="public", table="commands", callback=lambda _payload: self.command_waiting.set()
        )
        await channel.subscribe()

        observer = Observer()
        handler = _Changes(asyncio.get_running_loop(), self.dirty, self.files_changed)
        observer.schedule(handler, str(self.s.pipeline_dir), recursive=False)
        observer.schedule(handler, str(self.s.data), recursive=True)
        observer.start()
        try:
            await asyncio.gather(self.sync_loop(), self.command_loop(), self.heartbeat_loop())
        finally:
            observer.stop()
            observer.join()


async def _main() -> None:
    s = settings.load()
    db = await acreate_client(s.supabase_url, s.supabase_key)
    auth = await db.auth.sign_in_with_password({"email": s.agent_email, "password": s.agent_password})
    role = (auth.user.app_metadata or {}).get("role") if auth.user else None
    if role != "agent":
        raise SystemExit(f"{s.agent_email} must have app_metadata.role = 'agent' (has {role!r})")
    await Agent(s, db).run()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    logging.getLogger("httpx").setLevel(logging.WARNING)
    asyncio.run(_main())
