"""Kontrak enum bersama untuk Takt.

Nilai enum di file ini mengikuti kontrak pre-production AKTIF.
`StrEnum` dipakai supaya nilai yang diserialisasi ke API tetap sama persis
dengan wire value yang sudah disepakati.
"""

from enum import StrEnum


class ReadinessStatus(StrEnum):
    """Status hasil pemeriksaan kesiapan awal."""

    READY_TO_EVALUATE = "READY_TO_EVALUATE"
    NEEDS_REVIEW = "NEEDS_REVIEW"
    ELIGIBILITY_BLOCKED = "ELIGIBILITY_BLOCKED"
    DEADLINE_PASSED = "DEADLINE_PASSED"
    INSUFFICIENT_INFORMATION = "INSUFFICIENT_INFORMATION"


class FeasibilityStatus(StrEnum):
    """Status kelayakan rencana berdasarkan constraint saat ini."""

    FEASIBLE = "FEASIBLE"
    FEASIBLE_WITH_TRADEOFFS = "FEASIBLE_WITH_TRADEOFFS"
    TIGHT_CAPACITY = "TIGHT_CAPACITY"
    NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS = (
        "NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS"
    )


class CanonicalFieldState(StrEnum):
    """Status rekonsiliasi sebuah field canonical."""

    VERIFIED = "VERIFIED"
    SINGLE_SOURCE = "SINGLE_SOURCE"
    CONFLICT = "CONFLICT"
    MISSING = "MISSING"
    UNVERIFIED = "UNVERIFIED"


class CommitmentType(StrEnum):
    """Sifat commitment pada jadwal user."""

    FIXED = "FIXED"
    FLEXIBLE = "FLEXIBLE"


class RecommendationAction(StrEnum):
    """Aksi eksplisit user terhadap recommendation."""

    ACCEPT = "ACCEPT"
    CHOOSE_ALTERNATIVE = "CHOOSE_ALTERNATIVE"
    EDIT_CONSTRAINTS = "EDIT_CONSTRAINTS"
    IGNORE = "IGNORE"


class AvailabilityType(StrEnum):
    """Tipe blok availability yang diizinkan kontrak aktif."""

    AVAILABLE = "AVAILABLE"
    FIXED_BUSY = "FIXED_BUSY"
    FLEXIBLE_BUSY = "FLEXIBLE_BUSY"
    ACCEPTED_PROJECT_COMMITMENT = "ACCEPTED_PROJECT_COMMITMENT"
