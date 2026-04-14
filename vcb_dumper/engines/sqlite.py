"""SQLiteDumper — consistent copies of SQLite database files via `sqlite3 .backup`.

Imported by: engines/__init__.py, tests.
Calls out to: sqlite3 (the CLI).

SQLite has no credentials. "Discovery" is the list of file paths the user
approved during the bootstrap.
"""
from __future__ import annotations

import gzip
import shutil
import tempfile
import time
from pathlib import Path

from ..errors import DumperConnectionError, DumperDumpFailed
from ..result import DumpResult
from .base import Dumper


class SQLiteDumper(Dumper):
    """File-based SQLite databases. Uses sqlite3 .backup for online consistency."""

    engine_name = "sqlite"
    label = "SQLite"

    # ------------------------------------------------------------------
    def test_connection(self) -> None:
        paths = self._configured_paths()
        if not paths:
            raise DumperConnectionError(
                "no SQLite paths configured (SQLITE_PATHS)",
                context={"sqlite_paths": ""},
            )
        missing = [p for p in paths if not p.is_file()]
        if missing:
            raise DumperConnectionError(
                f"SQLite path(s) not readable: {', '.join(str(p) for p in missing)}",
                context={"missing": [str(p) for p in missing]},
            )
        # Probe sqlite3 tool itself.
        try:
            self._run(["sqlite3", "-version"])
        except DumperDumpFailed as exc:
            raise DumperConnectionError(
                f"sqlite3 CLI not usable: {exc}", context=exc.context
            ) from exc

    # ------------------------------------------------------------------
    def discover(self) -> list[str]:
        paths = self._configured_paths()
        names = [str(p) for p in paths if p.is_file()]
        self._logger.info("discovered %d SQLite files", len(names))
        return names

    # ------------------------------------------------------------------
    def dump(self, database: str) -> DumpResult:
        src = Path(database)
        out = self._target_path(src.name)

        started = time.monotonic()
        with tempfile.TemporaryDirectory(prefix="vcb-sqlite-") as tmpdir:
            snapshot = Path(tmpdir) / src.name
            try:
                # The dot-command is one argv element; inner quotes would
                # end up in the filename on sqlite3's side. The temp path
                # is created by Python so it is guaranteed whitespace-free.
                self._run(
                    [
                        "sqlite3",
                        str(src),
                        f".backup {snapshot}",
                    ]
                )
            except DumperDumpFailed as exc:
                return DumpResult(
                    engine=self.engine_name,
                    database=src.name,
                    path=None,
                    size_bytes=0,
                    duration_seconds=time.monotonic() - started,
                    success=False,
                    error_code=exc.code,
                    error_message=str(exc),
                )

            try:
                out.parent.mkdir(parents=True, exist_ok=True)
                tmp_out = out.with_suffix(out.suffix + ".tmp")
                with snapshot.open("rb") as fin, gzip.open(tmp_out, "wb", compresslevel=6) as fout:
                    shutil.copyfileobj(fin, fout, length=1024 * 1024)
                tmp_out.replace(out)
            except OSError as exc:
                return DumpResult(
                    engine=self.engine_name,
                    database=src.name,
                    path=None,
                    size_bytes=0,
                    duration_seconds=time.monotonic() - started,
                    success=False,
                    error_code="VCB-DUMP-030",
                    error_message=f"cannot compress SQLite snapshot: {exc}",
                )

        return DumpResult(
            engine=self.engine_name,
            database=src.name,
            path=str(out),
            size_bytes=out.stat().st_size,
            duration_seconds=time.monotonic() - started,
            success=True,
            error_code=None,
            error_message=None,
        )

    # ------------------------------------------------------------------
    def _configured_paths(self) -> list[Path]:
        raw = self._cfg.extra.get("PATHS", "")
        return [Path(p) for p in raw.split() if p]
