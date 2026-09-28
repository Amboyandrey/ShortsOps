"""Agent configuration, read once from the environment (agent/.env via systemd EnvironmentFile)."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    supabase_url: str
    supabase_key: str  # publishable/anon key; the agent's rights come from its user's role, not this key
    agent_email: str
    agent_password: str
    pipeline_dir: Path

    @property
    def data(self) -> Path:
        return self.pipeline_dir / "data"

    @property
    def python(self) -> Path:
        return self.pipeline_dir / ".venv" / "bin" / "python"

    @property
    def ffmpeg(self) -> str:
        local = self.pipeline_dir / "bin" / "ffmpeg"
        return str(local) if local.exists() else "ffmpeg"


def load() -> Settings:
    def need(name: str) -> str:
        val = os.environ.get(name)
        if not val:
            raise SystemExit(f"missing environment variable {name} (see agent/.env.example)")
        return val

    return Settings(
        supabase_url=need("SUPABASE_URL"),
        supabase_key=need("SUPABASE_PUBLISHABLE_KEY"),
        agent_email=need("AGENT_EMAIL"),
        agent_password=need("AGENT_PASSWORD"),
        pipeline_dir=Path(need("PIPELINE_DIR")).expanduser().resolve(),
    )
