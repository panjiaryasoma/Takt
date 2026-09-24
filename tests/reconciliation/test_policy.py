from engine.reconciliation import ScopeRelation, comparison_value, parse_scope, scope_relation


def test_scope_relations_are_explicit_and_conservative() -> None:
    general = parse_scope({"category": "general"})
    same = parse_scope({"category": "general"})
    student = parse_scope({"category": "student"})
    wildcard = parse_scope({"category": "all"})
    unknown = parse_scope({})

    assert scope_relation(general, same) is ScopeRelation.SAME
    assert scope_relation(general, student) is ScopeRelation.DISJOINT
    assert scope_relation(wildcard, student) is ScopeRelation.OVERLAPS
    assert scope_relation(unknown, student) is ScopeRelation.UNKNOWN


def test_structured_comparison_is_deterministic() -> None:
    left = comparison_value("team_size", {"max": 4, "min": 1})
    right = comparison_value("team_size", {"min": 1, "max": 4})
    assert left == right
