import pytest
from pydantic import ValidationError

from packages.contracts.models import Task
from packages.contracts.workload import EffortRange, WorkloadAssumption, WorkloadInput


def make_task(**overrides):
    payload = {
        "task_id": "A",
        "name": "Build API",
        "mandatory": True,
        "dependencies": (),
        "effort_min_minutes": 60,
        "effort_likely_minutes": 90,
        "effort_max_minutes": 120,
        "assumptions": (),
    }
    payload.update(overrides)
    return Task(**payload)


def test_valid_task_uses_integer_minutes() -> None:
    task = make_task()
    assert task.effort_likely_minutes == 90


def test_invalid_effort_ordering_is_rejected() -> None:
    with pytest.raises(ValidationError):
        make_task(effort_min_minutes=240, effort_likely_minutes=120)


def test_mandatory_is_strict_boolean() -> None:
    for invalid in ("true", 1):
        with pytest.raises(ValidationError):
            make_task(mandatory=invalid)


def test_effort_minutes_are_strict_integers() -> None:
    for invalid in ("90", 90.0, True):
        with pytest.raises(ValidationError):
            make_task(effort_likely_minutes=invalid)


def test_hours_fields_are_not_accepted() -> None:
    payload = make_task().model_dump()
    payload.pop("effort_min_minutes")
    payload.pop("effort_likely_minutes")
    payload.pop("effort_max_minutes")
    payload.update(
        effort_min_hours=1.0,
        effort_likely_hours=1.5,
        effort_max_hours=2.0,
    )
    with pytest.raises(ValidationError):
        Task(**payload)


def test_self_dependency_is_rejected() -> None:
    with pytest.raises(ValidationError):
        make_task(dependencies=("A",))


def test_duplicate_dependency_is_rejected() -> None:
    with pytest.raises(ValidationError):
        make_task(dependencies=("B", "B"))


def test_zero_effort_is_explicitly_valid() -> None:
    task = make_task(
        effort_min_minutes=0,
        effort_likely_minutes=0,
        effort_max_minutes=0,
    )
    assert task.effort_max_minutes == 0


def test_workload_contracts_forbid_extra_fields() -> None:
    with pytest.raises(ValidationError):
        EffortRange(min_minutes=1, likely_minutes=2, max_minutes=3, fake=4)


def test_assumption_supports_global_or_task_specific_trace() -> None:
    global_item = WorkloadAssumption(description="team size assumed to be two")
    task_item = WorkloadAssumption(task_id="A", description="API has no OAuth")
    workload = WorkloadInput(tasks=(make_task(),), assumptions=(global_item, task_item))
    assert workload.assumptions == (global_item, task_item)


def test_public_workload_api_only_exposes_analysis_entrypoint() -> None:
    import engine.workload as workload_api

    assert workload_api.__all__ == ["analyze_workload"]
    assert not hasattr(workload_api, "DependencyGraph")
    assert not hasattr(workload_api, "build_dependency_graph")
    assert not hasattr(workload_api, "required_task_closure")


def test_schema_migration_is_versioned_by_scr_002() -> None:
    from pathlib import Path

    schema = Path(
        "docs/05_PREPRODUCTION/01_CONTRACTS_ACTIVE/FEATURE_SCHEMA_FINAL.yaml"
    ).read_text(encoding="utf-8")
    scr = Path(
        "docs/05_PREPRODUCTION/01_CONTRACTS_ACTIVE/SCHEMA_CHANGE_REQUEST_002.md"
    ).read_text(encoding="utf-8")

    assert 'schema_version: "2.0.0"' in schema
    assert "effort_min_minutes" in schema
    assert "effort_min_hours" not in schema
    assert "SCR-002" in scr
    assert "breaking wire-contract change" in scr


def test_english_and_indonesian_schema_mirrors_share_task_version() -> None:
    from pathlib import Path

    english = Path(
        "docs/05_PREPRODUCTION/01_CONTRACTS_ACTIVE/FEATURE_SCHEMA_FINAL.yaml"
    ).read_text(encoding="utf-8")
    indonesian = Path(
        "docs/indonesian language/05_PREPRODUCTION/01_CONTRACTS_ACTIVE/"
        "FEATURE_SCHEMA_FINAL.yaml"
    ).read_text(encoding="utf-8")

    for expected in (
        'schema_version: "2.0.0"',
        "effort_min_minutes",
        "effort_likely_minutes",
        "effort_max_minutes",
        "assumptions",
        "effort_unit: integer_minutes",
    ):
        assert expected in english
        assert expected in indonesian
