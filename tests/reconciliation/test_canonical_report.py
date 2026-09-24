from __future__ import annotations

from copy import deepcopy

import pytest

from engine.reconciliation import (
    CANONICAL_V1,
    CanonicalAssemblyPolicy,
    FieldReconciliationResult,
    ReconciliationInputError,
    assemble_canonical_report,
)
from packages.contracts import (
    CandidateField,
    CanonicalField,
    CanonicalFieldState,
    ExtractionPath,
)
from packages.contracts.source import CORE_CANONICAL_FIELDS


def make_missing_result(field_name: str) -> FieldReconciliationResult:
    return FieldReconciliationResult(
        canonical_field=CanonicalField(
            field_name=field_name,
            state=CanonicalFieldState.MISSING,
        ),
        resolution_basis=("test-missing",),
        supporting_source_ids=(),
    )


def make_usable_result(
    field_name: str,
    *,
    source_ids=("src-a",),
    value="usable",
    normalized="usable",
    state=CanonicalFieldState.SINGLE_SOURCE,
    evidence_id: str | None = None,
) -> FieldReconciliationResult:
    evidence_id = evidence_id or f"ev-{field_name}-{source_ids[0]}"
    candidate = CandidateField(
        field_name=field_name,
        raw_value=deepcopy(value),
        normalized_value=deepcopy(normalized),
        evidence_ids=[evidence_id],
        extraction_path=ExtractionPath.NATIVE,
        confidence=0.9,
        scope={"category": "all"},
    )
    return FieldReconciliationResult(
        canonical_field=CanonicalField(
            field_name=field_name,
            state=state,
            value=deepcopy(value),
            normalized_value=deepcopy(normalized),
            candidates=[candidate],
            evidence_ids=[evidence_id],
        ),
        resolution_basis=("test-usable",),
        supporting_source_ids=tuple(source_ids),
    )


def make_unverified_result(field_name: str) -> FieldReconciliationResult:
    evidence_id = f"ev-unverified-{field_name}"
    candidate = CandidateField(
        field_name=field_name,
        raw_value="candidate",
        normalized_value="candidate",
        evidence_ids=[evidence_id],
        extraction_path=ExtractionPath.NATIVE,
        confidence=0.5,
        scope={"category": "all"},
    )
    return FieldReconciliationResult(
        canonical_field=CanonicalField(
            field_name=field_name,
            state=CanonicalFieldState.UNVERIFIED,
            candidates=[candidate],
            evidence_ids=[evidence_id],
        ),
        resolution_basis=("test-unverified",),
        supporting_source_ids=(),
    )


def make_conflict_result(field_name: str) -> FieldReconciliationResult:
    candidates = []
    evidence_ids = []
    for index, normalized in enumerate(("value-a", "value-b"), start=1):
        evidence_id = f"ev-conflict-{field_name}-{index}"
        evidence_ids.append(evidence_id)
        candidates.append(
            CandidateField(
                field_name=field_name,
                raw_value=normalized,
                normalized_value=normalized,
                evidence_ids=[evidence_id],
                extraction_path=ExtractionPath.NATIVE,
                confidence=0.5,
                scope={"category": "all"},
            )
        )
    return FieldReconciliationResult(
        canonical_field=CanonicalField(
            field_name=field_name,
            state=CanonicalFieldState.CONFLICT,
            candidates=candidates,
            evidence_ids=evidence_ids,
        ),
        resolution_basis=("test-conflict",),
        supporting_source_ids=(),
    )


def complete_results(
    *overrides: FieldReconciliationResult,
) -> list[FieldReconciliationResult]:
    by_field = {
        field_name: make_missing_result(field_name)
        for field_name in CANONICAL_V1.core_fields
    }
    for result in overrides:
        by_field[result.canonical_field.field_name] = result
    return [by_field[field_name] for field_name in CANONICAL_V1.core_fields]


def assemble(
    *,
    overrides=(),
    snapshot_source_ids=("src-a",),
    previous_report=None,
):
    return assemble_canonical_report(
        competition_id="shipaton-2026",
        field_results=complete_results(*overrides),
        snapshot_source_ids=snapshot_source_ids,
        previous_report=previous_report,
    )


def test_first_report_is_version_one_and_changed() -> None:
    result = assemble()
    assert result.report.report_version == 1
    assert result.report_changed is True
    assert result.assembly_policy_version == "canonical-v1"
    assert len(result.material_fingerprint) == 64


def test_all_core_fields_require_explicit_results_and_keep_policy_order() -> None:
    result = assemble()
    assert tuple(result.report.canonical_fields) == CANONICAL_V1.core_fields
    assert set(result.report.canonical_fields) == CORE_CANONICAL_FIELDS
    assert all(
        field.state is CanonicalFieldState.MISSING
        for field in result.report.canonical_fields.values()
    )


def test_incomplete_reconciliation_batch_is_rejected() -> None:
    incomplete = complete_results()[:-1]
    with pytest.raises(
        ReconciliationInputError,
        match="incomplete reconciliation batch",
    ):
        assemble_canonical_report(
            competition_id="shipaton-2026",
            field_results=incomplete,
            snapshot_source_ids=["src-a"],
        )


def test_explicit_missing_from_4a_is_valid() -> None:
    result = assemble()
    assert result.report.canonical_fields["competition_name"].state is (
        CanonicalFieldState.MISSING
    )


def test_missing_critical_fields_are_unresolved() -> None:
    result = assemble()
    assert result.report.unresolved_critical_fields == [
        "submission_deadline",
        "eligibility",
    ]


def test_usable_critical_fields_are_resolved() -> None:
    result = assemble(
        overrides=(
            make_usable_result("submission_deadline"),
            make_usable_result("eligibility"),
        )
    )
    assert result.report.unresolved_critical_fields == []


def test_conflict_and_unverified_critical_fields_are_unresolved() -> None:
    result = assemble(
        overrides=(
            make_conflict_result("submission_deadline"),
            make_unverified_result("eligibility"),
        )
    )
    assert result.report.unresolved_critical_fields == [
        "submission_deadline",
        "eligibility",
    ]


def test_noncritical_missing_field_is_not_unresolved() -> None:
    result = assemble(
        overrides=(
            make_usable_result("submission_deadline"),
            make_usable_result("eligibility"),
        )
    )
    assert "deliverables" not in result.report.unresolved_critical_fields


def test_source_ids_are_unique_sorted_snapshot_ids() -> None:
    result = assemble(snapshot_source_ids=("src-b", "src-a", "src-b"))
    assert result.report.source_ids == ["src-a", "src-b"]


def test_zero_source_snapshot_is_rejected() -> None:
    with pytest.raises(ReconciliationInputError):
        assemble_canonical_report(
            competition_id="shipaton-2026",
            field_results=complete_results(),
            snapshot_source_ids=[],
        )


def test_snapshot_source_ids_plain_string_is_rejected() -> None:
    with pytest.raises(
        ReconciliationInputError,
        match="not a string",
    ):
        assemble_canonical_report(
            competition_id="shipaton-2026",
            field_results=complete_results(),
            snapshot_source_ids="src-a",
        )


def test_duplicate_field_result_is_rejected() -> None:
    fields = complete_results()
    fields.append(make_missing_result("submission_deadline"))
    with pytest.raises(ReconciliationInputError, match="duplicate"):
        assemble_canonical_report(
            competition_id="shipaton-2026",
            field_results=fields,
            snapshot_source_ids=["src-a"],
        )


def test_unknown_field_result_is_rejected() -> None:
    fields = complete_results()
    fields.append(make_missing_result("sponsor_contact"))
    with pytest.raises(ReconciliationInputError, match="unknown canonical field"):
        assemble_canonical_report(
            competition_id="shipaton-2026",
            field_results=fields,
            snapshot_source_ids=["src-a"],
        )


def test_trace_source_must_belong_to_snapshot() -> None:
    field = make_usable_result("submission_deadline", source_ids=("src-z",))
    with pytest.raises(ReconciliationInputError, match="outside snapshot"):
        assemble(
            overrides=(field,),
            snapshot_source_ids=("src-a",),
        )


def test_superseded_trace_source_must_belong_to_snapshot() -> None:
    field = make_usable_result("submission_deadline")
    invalid = FieldReconciliationResult(
        canonical_field=field.canonical_field,
        resolution_basis=field.resolution_basis,
        supporting_source_ids=("src-a",),
        superseded_source_ids=("src-z",),
    )
    with pytest.raises(ReconciliationInputError, match="outside snapshot"):
        assemble(overrides=(invalid,))


def test_identical_rerun_keeps_version_and_fingerprint() -> None:
    field = make_usable_result("submission_deadline")
    first = assemble(overrides=(field,))
    second = assemble(
        overrides=(field,),
        previous_report=first.report,
    )
    assert second.report.report_version == 1
    assert second.report_changed is False
    assert second.material_fingerprint == first.material_fingerprint


def test_canonical_value_change_bumps_version() -> None:
    first = assemble(
        overrides=(
            make_usable_result(
                "submission_deadline",
                value="Sep 30",
                normalized="2026-09-30T16:59:00Z",
            ),
        )
    )
    second = assemble(
        overrides=(
            make_usable_result(
                "submission_deadline",
                value="Oct 2",
                normalized="2026-10-02T16:59:00Z",
            ),
        ),
        previous_report=first.report,
    )
    assert second.report.report_version == 2
    assert second.report_changed is True
    assert second.material_fingerprint != first.material_fingerprint


def test_provenance_change_bumps_version_with_same_value() -> None:
    first = assemble(
        overrides=(
            make_usable_result(
                "submission_deadline",
                value="Sep 30",
                normalized="2026-09-30T16:59:00Z",
                evidence_id="ev-old",
            ),
        )
    )
    second = assemble(
        overrides=(
            make_usable_result(
                "submission_deadline",
                value="Sep 30",
                normalized="2026-09-30T16:59:00Z",
                evidence_id="ev-new",
            ),
        ),
        previous_report=first.report,
    )
    assert second.report.report_version == 2
    assert second.report_changed is True


def test_state_change_bumps_version_even_when_value_is_same() -> None:
    first = assemble(
        overrides=(make_usable_result("submission_deadline"),),
        snapshot_source_ids=("src-a", "src-b"),
    )
    second = assemble(
        overrides=(
            make_usable_result(
                "submission_deadline",
                source_ids=("src-a", "src-b"),
                state=CanonicalFieldState.VERIFIED,
            ),
        ),
        snapshot_source_ids=("src-a", "src-b"),
        previous_report=first.report,
    )
    assert second.report.report_version == 2
    assert second.report_changed is True


def test_source_ids_change_bumps_version() -> None:
    first = assemble(snapshot_source_ids=("src-a",))
    second = assemble(
        snapshot_source_ids=("src-a", "src-b"),
        previous_report=first.report,
    )
    assert second.report.report_version == 2
    assert second.report_changed is True


def test_previous_competition_mismatch_is_rejected() -> None:
    first = assemble_canonical_report(
        competition_id="competition-a",
        field_results=complete_results(),
        snapshot_source_ids=["src-a"],
    )
    with pytest.raises(ReconciliationInputError, match="competition_id"):
        assemble_canonical_report(
            competition_id="competition-b",
            field_results=complete_results(),
            snapshot_source_ids=["src-a"],
            previous_report=first.report,
        )


def test_previous_report_is_deep_independent_from_new_report() -> None:
    field = make_usable_result(
        "deliverables",
        value=["demo_video", "repository"],
        normalized=["demo_video", "repository"],
    )
    first = assemble(overrides=(field,))
    before = first.report.model_dump(mode="python")

    second = assemble(
        overrides=(field,),
        previous_report=first.report,
    )
    second.report.canonical_fields["deliverables"].normalized_value.append("slides")
    second.report.canonical_fields["deliverables"].candidates[0].raw_value.append(
        "slides"
    )

    assert first.report.model_dump(mode="python") == before


def test_input_field_results_are_not_mutated_or_aliased() -> None:
    input_result = make_usable_result(
        "deliverables",
        value=["demo_video"],
        normalized=["demo_video"],
    )
    before = deepcopy(input_result.canonical_field.model_dump(mode="python"))

    assembled = assemble(overrides=(input_result,))
    assembled.report.canonical_fields["deliverables"].normalized_value.append(
        "repository"
    )

    assert input_result.canonical_field.model_dump(mode="python") == before


def test_mutated_invalid_field_result_is_normalized_to_reconciliation_error() -> None:
    invalid = make_usable_result("submission_deadline")
    invalid.canonical_field.value = None

    with pytest.raises(
        ReconciliationInputError,
        match="canonical field contract",
    ):
        assemble(overrides=(invalid,))


def test_mutated_invalid_previous_report_is_normalized_to_reconciliation_error() -> None:
    first = assemble(
        overrides=(make_usable_result("submission_deadline"),)
    )
    first.report.canonical_fields["submission_deadline"].value = None

    with pytest.raises(
        ReconciliationInputError,
        match="canonical report input",
    ):
        assemble(previous_report=first.report)


def test_field_and_source_input_order_do_not_change_material_output() -> None:
    fields = complete_results(
        make_usable_result("submission_deadline"),
        make_usable_result("eligibility"),
    )
    forward = assemble_canonical_report(
        competition_id="shipaton-2026",
        field_results=fields,
        snapshot_source_ids=["src-b", "src-a"],
    )
    reverse = assemble_canonical_report(
        competition_id="shipaton-2026",
        field_results=list(reversed(fields)),
        snapshot_source_ids=["src-a", "src-b"],
    )
    assert forward.material_fingerprint == reverse.material_fingerprint
    assert forward.report.model_dump(mode="python") == reverse.report.model_dump(
        mode="python"
    )


def test_existing_critical_conflict_is_preserved_not_reinterpreted() -> None:
    result = assemble(
        overrides=(make_conflict_result("submission_deadline"),)
    )
    assert result.report.canonical_fields["submission_deadline"].state is (
        CanonicalFieldState.CONFLICT
    )
    assert result.report.unresolved_critical_fields == [
        "submission_deadline",
        "eligibility",
    ]


def test_policy_rejects_altered_canonical_v1_critical_fields() -> None:
    with pytest.raises(ValueError, match="critical_fields must exactly match"):
        CanonicalAssemblyPolicy(
            policy_version="canonical-v1",
            core_fields=CANONICAL_V1.core_fields,
            critical_fields=("organizer",),
        )


def test_policy_rejects_altered_canonical_v1_core_order() -> None:
    reordered = (
        CANONICAL_V1.core_fields[1],
        CANONICAL_V1.core_fields[0],
        *CANONICAL_V1.core_fields[2:],
    )
    with pytest.raises(ValueError, match="core_fields must exactly match"):
        CanonicalAssemblyPolicy(
            policy_version="canonical-v1",
            core_fields=reordered,
            critical_fields=CANONICAL_V1.critical_fields,
        )


def test_policy_rejects_unregistered_version() -> None:
    with pytest.raises(
        ValueError,
        match="unsupported canonical assembly policy version",
    ):
        CanonicalAssemblyPolicy(
            policy_version="canonical-v2",
            core_fields=CANONICAL_V1.core_fields,
            critical_fields=CANONICAL_V1.critical_fields,
        )


def test_policy_freezes_mutable_constructor_inputs() -> None:
    core = list(CANONICAL_V1.core_fields)
    critical = list(CANONICAL_V1.critical_fields)
    policy = CanonicalAssemblyPolicy(
        policy_version="canonical-v1",
        core_fields=core,
        critical_fields=critical,
    )

    core.reverse()
    critical.clear()
    critical.append("organizer")

    assert policy.core_fields == CANONICAL_V1.core_fields
    assert policy.critical_fields == CANONICAL_V1.critical_fields
    assert isinstance(policy.core_fields, tuple)
    assert isinstance(policy.critical_fields, tuple)


def test_policy_rejects_core_field_contract_drift() -> None:
    with pytest.raises(ValueError, match="core_fields must match canonical contract"):
        CanonicalAssemblyPolicy(
            policy_version="canonical-v1",
            core_fields=("submission_deadline",),
            critical_fields=("submission_deadline",),
        )


def test_policy_rejects_duplicate_core_fields() -> None:
    duplicate_core = CANONICAL_V1.core_fields + (CANONICAL_V1.core_fields[0],)
    with pytest.raises(ValueError, match="core_fields must be unique"):
        CanonicalAssemblyPolicy(
            policy_version="canonical-v1",
            core_fields=duplicate_core,
            critical_fields=CANONICAL_V1.critical_fields,
        )


def test_policy_rejects_duplicate_critical_fields() -> None:
    with pytest.raises(ValueError, match="critical_fields must be unique"):
        CanonicalAssemblyPolicy(
            policy_version="canonical-v1",
            core_fields=CANONICAL_V1.core_fields,
            critical_fields=("eligibility", "eligibility"),
        )
