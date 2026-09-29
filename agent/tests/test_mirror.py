import asyncio
import json
import os
from pathlib import Path

from shortsops_agent.mirror import Mirror
from shortsops_agent.settings import Settings


class _Table:
    def __init__(self, db, name):
        self.db, self.name = db, name

    def select(self, *_):
        return self

    def upsert(self, rows, **_):
        self.db.upserts.setdefault(self.name, []).extend(rows)
        return self

    async def execute(self):
        return type("Res", (), {"data": []})()


class _Db:
    def __init__(self):
        self.upserts: dict[str, list[dict]] = {}

    def table(self, name):
        return _Table(self, name)


def test_build_size_is_recounted_after_cleanup_deletes_files(tmp_path: Path):
    build = tmp_path / "data" / "out" / "20260920_1000_abc"
    (build / "clips").mkdir(parents=True)
    (build / "meta.json").write_text(json.dumps({"title": "T"}))
    (build / "final.mp4").write_bytes(b"x" * 5000)
    (build / "clips" / "a.mp4").write_bytes(b"x" * 3000)
    db = _Db()
    mirror = Mirror(db, Settings("u", "k", "e", "p", tmp_path))

    asyncio.run(mirror.builds())
    assert db.upserts["builds"][-1]["size_bytes"] > 8000

    (build / "final.mp4").unlink()  # what `pipeline cleanup` does, leaving meta.json untouched
    (build / "clips" / "a.mp4").unlink()
    (build / "clips").rmdir()
    # Timestamps tick coarsely; in real use cleanup runs hours after the last scan, so move the folder's clock on.
    later = build.stat().st_mtime + 60
    os.utime(build, (later, later))
    asyncio.run(mirror.builds())
    assert db.upserts["builds"][-1]["size_bytes"] < 1000
