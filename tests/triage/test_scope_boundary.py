import ast
from pathlib import Path


FORBIDDEN_IMPORT_PREFIXES = (
    "engine.solver",
    "engine.recommendation",
    "engine.feasibility",
)


def test_triage_engine_does_not_import_later_decision_layers() -> None:
    source_path = Path("engine/triage/service.py")
    tree = ast.parse(source_path.read_text(encoding="utf-8"))

    imports: list[str] = []

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imports.extend(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imports.append(node.module)

    assert not any(
        module.startswith(prefix)
        for module in imports
        for prefix in FORBIDDEN_IMPORT_PREFIXES
    )
