"""DumpResult + DumperRun — per-database and per-run outcomes.

Imported by: engines/base.py, orchestrator, cli, tests.
Calls out to: dataclasses, json, pathlib only.
"""
from __future__ import annotations

import json
import os
import tempfile
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path


@dataclass(frozen=True)
class DumpResult:
    """Outcome of a single database dump attempt. Immutable."""

    engine: str
    database: str
    path: str | None           # None if dump failed before opening a file
    size_bytes: int            # 0 if failed
    duration_seconds: float
    success: bool
    error_code: str | None     # e.g. "VCB-DUMP-030", None on success
    error_message: str | None  # None on success


class DumperRun:
    """Mutable aggregator of DumpResults for one orchestrator run."""

    def __init__(self, started_at: datetime | None = None) -> None:
        self.started_at = started_at or datetime.now(timezone.utc)
        self._results: list[DumpResult] = []

    def record(self, result: DumpResult) -> None:
        self._results.append(result)

    @property
    def results(self) -> tuple[DumpResult, ...]:
        return tuple(self._results)

    @property
    def total(self) -> int:
        return len(self._results)

    @property
    def succeeded(self) -> int:
        return sum(1 for r in self._results if r.success)

    @property
    def failed(self) -> int:
        return sum(1 for r in self._results if not r.success)

    def overall_exit_code(self) -> int:
        """0 = all clean, 1 = partial (at least one succeeded and one failed),
        2 only for catastrophic failures raised outside this aggregator."""
        if not self._results:
            return 0
        if self.failed == 0:
            return 0
        if self.succeeded == 0:
            return 1  # total failure of all dumps is still "partial" at this layer;
                      # the orchestrator promotes to 2 only on catastrophic errors.
        return 1

    def to_summary(self) -> dict:
        return {
            "version": 1,
            "started_at": self.started_at.isoformat(),
            "finished_at": datetime.now(timezone.utc).isoformat(),
            "total": self.total,
            "succeeded": self.succeeded,
            "failed": self.failed,
            "exit_code": self.overall_exit_code(),
            "results": [asdict(r) for r in self._results],
        }

    def write_summary(self, path: Path) -> None:
        """Atomic JSON write of the run summary."""
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            mode="w", dir=path.parent, delete=False, suffix=".tmp"
        ) as tmp:
            json.dump(self.to_summary(), tmp, indent=2)
            tmp.flush()
            os.fsync(tmp.fileno())
            tmp_name = tmp.name
        os.replace(tmp_name, path)
