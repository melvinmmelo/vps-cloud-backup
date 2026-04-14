"""Dumper ABC — the contract every database engine implements.

Imported by: engines/__init__.py, engines/mysql|postgres|sqlite.py, orchestrator.
Calls out to: subprocess, gzip, pathlib, logging (stdlib).

The ABC defines the public interface. Two shared helpers, _run and
_stream_to_gzip, are methods (not free functions) because they depend on
self._logger and self._staging. Subclasses use composition via these helpers;
inheritance is only for interface conformance.
"""
from __future__ import annotations

import gzip
import logging
import shutil
import subprocess
import time
from abc import ABC, abstractmethod
from datetime import datetime, timezone
from pathlib import Path
from typing import ClassVar

from ..config import EngineConfig
from ..credentials import CredentialStore
from ..errors import DumperDumpFailed, DumperTimeoutError
from ..result import DumpResult


class Dumper(ABC):
    """Abstract base class for a database-engine-specific dumper."""

    engine_name: ClassVar[str] = ""
    label: ClassVar[str] = ""

    def __init__(
        self,
        cfg: EngineConfig,
        creds: CredentialStore,
        staging: Path,
        logger: logging.Logger,
        stamp: str | None = None,
    ) -> None:
        if not self.engine_name:
            raise ValueError(f"{type(self).__name__}.engine_name must be set")
        self._cfg = cfg
        self._creds = creds
        self._staging = staging
        self._logger = logger.getChild(self.engine_name)
        self._stamp = stamp or datetime.now(timezone.utc).strftime("%Y-%m-%d_%H%M%S")

    # ------------------------------------------------------------------
    # Abstract methods — every subclass must implement these.
    # ------------------------------------------------------------------
    @abstractmethod
    def test_connection(self) -> None:
        """Verify the engine is reachable and credentials work.

        Must raise DumperConnectionError / DumperAuthError on failure.
        Returns None on success.
        """

    @abstractmethod
    def discover(self) -> list[str]:
        """Return databases reachable with current credentials.

        Does NOT apply include/exclude filters — that's the orchestrator's
        job. May raise DumperDiscoveryError on protocol failures.
        """

    @abstractmethod
    def dump(self, database: str) -> DumpResult:
        """Dump a single database. MUST return a DumpResult; NEVER raise.

        Per-database errors translate to DumpResult(success=False, ...).
        Only truly unrecoverable errors (e.g. staging dir vanished) may
        raise to the orchestrator.
        """

    # ------------------------------------------------------------------
    # Shared helpers used by subclasses.
    # ------------------------------------------------------------------
    def apply_filters(self, discovered: list[str]) -> list[str]:
        """Apply include/exclude filters. Include wins; empty include = all."""
        include = set(self._cfg.include)
        exclude = set(self._cfg.exclude)
        result = [db for db in discovered if (not include or db in include) and db not in exclude]
        return result

    def _target_path(self, database: str) -> Path:
        subdir = self._staging / self.engine_name
        subdir.mkdir(parents=True, exist_ok=True)
        safe = database.replace("/", "_")
        return subdir / f"{safe}-{self._stamp}.sql.gz"

    def _run(
        self,
        argv: list[str],
        *,
        env: dict[str, str] | None = None,
        timeout: int = 3600,
        check: bool = True,
    ) -> subprocess.CompletedProcess[bytes]:
        """Run a short-lived command for discovery/probing.

        For long-running dumps use _stream_to_gzip instead.
        """
        self._logger.debug("run: %s", _safe_argv(argv))
        try:
            proc = subprocess.run(
                argv,
                env=env,
                capture_output=True,
                timeout=timeout,
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise DumperTimeoutError(
                f"{argv[0]} timed out after {timeout}s",
                context={"argv": argv, "timeout": timeout},
            ) from exc
        except FileNotFoundError as exc:
            raise DumperDumpFailed(
                f"tool not found: {argv[0]}",
                context={"argv": argv},
            ) from exc
        if check and proc.returncode != 0:
            raise DumperDumpFailed(
                f"{argv[0]} exited {proc.returncode}: "
                f"{proc.stderr.decode('utf-8', 'replace').strip()}",
                context={"argv": argv, "returncode": proc.returncode},
            )
        return proc

    def _stream_to_gzip(
        self,
        argv: list[str],
        out_path: Path,
        *,
        env: dict[str, str] | None = None,
        timeout: int = 14400,
    ) -> int:
        """Run argv, pipe its stdout through gzip, write to out_path.

        Returns the number of compressed bytes written.
        Raises DumperDumpFailed on non-zero exit or timeout.
        """
        out_path.parent.mkdir(parents=True, exist_ok=True)
        tmp_path = out_path.with_suffix(out_path.suffix + ".tmp")
        start = time.monotonic()

        # Open the subprocess first so a missing binary produces the
        # specific "tool not found" error, distinct from any later I/O
        # failure against tmp_path / gzip.
        try:
            proc = subprocess.Popen(
                argv,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
            )
        except FileNotFoundError as exc:
            raise DumperDumpFailed(
                f"tool not found: {argv[0]}",
                context={"argv": argv},
            ) from exc

        try:
            assert proc.stdout is not None
            with gzip.open(tmp_path, "wb", compresslevel=6) as gz:
                shutil.copyfileobj(proc.stdout, gz, length=1024 * 1024)
            try:
                _, stderr = proc.communicate(timeout=timeout)
            except subprocess.TimeoutExpired as exc:
                proc.kill()
                proc.wait(timeout=30)
                tmp_path.unlink(missing_ok=True)
                raise DumperTimeoutError(
                    f"{argv[0]} timed out after {timeout}s",
                    context={"argv": argv, "timeout": timeout},
                ) from exc

            if proc.returncode != 0:
                tmp_path.unlink(missing_ok=True)
                raise DumperDumpFailed(
                    f"{argv[0]} exited {proc.returncode}: "
                    f"{stderr.decode('utf-8', 'replace').strip()}",
                    context={"argv": argv, "returncode": proc.returncode},
                )
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait(timeout=30)

        tmp_path.replace(out_path)
        size = out_path.stat().st_size
        duration = time.monotonic() - start
        self._logger.info(
            "dumped %s (%.1f KiB in %.1fs)", out_path.name, size / 1024, duration
        )
        return size


def _safe_argv(argv: list[str]) -> str:
    """Collapse argv for logging without echoing any argument that looks secret."""
    masked = []
    for a in argv:
        if a.startswith("-p") and len(a) > 2:
            masked.append("-p***")
        elif "PASSWORD" in a.upper() or "SECRET" in a.upper():
            masked.append("***")
        else:
            masked.append(a)
    return " ".join(masked)
