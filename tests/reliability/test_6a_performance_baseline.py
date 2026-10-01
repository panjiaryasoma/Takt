"""Observational fixture timings; deliberately no latency pass/fail thresholds.

Reproduce: uv run python -m tests.reliability.test_6a_performance_baseline \
    --output docs/evidence/6a-performance-baseline.json
"""

import argparse
import hashlib
import json
import math
import os
import platform
import statistics
from contextlib import ExitStack
from datetime import UTC, datetime
from importlib.metadata import version
from pathlib import Path
from time import perf_counter
from unittest.mock import patch

from fastapi.testclient import TestClient

from apps.api.main import app
from apps.api.services.competition_analysis import analyze_url
from apps.api.services.plan_evaluation import evaluate_plan, prepare_evaluation
from apps.api.services.reevaluation import reevaluate_plan
from engine.availability import build_availability
from engine.extraction import (
    TesseractOCRProvider,
    create_pdf_snapshot,
    extract_native_snapshot,
    extract_ocr_snapshot,
    extract_snapshot,
    fetch_url_snapshot,
)
from engine.integration.competition_analysis import build_canonical_report
from engine.scheduler import solve_candidate_allocations
from engine.workload import analyze_workload
from tests.api.test_plan_evaluate_behavior import _prior_request
from tests.reliability.support import (
    PLAN_ENDPOINT,
    REEVALUATE_ENDPOINT,
    URL_ENDPOINT,
    clock,
    mock_source_client,
    plan_request,
    public_dns,
    source_context,
    url_request,
)

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "tests/fixtures/extraction"
STAGES = (
    "native_html",
    "native_pdf",
    "ocr_fixture",
    "reconciliation",
    "availability",
    "solver",
    "plan_evaluate_e2e",
    "competition_analysis_e2e",
    "reevaluation_unchanged_e2e",
)


def _measure(operation, repetitions):
    operation()  # One warm-up; dependency initialization is outside the baseline.
    samples = []
    for _ in range(repetitions):
        started = perf_counter()
        operation()
        samples.append((perf_counter() - started) * 1000)
    return {
        "samples_ms": samples,
        "min_ms": min(samples),
        "median_ms": statistics.median(samples),
        "max_ms": max(samples),
    }


def measure_baseline(repetitions=5):
    if repetitions < 1:
        raise ValueError("repetitions must be positive")
    fixtures = {
        name: (FIXTURES / name).read_bytes()
        for name in (
            "native_competition.html",
            "native_competition.pdf",
            "ocr_competition.pdf",
        )
    }
    request = plan_request(effort_minutes=60)
    prepared = prepare_evaluation(request, clock=clock)
    material = prepared.planning.material
    workload = analyze_workload(request.planning.workload)
    re_request, _ = _prior_request(prior=request)
    provider = TesseractOCRProvider()

    with ExitStack() as stack:
        stack.enter_context(patch("engine.extraction.url_security.socket.getaddrinfo", public_dns))
        source_client = stack.enter_context(mock_source_client(fixtures["native_competition.html"]))
        html = fetch_url_snapshot(
            url_request().url, context=source_context(), client=source_client, retrieved_at=clock()
        )
        pdf = create_pdf_snapshot(
            "native.pdf",
            fixtures["native_competition.pdf"],
            context=source_context(),
            retrieved_at=clock(),
        )
        ocr = create_pdf_snapshot(
            "ocr.pdf",
            fixtures["ocr_competition.pdf"],
            context=source_context(),
            retrieved_at=clock(),
        )
        extracted = extract_snapshot(html)
        stack.enter_context(
            patch(
                "apps.api.routes.plans.evaluate_plan",
                lambda value: evaluate_plan(value, clock=clock),
            )
        )
        stack.enter_context(
            patch(
                "apps.api.routes.plans.reevaluate_plan",
                lambda value: reevaluate_plan(value, clock=clock),
            )
        )
        stack.enter_context(
            patch(
                "apps.api.routes.competitions.analyze_url",
                lambda value: analyze_url(value, client=source_client),
            )
        )
        client = stack.enter_context(TestClient(app))

        def post(endpoint, payload):
            response = client.post(endpoint.split()[1], json=payload)
            assert response.status_code == 200, response.text
            return response.json()

        operations = {
            "native_html": lambda: extract_native_snapshot(html),
            "native_pdf": lambda: extract_native_snapshot(pdf),
            "ocr_fixture": lambda: extract_ocr_snapshot(ocr, provider=provider),
            "reconciliation": lambda: build_canonical_report(
                competition_id="cmp-perf", snapshot_results=(extracted,)
            ),
            "availability": lambda: build_availability(material.availability_input),
            "solver": lambda: solve_candidate_allocations(
                material.availability, workload, material.solver_config
            ),
            "plan_evaluate_e2e": lambda: post(PLAN_ENDPOINT, request.model_dump(mode="json")),
            "competition_analysis_e2e": lambda: post(
                URL_ENDPOINT, url_request().model_dump(mode="json")
            ),
            "reevaluation_unchanged_e2e": lambda: post(
                REEVALUATE_ENDPOINT, re_request.model_dump(mode="json")
            ),
        }
        # Fail rather than record a baseline for a silently empty/broken real OCR path.
        assert "Takt OCR Fixture Hackathon" in operations["ocr_fixture"]().text
        metrics = {name: _measure(operation, repetitions) for name, operation in operations.items()}

    measured_paths = [
        *sorted((ROOT / "engine").rglob("*.py")),
        *sorted((ROOT / "apps/api").rglob("*.py")),
        *sorted((ROOT / "packages/contracts").rglob("*.py")),
        *sorted((ROOT / "tests/reliability").glob("*.py")),
        *sorted((ROOT / "tests/support").glob("*.py")),
        ROOT / "tests/api/test_competition_analysis_behavior.py",
        ROOT / "tests/api/test_plan_evaluate_behavior.py",
        ROOT / "tests/fixtures/reliability/recovery_policy_v1.json",
        ROOT / "uv.lock",
    ]
    digest = hashlib.sha256()
    for path in measured_paths:
        digest.update(str(path.relative_to(ROOT)).encode() + b"\0" + path.read_bytes() + b"\0")
    return {
        "format": "6a-observational-baseline-v1",
        "measured_at_utc": datetime.now(UTC).isoformat(),
        "base_sha": "7986a6fd967f93327b1fcf272095523f90190ad5",
        "measurement_code_sha256": digest.hexdigest(),
        "environment": {
            "python": platform.python_version(),
            "os": platform.system(),
            "architecture": platform.machine(),
            "logical_cpus": os.cpu_count(),
            "dependencies": {
                name: version(name) for name in ("ortools", "pymupdf", "fastapi", "httpx")
            },
            "tesseract": provider.provider_version,
        },
        "method": {
            "clock": "perf_counter",
            "unit": "milliseconds",
            "warmups_per_stage": 1,
            "repetitions": repetitions,
            "latency_thresholds": None,
            "network": "MockTransport and fixed public DNS; external network and Railway excluded",
            "e2e": "In-process HTTP request validation, service execution and response serialization",
            "ocr": "Real two-page image PDF, rasterization and Tesseract; provider initialized before timing",
            "solver": "One LIKELY candidate-pool solve; plan E2E includes all four scenarios",
            "reconciliation": "All canonical fields plus report assembly; extraction outside timing",
            "planning_fixture": "One mandatory 60-minute task; one clipped work window with 99 usable minutes",
            "scope": "Small warm fixture baseline, not production load, concurrency, cold start or SLO evidence",
        },
        "fixtures": {
            name: {"bytes": len(content), "sha256": hashlib.sha256(content).hexdigest()}
            for name, content in fixtures.items()
        },
        "metrics": metrics,
    }


def test_performance_baseline_covers_all_stages_without_latency_thresholds():
    baseline = measure_baseline(repetitions=1)
    assert tuple(baseline["metrics"]) == STAGES
    assert baseline["method"]["latency_thresholds"] is None
    for metric in baseline["metrics"].values():
        assert len(metric["samples_ms"]) == 1
        assert all(math.isfinite(value) and value >= 0 for value in metric["samples_ms"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--repetitions", type=int, default=5)
    args = parser.parse_args()
    baseline = measure_baseline(args.repetitions)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(baseline, indent=2) + "\n", encoding="utf-8")
    print(args.output)
