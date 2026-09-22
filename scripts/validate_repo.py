from pathlib import Path

REQUIRED = [
    Path("docs/05_PREPRODUCTION/01_CONTRACTS_ACTIVE/BASELINE_CONTRACT.md"),
    Path("docs/05_PREPRODUCTION/01_CONTRACTS_ACTIVE/FEATURE_SCHEMA_FINAL.yaml"),
    Path("docs/03_EVALUATION_AND_DOMAIN_RULES/domain_rules_v1.0.yaml"),
    Path("docs/03_EVALUATION_AND_DOMAIN_RULES/SOURCE_SCHEMA.md"),
    Path("apps/api/main.py"),
    Path("apps/mobile/lib/data/local/app_database.dart"),
    Path("apps/mobile/lib/domain/contracts.dart"),
    Path("engine/triage/service.py"),
    Path("packages/contracts/enums.py"),
    Path("packages/contracts/triage.py"),
]


def main() -> None:
    missing = [str(path) for path in REQUIRED if not path.exists()]
    if missing:
        raise SystemExit("Missing required repository artifacts:\n- " + "\n- ".join(missing))
    print("Repository baseline validation: PASS")


if __name__ == "__main__":
    main()
