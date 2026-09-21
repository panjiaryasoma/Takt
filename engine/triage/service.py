from __future__ import annotations

from packages.contracts.triage import (
    ReadinessRequest,
    ReadinessResponse,
    ReadinessStatus,
)


def evaluate_readiness(request: ReadinessRequest) -> ReadinessResponse:
    blocking: list[str] = []
    review: list[str] = []
    passed: list[str] = []

    if request.unresolved_critical_fields:
        review.extend(
            f"unresolved_critical_field:{field}"
            for field in request.unresolved_critical_fields
        )
        return ReadinessResponse(
            status=ReadinessStatus.NEEDS_REVIEW,
            review_items=review,
            passed_checks=passed,
        )

    if request.submission_deadline is None:
        return ReadinessResponse(
            status=ReadinessStatus.INSUFFICIENT_INFORMATION,
            review_items=["submission_deadline_missing"],
        )

    if (
        request.submission_deadline <= request.evaluated_at
        and not request.has_applicable_deadline_extension
    ):
        return ReadinessResponse(
            status=ReadinessStatus.DEADLINE_PASSED,
            blocking_reasons=["authoritative_submission_deadline_passed"],
        )

    passed.append("deadline_valid")

    if not request.mandatory_information_complete:
        return ReadinessResponse(
            status=ReadinessStatus.INSUFFICIENT_INFORMATION,
            review_items=["mandatory_competition_information_missing"],
            passed_checks=passed,
        )

    rules = request.eligibility
    user = request.user

    if rules.minimum_age is not None:
        if user.age is None:
            return ReadinessResponse(
                status=ReadinessStatus.NEEDS_REVIEW,
                review_items=["user_age_unknown"],
                passed_checks=passed,
            )
        if user.age < rules.minimum_age:
            blocking.append("minimum_age_not_met")
            return ReadinessResponse(
                status=ReadinessStatus.ELIGIBILITY_BLOCKED,
                blocking_reasons=blocking,
                passed_checks=passed,
            )
        passed.append("minimum_age_met")

    if rules.requires_student:
        if user.student_status is None:
            return ReadinessResponse(
                status=ReadinessStatus.NEEDS_REVIEW,
                review_items=["student_status_unknown"],
                passed_checks=passed,
            )
        if not user.student_status:
            blocking.append("student_status_requirement_not_met")
            return ReadinessResponse(
                status=ReadinessStatus.ELIGIBILITY_BLOCKED,
                blocking_reasons=blocking,
                passed_checks=passed,
            )
        passed.append("student_status_met")

    normalized_regions = {region.strip().lower() for region in rules.allowed_regions}
    if normalized_regions and "global" not in normalized_regions:
        if user.country is None:
            return ReadinessResponse(
                status=ReadinessStatus.NEEDS_REVIEW,
                review_items=["user_country_unknown"],
                passed_checks=passed,
            )
        if user.country.strip().lower() not in normalized_regions:
            blocking.append("region_requirement_not_met")
            return ReadinessResponse(
                status=ReadinessStatus.ELIGIBILITY_BLOCKED,
                blocking_reasons=blocking,
                passed_checks=passed,
            )
        passed.append("region_eligible")

    passed.append("mandatory_information_complete")

    return ReadinessResponse(
        status=ReadinessStatus.READY_TO_EVALUATE,
        passed_checks=passed,
    )
