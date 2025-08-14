.PHONY: help install install-dev test lint format clean build docs run-cluster run-train run-play

help:
	@echo "Available commands:"
	@echo "  make install       - Install the package with uv"
	@echo "  make install-dev   - Install with development dependencies"
	@echo "  make test         - Run tests with pytest"
	@echo "  make lint         - Run linting with ruff"
	@echo "  make format       - Format code with black and ruff"
	@echo "  make clean        - Remove build artifacts and cache files"
	@echo "  make build        - Build the package"
	@echo "  make docs         - Build documentation"
	@echo "  make run-cluster  - Generate card information lookup tables"
	@echo "  make run-train    - Start training a new agent"
	@echo "  make run-play     - Play against trained agent"

install:
	uv sync

install-dev:
	uv sync --all-extras

test:
	uv run pytest

test-verbose:
	uv run pytest -vv

test-coverage:
	uv run pytest --cov=poker_ai --cov-report=html --cov-report=term

lint:
	uv run ruff check poker_ai test
	uv run mypy poker_ai

format:
	uv run black poker_ai test
	uv run ruff check --fix poker_ai test
	uv run isort poker_ai test

clean:
	rm -rf build dist *.egg-info
	rm -rf .pytest_cache .coverage htmlcov
	rm -rf .mypy_cache .ruff_cache
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete
	find . -type f -name "*.pyo" -delete
	find . -type f -name "*.pyd" -delete
	find . -type f -name ".coverage" -delete
	find . -type f -name ".coverage.*" -delete

build:
	uv build

docs:
	cd docs && uv run make html

# Poker AI specific commands
run-cluster:
	uv run poker_ai cluster

run-train:
	uv run poker_ai train start

run-play:
	uv run poker_ai play

run-viz:
	uv run poker_ai viz

# Development shortcuts
dev-setup: install-dev
	@echo "Development environment ready!"
	@echo "Run 'make test' to run tests"
	@echo "Run 'make lint' to check code quality"
	@echo "Run 'make run-cluster' to generate lookup tables before training"