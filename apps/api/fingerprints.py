"""Deterministic fingerprint helpers for Issue 4A public contracts."""

from __future__ import annotations

import json
import math
from datetime import UTC, date, datetime
from decimal import Decimal
from hashlib import sha256
from typing import Any

from pydantic import BaseModel

from apps.api.contracts import CanonicalReportRefV1
from packages.contracts import CanonicalCompetitionReport

_IJSON_SAFE_INTEGER = 9_007_199_254_740_991


class CanonicalJsonError(ValueError):
    """Raised when material cannot be represented by the JCS/I-JSON subset."""


def canonical_utc(value: datetime) -> str:
    if value.tzinfo is None or value.utcoffset() is None:
        raise CanonicalJsonError("datetime must include timezone information")
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _validate_unicode(value: str) -> None:
    if any(0xD800 <= ord(char) <= 0xDFFF for char in value):
        raise CanonicalJsonError("lone UTF-16 surrogate is not valid I-JSON text")


def _serialize_string(value: str) -> str:
    _validate_unicode(value)
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def _serialize_number(value: int | float) -> str:
    if isinstance(value, bool):
        raise TypeError("bool is not a numeric JCS value")

    if isinstance(value, int):
        if abs(value) > _IJSON_SAFE_INTEGER:
            raise CanonicalJsonError("integer exceeds the I-JSON interoperable range")
        return str(value)

    if not math.isfinite(value):
        raise CanonicalJsonError("non-finite float is not valid JSON")
    if value == 0:
        return "0"

    negative = value < 0
    absolute = -value if negative else value
    raw = repr(absolute).lower()
    decimal = Decimal(raw)
    digits = list(decimal.as_tuple().digits)
    exponent = decimal.as_tuple().exponent
    while len(digits) > 1 and digits[-1] == 0:
        digits.pop()
        exponent += 1

    digits_text = "".join(str(item) for item in digits) or "0"
    decimal_position = len(digits_text) + exponent
    adjusted_exponent = decimal_position - 1

    if 1e-6 <= absolute < 1e21:
        if decimal_position <= 0:
            rendered = "0." + ("0" * (-decimal_position)) + digits_text
        elif decimal_position >= len(digits_text):
            rendered = digits_text + ("0" * (decimal_position - len(digits_text)))
        else:
            rendered = (
                digits_text[:decimal_position]
                + "."
                + digits_text[decimal_position:]
            )
    else:
        fraction = digits_text[1:]
        mantissa = digits_text[0] + (("." + fraction) if fraction else "")
        sign = "+" if adjusted_exponent >= 0 else ""
        rendered = f"{mantissa}e{sign}{adjusted_exponent}"

    return ("-" if negative else "") + rendered


def jcs_dumps(value: Any) -> str:
    """Serialize the supported JSON tree using RFC-8785-compatible ordering.

    The API intentionally rejects non-I-JSON values instead of inventing a
    Python-only representation that Flutter could not reproduce.
    """

    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        return _serialize_number(value)
    if isinstance(value, str):
        return _serialize_string(value)
    if isinstance(value, (list, tuple)):
        return "[" + ",".join(jcs_dumps(item) for item in value) + "]"
    if isinstance(value, dict):
        if any(not isinstance(key, str) for key in value):
            raise CanonicalJsonError("JCS object keys must be strings")
        keys = sorted(
            value,
            key=lambda item: item.encode("utf-16be"),
        )
        return (
            "{"
            + ",".join(
                _serialize_string(key) + ":" + jcs_dumps(value[key])
                for key in keys
            )
            + "}"
        )
    raise CanonicalJsonError(
        f"unsupported canonical JSON value: {type(value).__name__}"
    )


def jcs_sha256(value: Any) -> str:
    encoded = jcs_dumps(value).encode("utf-8")
    return sha256(encoded).hexdigest()


def json_material(value: Any) -> Any:
    """Project Pydantic/domain values to a JSON-compatible deterministic tree."""

    if isinstance(value, BaseModel):
        return value.model_dump(mode="json", warnings=False)
    if isinstance(value, datetime):
        return canonical_utc(value)
    if isinstance(value, date):
        return value.isoformat()
    return value


def report_wire_material(
    report: CanonicalCompetitionReport,
    ref: CanonicalReportRefV1,
) -> dict[str, Any]:
    ref_material = ref.model_dump(
        mode="json",
        exclude={"wire_fingerprint"},
        warnings=False,
    )
    return {
        "report": report.model_dump(mode="json", warnings=False),
        "ref": ref_material,
    }


def report_wire_fingerprint(
    report: CanonicalCompetitionReport,
    ref: CanonicalReportRefV1,
) -> str:
    return jcs_sha256(report_wire_material(report, ref))
