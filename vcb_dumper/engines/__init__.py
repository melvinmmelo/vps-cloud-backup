"""Engine registry — the ONLY place the orchestrator looks up engine classes.

Adding a new engine:
  1. Create engines/<name>.py with a class subclassing Dumper.
  2. Import it here and add it to ENGINES.

Anything else (orchestrator, config, credentials) is untouched.
"""
from __future__ import annotations

from .base import Dumper
from .mysql import MySQLDumper
from .postgres import PostgresDumper
from .sqlite import SQLiteDumper

ENGINES: dict[str, type[Dumper]] = {
    "mysql": MySQLDumper,
    "postgres": PostgresDumper,
    "sqlite": SQLiteDumper,
}

__all__ = ["Dumper", "ENGINES", "MySQLDumper", "PostgresDumper", "SQLiteDumper"]
