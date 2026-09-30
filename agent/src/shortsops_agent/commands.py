"""Command validation: every accepted command becomes a fixed facts-shorts CLI argv, never a shell string."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, ValidationError

TopicId = Annotated[str, StringConstraints(pattern=r"^[A-Za-z0-9_-]{1,40}$")]
BuildId = Annotated[str, StringConstraints(pattern=r"^[A-Za-z0-9_-]{1,80}$")]
VideoId = Annotated[str, StringConstraints(pattern=r"^[A-Za-z0-9_-]{11}$")]


class _Payload(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Empty(_Payload):
    pass


class AddTopic(_Payload):
    text: Annotated[str, StringConstraints(strip_whitespace=True, min_length=5, max_length=200)]


class TopicRef(_Payload):
    id: TopicId


class Reorder(_Payload):
    ids: list[TopicId] = Field(min_length=1, max_length=50)


class Research(_Payload):
    n: int = Field(default=10, ge=1, le=20)


class Make(_Payload):
    topic_id: TopicId | None = None


class BuildRef(_Payload):
    build: BuildId


class ApproveVideo(_Payload):
    video_id: VideoId
    now: bool = False


class Cleanup(_Payload):
    days: int = Field(default=7, ge=1, le=365)


@dataclass(frozen=True)
class Spec:
    payload: type[_Payload]
    timeout_s: int
    uses_pipeline_lock: bool = False  # long jobs must not overlap the cron run
    min_interval_s: int = 0  # rate limit between successful runs


SPECS: dict[str, Spec] = {
    "add_topic": Spec(AddTopic, 30),
    "reorder_topics": Spec(Reorder, 30),
    "skip_topic": Spec(TopicRef, 30),
    "restore_topic": Spec(TopicRef, 30),
    "reset_stuck": Spec(TopicRef, 30),
    "research": Spec(Research, 15 * 60, uses_pipeline_lock=True, min_interval_s=3600),
    "make": Spec(Make, 40 * 60, uses_pipeline_lock=True),
    "approve_upload": Spec(BuildRef, 30 * 60, uses_pipeline_lock=True),
    "publish_now": Spec(BuildRef, 30 * 60, uses_pipeline_lock=True),
    "rebuild": Spec(BuildRef, 20 * 60, uses_pipeline_lock=True),
    "refresh_stats": Spec(Empty, 120, min_interval_s=1800),
    "pause": Spec(Empty, 30),
    "resume": Spec(Empty, 30),
    "cleanup": Spec(Cleanup, 10 * 60, uses_pipeline_lock=True),
    "approve_video": Spec(ApproveVideo, 120, uses_pipeline_lock=True),
}
# Declared in the database but handled in a later phase; the agent fails them explicitly.
NOT_YET = {"reschedule", "update_config"}


class Rejected(Exception):
    """A command that must not run; the message is shown in the app."""


def to_argv(kind: str, payload: dict, data_dir: Path) -> tuple[Spec, list[str]]:
    if kind in NOT_YET:
        raise Rejected(f"{kind} is not supported by this agent version yet")
    spec = SPECS.get(kind)
    if spec is None:
        raise Rejected(f"unknown command {kind}")
    try:
        p = spec.payload.model_validate(payload or {})
    except ValidationError as e:
        detail = "; ".join(f"{'.'.join(map(str, err['loc'])) or 'payload'}: {err['msg']}" for err in e.errors())
        raise Rejected(f"invalid payload: {detail}") from None

    def build_dir(build: str) -> str:
        d = data_dir / "out" / build
        if not (d / "meta.json").is_file():
            raise Rejected(f"no build named {build}")
        return str(d)

    match kind:
        case "add_topic":
            return spec, ["topic", "add", p.text]
        case "reorder_topics":
            return spec, ["topic", "reorder", *p.ids]
        case "skip_topic" | "restore_topic" | "reset_stuck":
            action = {"skip_topic": "skip", "restore_topic": "restore", "reset_stuck": "reset"}[kind]
            return spec, ["topic", action, p.id]
        case "research":
            return spec, ["research", "-n", str(p.n)]
        case "make":
            return spec, ["make", *(["--topic-id", p.topic_id] if p.topic_id else [])]
        case "approve_upload":
            return spec, ["upload", build_dir(p.build)]
        case "publish_now":
            return spec, ["upload", build_dir(p.build), "--now"]
        case "rebuild":
            return spec, ["rebuild", build_dir(p.build)]
        case "refresh_stats":
            return spec, ["stats"]
        case "pause" | "resume":
            return spec, [kind]
        case "approve_video":
            return spec, ["approve", p.video_id, *(["--now"] if p.now else [])]
        case "cleanup":
            return spec, ["cleanup", "--days", str(p.days)]
    raise Rejected(f"unhandled command {kind}")


STEP_RE = re.compile(r"=== step: (\w+)")


def step_of(line: str) -> str | None:
    m = STEP_RE.search(line)
    return m.group(1) if m else None
