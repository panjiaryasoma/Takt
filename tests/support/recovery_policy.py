"""Python parity adapter for the JSON policy also consumed by 6B tests.

This is test/support policy, never a new API field or an automatic retry engine.
"""

import json
from pathlib import Path

from tests.support.public_error_matrix import PUBLIC_ERROR_MATRIX

POLICY_PATH = Path(__file__).resolve().parents[1] / "fixtures/reliability/recovery_policy_v1.json"


def load_recovery_policy(path=POLICY_PATH):
    policy = json.loads(path.read_text(encoding="utf-8"))
    if set(policy) != {"version", "recovery_classes", "scenarios"}:
        raise ValueError("Unexpected recovery policy shape")
    if policy["version"] != "recovery-policy-v1":
        raise ValueError("Unsupported recovery policy version")
    classes = policy["recovery_classes"]
    if (
        not isinstance(classes, list)
        or not classes
        or not all(isinstance(item, str) and item for item in classes)
        or len(set(classes)) != len(classes)
    ):
        raise ValueError("Invalid recovery classes")
    authority = {(row.endpoint, row.failure_class) for row in PUBLIC_ERROR_MATRIX}
    covered, scenarios = set(), {}
    for row in policy["scenarios"]:
        keys = {"scenario_id", "contract_key", "recovery_class"}
        keys.add("expected_state" if row["contract_key"] is None else "endpoints")
        if set(row) != keys or row["recovery_class"] not in classes:
            raise ValueError("Invalid recovery scenario shape/class")
        scenario_id = row["scenario_id"]
        if not isinstance(scenario_id, str) or not scenario_id or scenario_id in scenarios:
            raise ValueError("Duplicate/invalid recovery scenario identity")
        if row["contract_key"] is None:
            if not isinstance(row["expected_state"], str) or not row["expected_state"]:
                raise ValueError("Domain scenario requires one expected state")
        else:
            endpoints = row["endpoints"]
            if (
                not isinstance(endpoints, list)
                or not endpoints
                or len(set(endpoints)) != len(endpoints)
            ):
                raise ValueError("Invalid recovery endpoints")
            refs = {(endpoint, row["contract_key"]) for endpoint in endpoints}
            if not refs <= authority or covered & refs:
                raise ValueError("Orphan/duplicate public failure reference")
            covered.update(refs)
        scenarios[scenario_id] = row
    if covered != authority:
        raise ValueError("Recovery policy does not cover the 5A public error matrix")
    return scenarios


def recovery_for(scenario_id):
    # Unknown scenarios fail closed; no optimistic automatic-retry default.
    return load_recovery_policy()[scenario_id]["recovery_class"]
