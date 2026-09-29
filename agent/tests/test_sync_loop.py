import asyncio
from pathlib import Path

from watchdog.events import FileClosedNoWriteEvent, FileModifiedEvent, FileMovedEvent, FileOpenedEvent

from shortsops_agent import app
from shortsops_agent.settings import Settings


def make_agent(tmp_path: Path) -> tuple[app.Agent, list[str]]:
    agent = app.Agent(Settings("u", "k", "e", "p", tmp_path), db=None)
    calls: list[str] = []
    for name in ("topics", "videos", "competitors", "config", "builds"):

        async def step(name=name):
            calls.append(name)

        setattr(agent.mirror, name, step)
    return agent, calls


def test_changes_keep_syncing_after_the_first_round(tmp_path, monkeypatch):
    """Regression: the dirty set was swapped for a new one, so every change after the first was lost."""
    monkeypatch.setattr(app, "DEBOUNCE_S", 0)

    async def scenario():
        agent, calls = make_agent(tmp_path)
        handler = app._Changes(asyncio.get_running_loop(), agent.dirty, agent.files_changed)
        loop_task = asyncio.create_task(agent.sync_loop())
        for round_ in range(3):
            handler.on_any_event(FileMovedEvent(str(tmp_path / "x.tmp"), str(tmp_path / "data" / "topics.json")))
            await asyncio.sleep(0.05)
            assert calls.count("topics") == round_ + 1
        loop_task.cancel()

    asyncio.run(scenario())


def test_reading_a_file_does_not_wake_the_sync(tmp_path):
    async def scenario():
        agent, _ = make_agent(tmp_path)
        handler = app._Changes(asyncio.get_running_loop(), agent.dirty, agent.files_changed)
        history = str(tmp_path / "data" / "history.json")
        handler.on_any_event(FileOpenedEvent(history))
        handler.on_any_event(FileClosedNoWriteEvent(history))
        await asyncio.sleep(0)
        assert not agent.files_changed.is_set() and not agent.dirty
        handler.on_any_event(FileModifiedEvent(history))
        await asyncio.sleep(0)
        assert agent.dirty == {"videos"}

    asyncio.run(scenario())


def test_full_rescan_runs_on_schedule_even_while_files_keep_changing(tmp_path, monkeypatch):
    monkeypatch.setattr(app, "DEBOUNCE_S", 0)
    monkeypatch.setattr(app, "RESCAN_S", 0.2)

    async def scenario():
        agent, calls = make_agent(tmp_path)
        loop_task = asyncio.create_task(agent.sync_loop())
        for _ in range(8):  # an unrelated write every 50 ms never lets the loop sit idle for 200 ms
            agent.files_changed.set()
            await asyncio.sleep(0.05)
        loop_task.cancel()
        assert {"topics", "videos", "competitors", "config", "builds"} <= set(calls)

    asyncio.run(scenario())
