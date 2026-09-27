from __future__ import annotations

from dataclasses import dataclass

from packages.contracts.triage import EligibilityRule


@dataclass(frozen=True)
class ResolvedEligibilityScope:
    """Hasil scope resolution dari layer upstream sebelum masuk triage.

    Triage tidak menentukan category scope dari raw rules. Layer upstream
    harus menyerahkan selected scope, effective eligibility rule, dan trace
    sumber yang menjelaskan dari mana rule tersebut berasal.
    """

    selected_scope: str
    effective_rule: EligibilityRule
    provenance: tuple[str, ...]
    canonical_dimension: str | None = None
    canonical_value: str | None = None

    def __post_init__(self) -> None:
        if not self.selected_scope.strip():
            raise ValueError("selected_scope must not be empty")
        if not self.provenance:
            raise ValueError("resolved eligibility scope requires provenance")
        if (self.canonical_dimension is None) != (self.canonical_value is None):
            raise ValueError(
                "canonical scope dimension and value must be present together"
            )
