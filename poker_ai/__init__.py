from __future__ import annotations

import logging

try:
    from rich.logging import RichHandler
    handlers = [RichHandler()]
except ImportError:
    # Fallback to standard handler if rich is not installed
    handlers = [logging.StreamHandler()]

FORMAT = "%(message)s"
logging.basicConfig(
    format=FORMAT,
    datefmt="[%X] ",
    handlers=handlers,
    level=logging.INFO,
)

# Lazy imports to avoid dependency issues
# Only import modules when explicitly needed
__all__ = [
    "ai",
    "cli", 
    "clustering",
    "games",
    "poker",
    "terminal",
    "utils",
    "viz",
]

__version__ = "1.0.0rc3"
