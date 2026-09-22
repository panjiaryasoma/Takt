$ErrorActionPreference = "Stop"

Write-Host "==> Sync dependencies with uv"
uv sync --dev

Write-Host "==> Ruff"
uv run ruff check apps engine packages tests scripts

Write-Host "==> Pytest"
uv run pytest -q

Write-Host "==> Backend quality gate passed"
