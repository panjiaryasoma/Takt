"""Deterministic fingerprint helpers for Issue 4A public contracts."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from apps.api.canonical_json import jcs_sha256
from apps.api.contracts import CanonicalReportRefV1
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
