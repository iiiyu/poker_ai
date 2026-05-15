# Repository Guidelines

## Project Structure & Module Organization
The `poker_ai/` package contains all production logic: CFR trainers, evaluators, CLI entrypoints, and shared utilities. API shims and dashboards live in `applications/`, while experiments and scripts are grouped under `research/`, `scripts/`, and `monitoring/`. Tests sit in `test/` next to fixtures, with larger assets in `assets/` and generated artifacts in `trained_agents/` or `lut_checkpoints/`.

## Build, Test, and Development Commands
- `make install` / `make install-dev`: sync dependencies with `uv` (dev adds lint, docs, and typing extras).
- `make test`, `make test-coverage`: execute `uv run pytest` with optional coverage output in `htmlcov/`.
- `make lint` / `make format`: run Ruff + mypy, or apply Black, Ruff autofix, and isort in sequence.
- Poker workflows: `make run-cluster`, `make run-train`, `make run-play`, and `make run-viz` call the CLI (`uv run poker_ai …`) and assume LUTs already exist.

## Coding Style & Naming Conventions
Follow 4-space indentation, type hints, and Python 3.10+ features where they clarify intent. Functions and variables use `snake_case`, classes use `PascalCase`, and constants/config keys stay `UPPER_SNAKE_CASE`. Poker logic stays in `poker_ai/`, orchestration helpers in `applications/` or `scripts/`. New CLI commands should mirror the existing `click` patterns in `poker_ai/cli/` and include short, actionable `--help` strings.

## Testing Guidelines
Pytest is the single framework; name files `test_<feature>.py` and leverage fixtures in `conftest.py`. Every behavioral change needs (1) a unit or evaluator test in `test/` and (2) a workflow check that exercises the CLI (`uv run poker_ai train start`, etc.). Run `make test-coverage` for features touching MCCFR logic to keep evaluator coverage near 80% and update `monitoring/` benchmarks if runtime characteristics shift.

## Commit & Pull Request Guidelines
Recent commits favor concise Conventional Commit prefixes (`feat:`, `fix:`); use them to describe scope and impact. Branch from `develop` (or `git flow feature/<name>`) and keep rebases clean; force-push only to branches you control. Pull requests must target `develop`, link issues, outline affected commands (`make lint`, `make run-train`, etc.), and include screenshots or logs for user-facing changes. CI runs `make lint` and `make test`; run them locally before requesting review.

## Security & Configuration Tips
Generated LUT `.joblib` files and training logs can be huge—keep them out of Git and share download links when reviewers need them. Store API tokens or Slumbot credentials in untracked `.env` files consumed by the scripts, and document new environment keys in the PR so deployers can replicate the setup.
