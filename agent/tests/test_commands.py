from pathlib import Path

import pytest

from shortsops_agent.commands import Rejected, step_of, to_argv


@pytest.fixture
def data(tmp_path: Path) -> Path:
    (tmp_path / "out" / "20260928_1035_abc").mkdir(parents=True)
    (tmp_path / "out" / "20260928_1035_abc" / "meta.json").write_text("{}")
    return tmp_path


def test_add_topic_passes_text_as_one_argument(data):
    _, argv = to_argv("add_topic", {"text": "  Why cats purr; rm -rf /  "}, data)
    assert argv == ["topic", "add", "Why cats purr; rm -rf /"]


@pytest.mark.parametrize(
    "kind,payload",
    [
        ("add_topic", {"text": "hi"}),
        ("add_topic", {"text": "x" * 201}),
        ("skip_topic", {"id": "../etc"}),
        ("reorder_topics", {"ids": []}),
        ("research", {"n": 500}),
        ("make", {"topic_id": "abc", "extra": 1}),
        ("approve_upload", {"build": "../../secrets"}),
        ("approve_upload", {"build": "missing_build"}),
        ("cleanup", {"days": 0}),
    ],
)
def test_bad_payloads_are_rejected(data, kind, payload):
    with pytest.raises(Rejected):
        to_argv(kind, payload, data)


def test_unknown_and_unimplemented_commands_are_rejected(data):
    with pytest.raises(Rejected, match="unknown"):
        to_argv("shell", {}, data)
    with pytest.raises(Rejected, match="not supported"):
        to_argv("update_config", {"patch": {}}, data)


def test_upload_commands_resolve_to_the_build_directory(data):
    spec, argv = to_argv("publish_now", {"build": "20260928_1035_abc"}, data)
    assert argv == ["upload", str(data / "out" / "20260928_1035_abc"), "--now"]
    assert spec.uses_pipeline_lock


def test_rate_limited_commands_declare_an_interval(data):
    spec, argv = to_argv("research", {}, data)
    assert argv == ["research", "-n", "10"] and spec.min_interval_s == 3600


def test_step_markers():
    assert step_of("2026-09-28 10:00:01 INFO facts_shorts: === step: footage") == "footage"
    assert step_of("=== making short in x") is None


def test_rejection_names_the_bad_field(data):
    with pytest.raises(Rejected, match=r"^invalid payload: text: String should have at least 5 characters$"):
        to_argv("add_topic", {"text": "no"}, data)
