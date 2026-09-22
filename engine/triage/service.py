from __future__ import annotations

from packages.contracts.enums import ReadinessStatus
from packages.contracts.models import ReadinessTriage
from packages.contracts.triage import ReadinessRequest


def evaluate_readiness(request: ReadinessRequest) -> ReadinessTriage:
    """Evaluasi readiness secara deterministik.

    Fungsi ini hanya menangani readiness/eligibility awal.
    Solver, feasibility, recommendation, dan calendar commitment berada
    di luar scope mesin triage.
    """

    passed_checks: list[str] = []

    # Konflik critical tidak boleh diselesaikan diam-diam.
    if request.unresolved_critical_fields:
        return ReadinessTriage(
            status=ReadinessStatus.NEEDS_REVIEW,
            blocking_reasons=[],
            review_items=[
                f"unresolved_critical_field:{field}"
                for field in request.unresolved_critical_fields
            ],
            passed_checks=passed_checks,
            rule_version="1.0",
        )

    # Deadline authoritative adalah critical field untuk readiness.
    if request.submission_deadline is None:
        return ReadinessTriage(
            status=ReadinessStatus.INSUFFICIENT_INFORMATION,
            blocking_reasons=[],
            review_items=["submission_deadline_missing"],
            passed_checks=passed_checks,
            rule_version="1.0",
        )

    # Deadline yang lewat hanya boleh diloloskan jika extension authoritative
    # memang dinyatakan berlaku oleh input contract.
    if (
        request.submission_deadline <= request.evaluated_at
        and not request.has_applicable_deadline_extension
    ):
        return ReadinessTriage(
            status=ReadinessStatus.DEADLINE_PASSED,
            blocking_reasons=["authoritative_submission_deadline_passed"],
            review_items=[],
            passed_checks=passed_checks,
            rule_version="1.0",
        )

    passed_checks.append("deadline_valid")

    # Informasi mandatory yang eksplisit belum lengkap tidak boleh dianggap siap.
    if not request.mandatory_information_complete:
        return ReadinessTriage(
            status=ReadinessStatus.INSUFFICIENT_INFORMATION,
            blocking_reasons=[],
            review_items=["mandatory_competition_information_missing"],
            passed_checks=passed_checks,
            rule_version="1.0",
        )

    rules = request.eligibility
    user = request.user

    # UNKNOWN user attribute != explicit failure.
    if rules.minimum_age is not None:
        if user.age is None:
            return ReadinessTriage(
                status=ReadinessStatus.NEEDS_REVIEW,
                blocking_reasons=[],
                review_items=["user_age_unknown"],
                passed_checks=passed_checks,
                rule_version="1.0",
            )

        if user.age < rules.minimum_age:
            return ReadinessTriage(
                status=ReadinessStatus.ELIGIBILITY_BLOCKED,
                blocking_reasons=["minimum_age_not_met"],
                review_items=[],
                passed_checks=passed_checks,
                rule_version="1.0",
            )

        passed_checks.append("minimum_age_met")

    if rules.requires_student:
        if user.student_status is None:
            return ReadinessTriage(
                status=ReadinessStatus.NEEDS_REVIEW,
                blocking_reasons=[],
                review_items=["student_status_unknown"],
                passed_checks=passed_checks,
                rule_version="1.0",
            )

        if user.student_status is False:
            return ReadinessTriage(
                status=ReadinessStatus.ELIGIBILITY_BLOCKED,
                blocking_reasons=["student_status_requirement_not_met"],
                review_items=[],
                passed_checks=passed_checks,
                rule_version="1.0",
            )

        passed_checks.append("student_status_met")

    normalized_regions = {
        region.strip().lower()
        for region in rules.allowed_regions
        if region.strip()
    }

    # "global" berarti tidak ada region gate.
    if normalized_regions and "global" not in normalized_regions:
        if user.country is None:
            return ReadinessTriage(
                status=ReadinessStatus.NEEDS_REVIEW,
                blocking_reasons=[],
                review_items=["user_country_unknown"],
                passed_checks=passed_checks,
                rule_version="1.0",
            )

        if user.country.strip().lower() not in normalized_regions:
            return ReadinessTriage(
                status=ReadinessStatus.ELIGIBILITY_BLOCKED,
                blocking_reasons=["region_requirement_not_met"],
                review_items=[],
                passed_checks=passed_checks,
                rule_version="1.0",
            )

        passed_checks.append("region_eligible")

    passed_checks.append("mandatory_information_complete")

    return ReadinessTriage(
        status=ReadinessStatus.READY_TO_EVALUATE,
        blocking_reasons=[],
        review_items=[],
        passed_checks=passed_checks,
        rule_version="1.0",
    )
