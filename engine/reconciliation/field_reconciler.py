"""Pure field-level reconciliation from candidate reports to CanonicalField."""

from __future__ import annotations

import json
from collections.abc import Iterable
from hashlib import sha256

from packages.contracts import (
    CandidateExtractionReport,
    CanonicalField,
    CanonicalFieldState,
    EvidenceSpan,
    SourceRecord,
)

from engine.reconciliation.models import (
    CandidateObservation,
    FieldReconciliationResult,
    ReconciliationInputError,
    ScopeDescriptor,
    ScopeRelation,
)
from engine.reconciliation.policy import (
    UnusableNormalizedValue,
    comparison_value,
    parse_scope,
    scope_relation,
    source_supersedes,
)


def _stable_json(value: object) -> str:
    return json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        default=str,
    )



def _report_fingerprint(report: CandidateExtractionReport) -> str:
    payload = report.model_dump(mode="json")
    encoded = json.dumps(
        payload,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        default=str,
    ).encode("utf-8")
    return sha256(encoded).hexdigest()[:16]

def _observation_sort_key(observation: CandidateObservation) -> tuple[object, ...]:
    return (
        observation.source_id,
        observation.field.extraction_path.value,
        observation.field.field_name,
        tuple(sorted(observation.field.evidence_ids)),
        _stable_json(observation.field.normalized_value),
        _stable_json(observation.field.raw_value),
    )


def _candidate_sort_key(observation: CandidateObservation) -> tuple[object, ...]:
    return _observation_sort_key(observation)


def _evidence_ids(observations: Iterable[CandidateObservation]) -> list[str]:
    return sorted(
        {
            evidence.evidence_id
            for observation in observations
            for evidence in observation.evidence
        }
    )


def _candidates(observations: Iterable[CandidateObservation]):
    return [
        observation.field
        for observation in sorted(observations, key=_candidate_sort_key)
    ]


def collect_candidate_observations(
    reports: Iterable[CandidateExtractionReport],
    sources: Iterable[SourceRecord],
) -> tuple[CandidateObservation, ...]:
    """Validate report/source/evidence linkage and flatten reports deterministically."""

    source_by_id: dict[str, SourceRecord] = {}
    for source in sources:
        if source.source_id in source_by_id:
            raise ReconciliationInputError(
                f"duplicate SourceRecord source_id: {source.source_id!r}"
            )
        source_by_id[source.source_id] = source

    seen_report_keys: set[tuple[str, object, str]] = set()
    seen_evidence_ids: set[str] = set()
    observations: list[CandidateObservation] = []

    for report in reports:
        source = source_by_id.get(report.source_id)
        if source is None:
            raise ReconciliationInputError(
                f"candidate report references unknown source_id: {report.source_id!r}"
            )

        report_key = (
            report.source_id,
            report.extraction_path,
            _report_fingerprint(report),
        )
        if report_key in seen_report_keys:
            raise ReconciliationInputError(
                "duplicate candidate report snapshot for source/path: "
                f"{report.source_id!r}, {report.extraction_path.value!r}"
            )
        seen_report_keys.add(report_key)

        evidence_by_id: dict[str, EvidenceSpan] = {}
        for evidence in report.evidence:
            if evidence.evidence_id in seen_evidence_ids:
                raise ReconciliationInputError(
                    f"duplicate evidence_id across reconciliation input: {evidence.evidence_id!r}"
                )
            seen_evidence_ids.add(evidence.evidence_id)

            if evidence.source_id != report.source_id:
                raise ReconciliationInputError(
                    "evidence source_id must match candidate report source_id"
                )
            if evidence.extraction_path is not report.extraction_path:
                raise ReconciliationInputError(
                    "evidence extraction_path must match candidate report extraction_path"
                )
            evidence_by_id[evidence.evidence_id] = evidence

        for field in report.fields:
            if field.extraction_path is not report.extraction_path:
                raise ReconciliationInputError(
                    "candidate extraction_path must match candidate report extraction_path"
                )

            linked_evidence: list[EvidenceSpan] = []
            for evidence_id in field.evidence_ids:
                evidence = evidence_by_id.get(evidence_id)
                if evidence is None:
                    raise ReconciliationInputError(
                        f"candidate evidence_id does not exist in report: {evidence_id!r}"
                    )
                if evidence.field_name != field.field_name:
                    raise ReconciliationInputError(
                        "evidence field_name must match candidate field_name"
                    )
                linked_evidence.append(evidence)

            observations.append(
                CandidateObservation(
                    source_id=report.source_id,
                    report_key=report_key,
                    source_record=source,
                    field=field,
                    evidence=tuple(sorted(linked_evidence, key=lambda item: item.evidence_id)),
                )
            )

    return tuple(sorted(observations, key=_observation_sort_key))


def _unverified(
    field_name: str,
    observations: tuple[CandidateObservation, ...],
    *,
    basis: tuple[str, ...],
) -> FieldReconciliationResult:
    return FieldReconciliationResult(
        canonical_field=CanonicalField(
            field_name=field_name,
            state=CanonicalFieldState.UNVERIFIED,
            candidates=_candidates(observations),
            evidence_ids=_evidence_ids(observations),
        ),
        resolution_basis=basis,
        supporting_source_ids=(),
    )


def _conflict(
    field_name: str,
    observations: tuple[CandidateObservation, ...],
    *,
    superseded_source_ids: tuple[str, ...] = (),
) -> FieldReconciliationResult:
    return FieldReconciliationResult(
        canonical_field=CanonicalField(
            field_name=field_name,
            state=CanonicalFieldState.CONFLICT,
            candidates=_candidates(observations),
            evidence_ids=_evidence_ids(observations),
        ),
        resolution_basis=("unresolved-applicable-disagreement",),
        supporting_source_ids=(),
        superseded_source_ids=superseded_source_ids,
    )


def _simple_usable_result(
    field_name: str,
    *,
    active: tuple[CandidateObservation, ...],
    all_observations: tuple[CandidateObservation, ...],
    superseded_source_ids: tuple[str, ...],
) -> FieldReconciliationResult:
    representative = min(active, key=_observation_sort_key)
    compared = comparison_value(field_name, representative.field.normalized_value)
    supporting_source_ids = tuple(sorted({item.source_id for item in active}))
    state = (
        CanonicalFieldState.VERIFIED
        if len(supporting_source_ids) >= 2
        else CanonicalFieldState.SINGLE_SOURCE
    )
    basis = (
        f"agreement:{len(supporting_source_ids)}-independent-source",
    )
    if superseded_source_ids:
        basis += ("deterministic-supersession",)

    return FieldReconciliationResult(
        canonical_field=CanonicalField(
            field_name=field_name,
            state=state,
            value=representative.field.raw_value,
            normalized_value=compared.canonical,
            candidates=_candidates(all_observations),
            evidence_ids=_evidence_ids(all_observations),
        ),
        resolution_basis=basis,
        supporting_source_ids=supporting_source_ids,
        superseded_source_ids=superseded_source_ids,
    )


def _scoped_result(
    field_name: str,
    *,
    active: tuple[CandidateObservation, ...],
    all_observations: tuple[CandidateObservation, ...],
    superseded_source_ids: tuple[str, ...],
) -> FieldReconciliationResult:
    groups: dict[
        tuple[tuple[str | None, str | None, str | None], str],
        list[CandidateObservation],
    ] = {}
    scopes: dict[
        tuple[tuple[str | None, str | None, str | None], str], ScopeDescriptor
    ] = {}

    for observation in active:
        scope = parse_scope(observation.field.scope)
        compared = comparison_value(field_name, observation.field.normalized_value)
        key = (scope.key, compared.key)
        groups.setdefault(key, []).append(observation)
        scopes[key] = scope

    raw_variants: list[dict[str, object]] = []
    normalized_variants: list[dict[str, object]] = []
    support_counts: list[int] = []
    supporting_sources: set[str] = set()

    for key in sorted(groups, key=lambda item: (_stable_json(item[0]), item[1])):
        group = tuple(sorted(groups[key], key=_observation_sort_key))
        representative = group[0]
        compared = comparison_value(field_name, representative.field.normalized_value)
        scope_mapping = scopes[key].as_mapping()
        group_sources = sorted({item.source_id for item in group})
        support_counts.append(len(group_sources))
        supporting_sources.update(group_sources)
        raw_variants.append(
            {
                "scope": scope_mapping,
                "value": representative.field.raw_value,
            }
        )
        normalized_variants.append(
            {
                "scope": scope_mapping,
                "value": compared.canonical,
            }
        )

    state = (
        CanonicalFieldState.VERIFIED
        if support_counts and all(count >= 2 for count in support_counts)
        else CanonicalFieldState.SINGLE_SOURCE
    )
    basis = ("disjoint-scoped-variants",)
    if superseded_source_ids:
        basis += ("deterministic-supersession",)

    return FieldReconciliationResult(
        canonical_field=CanonicalField(
            field_name=field_name,
            state=state,
            value={"variants": raw_variants},
            normalized_value={"variants": normalized_variants},
            candidates=_candidates(all_observations),
            evidence_ids=_evidence_ids(all_observations),
        ),
        resolution_basis=basis,
        supporting_source_ids=tuple(sorted(supporting_sources)),
        superseded_source_ids=superseded_source_ids,
    )


def reconcile_field(
    field_name: str,
    reports: Iterable[CandidateExtractionReport],
    sources: Iterable[SourceRecord],
) -> FieldReconciliationResult:
    """Reconcile one field while retaining every candidate/evidence reference."""

    all_observations = collect_candidate_observations(reports, sources)
    observations = tuple(
        item for item in all_observations if item.field.field_name == field_name
    )
    if not observations:
        return FieldReconciliationResult(
            canonical_field=CanonicalField(
                field_name=field_name,
                state=CanonicalFieldState.MISSING,
            ),
            resolution_basis=("no-candidate",),
            supporting_source_ids=(),
        )

    comparisons: list[str] = []
    scopes: list[ScopeDescriptor] = []
    for observation in observations:
        scope = parse_scope(observation.field.scope)
        if not scope.known:
            return _unverified(
                field_name,
                observations,
                basis=("scope-unknown",),
            )
        scopes.append(scope)
        if observation.field.raw_value is None:
            return _unverified(
                field_name,
                observations,
                basis=("raw-value-unusable",),
            )
        try:
            comparisons.append(
                comparison_value(field_name, observation.field.normalized_value).key
            )
        except UnusableNormalizedValue:
            return _unverified(
                field_name,
                observations,
                basis=("normalized-value-unusable",),
            )

    for left_index, left_scope in enumerate(scopes):
        for right_scope in scopes[left_index + 1 :]:
            if scope_relation(left_scope, right_scope) is ScopeRelation.UNKNOWN:
                return _unverified(
                    field_name,
                    observations,
                    basis=("scope-relation-unknown",),
                )

    superseded_indexes: set[int] = set()
    supersession_basis: list[str] = []
    for left_index, left in enumerate(observations):
        for right_index in range(left_index + 1, len(observations)):
            right = observations[right_index]
            if comparisons[left_index] == comparisons[right_index]:
                continue
            relation = scope_relation(scopes[left_index], scopes[right_index])
            if relation not in {ScopeRelation.SAME, ScopeRelation.OVERLAPS}:
                continue

            left_over_right = source_supersedes(left, right, field_name=field_name)
            right_over_left = source_supersedes(right, left, field_name=field_name)
            if left_over_right == right_over_left:
                continue
            if left_over_right:
                superseded_indexes.add(right_index)
                supersession_basis.append(f"{left.source_id}>{right.source_id}")
            else:
                superseded_indexes.add(left_index)
                supersession_basis.append(f"{right.source_id}>{left.source_id}")

    active_indexes = tuple(
        index for index in range(len(observations)) if index not in superseded_indexes
    )
    active = tuple(observations[index] for index in active_indexes)
    if not active:
        return _unverified(
            field_name,
            observations,
            basis=("supersession-eliminated-all-candidates",),
        )

    active_keys = {comparisons[index] for index in active_indexes}
    superseded_source_ids = tuple(
        sorted({observations[index].source_id for index in superseded_indexes})
    )

    if len(active_keys) == 1:
        result = _simple_usable_result(
            field_name,
            active=active,
            all_observations=observations,
            superseded_source_ids=superseded_source_ids,
        )
        if supersession_basis:
            return FieldReconciliationResult(
                canonical_field=result.canonical_field,
                resolution_basis=result.resolution_basis
                + tuple(f"supersedes:{item}" for item in sorted(set(supersession_basis))),
                supporting_source_ids=result.supporting_source_ids,
                superseded_source_ids=result.superseded_source_ids,
            )
        return result

    for active_position, left_index in enumerate(active_indexes):
        for right_index in active_indexes[active_position + 1 :]:
            if comparisons[left_index] == comparisons[right_index]:
                continue
            relation = scope_relation(scopes[left_index], scopes[right_index])
            if relation in {ScopeRelation.SAME, ScopeRelation.OVERLAPS}:
                return _conflict(
                    field_name,
                    observations,
                    superseded_source_ids=superseded_source_ids,
                )
            if relation is ScopeRelation.UNKNOWN:
                return _unverified(
                    field_name,
                    observations,
                    basis=("scope-relation-unknown",),
                )

    return _scoped_result(
        field_name,
        active=active,
        all_observations=observations,
        superseded_source_ids=superseded_source_ids,
    )
