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

    def __post_init__(self) -> None:
        if not self.selected_scope.strip():
            raise ValueError("selected_scope must not be empty")
        if not self.provenance:
            raise ValueError("resolved eligibility scope requires provenance")
