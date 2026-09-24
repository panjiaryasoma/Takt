import pytest

from engine.reconciliation import (
    ReconciliationInputError,
    ScopeRelation,
    comparison_value,
    parse_scope,
    scope_relation,
)


def test_scope_relations_are_explicit_and_conservative() -> None:
    literal_general = parse_scope({"category": "general"})
    same_general = parse_scope({"category": "general"})
    student = parse_scope({"category": "student"})
    wildcard = parse_scope({"category": "all"})
    unknown = parse_scope({})

    assert scope_relation(literal_general, same_general) is ScopeRelation.SAME
    assert scope_relation(literal_general, student) is ScopeRelation.DISJOINT
    assert scope_relation(wildcard, student) is ScopeRelation.OVERLAPS
    assert scope_relation(unknown, student) is ScopeRelation.UNKNOWN


def test_general_is_literal_and_all_is_wildcard() -> None:
    general = parse_scope({"category": "general"})
    student = parse_scope({"category": "student"})
    all_categories = parse_scope({"category": "all"})

    assert scope_relation(general, student) is ScopeRelation.DISJOINT
    assert scope_relation(all_categories, student) is ScopeRelation.OVERLAPS


def test_malformed_scope_shape_is_rejected() -> None:
    with pytest.raises(ReconciliationInputError):
        parse_scope("all")

    with pytest.raises(ReconciliationInputError):
        parse_scope({"category": 7})


def test_structured_comparison_is_deterministic() -> None:
    left = comparison_value("team_size", {"max": 4, "min": 1})
    right = comparison_value("team_size", {"min": 1, "max": 4})
    assert left == right
