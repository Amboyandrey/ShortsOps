"""Runs facts-shorts CLI commands as subprocesses, sharing the cron run's lock and reporting step changes."""

from __future__ import annotations

import asyncio
import contextlib
import fcntl
import os
import signal
from collections import deque
from collections.abc import Awaitable, Callable
from pathlib import Path

from .commands import Rejected, step_of
from .settings import Settings

TAIL_LINES = 40


@contextlib.contextmanager
def pipeline_lock(data_dir: Path):
    """The same flock run_daily.sh takes, so an app command and the cron run never overlap."""
    with open(data_dir / ".daily.lock", "a") as fh:
        try:
            fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise Rejected("the pipeline is busy (daily run in progress); try again later") from None
        try:
            yield
        finally:
            fcntl.flock(fh, fcntl.LOCK_UN)


def pipeline_locked(data_dir: Path) -> bool:
    try:
        with pipeline_lock(data_dir):
            return False
    except Rejected:
        return True


async def run_cli(
    s: Settings, argv: list[str], timeout_s: int, on_step: Callable[[str], Awaitable[None]] | None = None
) -> tuple[int, str]:
    """Returns (exit code, last lines of output). Kills the whole process group on timeout."""
    # cron's PATH plus the claude CLI and the pipeline's bundled ffmpeg, as run_daily.sh sets it
    path = f"{os.path.expanduser('~/.local/bin')}:{s.pipeline_dir / 'bin'}:/usr/local/bin:/usr/bin:/bin"
    env = {**os.environ, "PATH": path}
    proc = await asyncio.create_subprocess_exec(
        str(s.python),
        "-m",
        "facts_shorts.pipeline",
        *argv,
        cwd=s.pipeline_dir,
        env=env,
        start_new_session=True,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
    )
    tail: deque[str] = deque(maxlen=TAIL_LINES)

    async def pump() -> None:
        assert proc.stdout
        async for raw in proc.stdout:
            line = raw.decode(errors="replace").rstrip()
            tail.append(line)
            if on_step and (step := step_of(line)):
                await on_step(step)

    try:
        await asyncio.wait_for(asyncio.gather(pump(), proc.wait()), timeout_s)
    except TimeoutError:
        with contextlib.suppress(ProcessLookupError):
            os.killpg(proc.pid, signal.SIGKILL)
        await proc.wait()
        tail.append(f"killed after {timeout_s}s timeout")
        return -1, "\n".join(tail)
    return proc.returncode or 0, "\n".join(tail)
