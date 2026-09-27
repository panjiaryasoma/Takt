"""Deterministic fingerprint helpers for Issue 4A public contracts."""

from __future__ import annotations

from datetime import UTC, datetime
from collections.abc import Iterable
from typing import Any

from apps.api.canonical_json import jcs_sha256
from apps.api.contracts import (
    SOURCE_SET_FINGERPRINT_VERSION,
    CanonicalReportRefV1,
)
from packages.contracts import CanonicalCompetitionReport


def canonical_utc(value: datetime) -> str:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("datetime must include timezone information")
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def report_wire_material(
    report: CanonicalCompetitionReport,
    ref: CanonicalReportRefV1,
) -> dict[str, Any]:
    return {
        "report": report.model_dump(mode="json", warnings=False),
        "ref": ref.model_dump(
            mode="json",
            exclude={"wire_fingerprint"},
            warnings=False,
        ),
    }


def report_wire_fingerprint(
    report: CanonicalCompetitionReport,
    ref: CanonicalReportRefV1,
) -> str:
    return jcs_sha256(report_wire_material(report, ref))


def source_set_fingerprint(artifacts: Iterable[Any]) -> str:
    """Fingerprint one public source-analysis artifact set in canonical order."""

    material = []
    for artifact in artifacts:
        dumped = artifact.model_dump(mode="json", warnings=False)
        source = dumped.get("source")
        if not isinstance(source, dict) or not isinstance(source.get("source_id"), str):
            raise ValueError("source artifact must expose source.source_id")
        material.append(dumped)

    material.sort(key=lambda item: item["source"]["source_id"])
    return jcs_sha256(
        {
            "version": SOURCE_SET_FINGERPRINT_VERSION,
            "artifacts": material,
        }
    )
