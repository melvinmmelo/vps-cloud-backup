"""PostgresDumper — dumps PostgreSQL databases via pg_dump.

Imported by: engines/__init__.py, tests.
Calls out to: psql, pg_dump, sudo (for peer auth).

Password is passed via the PGPASSWORD environment variable, never argv.
"""
from __future__ import annotations

import os
import time

from ..errors import (
    DumperAuthError,
    DumperConnectionError,
    DumperDiscoveryError,
    DumperDumpFailed,
)
from ..result import DumpResult
from .base import Dumper

_ALWAYS_EXCLUDE = frozenset({"template0", "template1"})


class PostgresDumper(Dumper):
    """PostgreSQL dumper using plain-text SQL via gzip for consistency with .sql.gz."""

    engine_name = "postgres"
    label = "PostgreSQL"

    # ------------------------------------------------------------------
    def test_connection(self) -> None:
        try:
            self._run(self._client_argv(["-c", "SELECT 1"]), env=self._client_env())
        except DumperDumpFailed as exc:
            msg = str(exc).lower()
            if "authentication" in msg or "password" in msg or "role" in msg:
                raise DumperAuthError(
                    f"PostgreSQL authentication failed: {exc}", context=exc.context
                ) from exc
            raise DumperConnectionError(
                f"PostgreSQL unreachable: {exc}", context=exc.context
            ) from exc

    # ------------------------------------------------------------------
    def discover(self) -> list[str]:
        sql = "SELECT datname FROM pg_database WHERE datistemplate = false"
        try:
            proc = self._run(
                self._client_argv(["-Atc", sql]),
                env=self._client_env(),
            )
        except DumperDumpFailed as exc:
            raise DumperDiscoveryError(
                f"pg_database query failed: {exc}", context=exc.context
            ) from exc

        names = [
            line.strip()
            for line in proc.stdout.decode("utf-8", "replace").splitlines()
            if line.strip() and line.strip() not in _ALWAYS_EXCLUDE
        ]
        self._logger.info("discovered %d Postgres databases", len(names))
        return names

    # ------------------------------------------------------------------
    def dump(self, database: str) -> DumpResult:
        out = self._target_path(database)
        argv = self._pg_dump_argv(database)

        started = time.monotonic()
        try:
            size = self._stream_to_gzip(argv, out, env=self._client_env())
        except Exception as exc:
            self._logger.error(
                "postgres dump failed for %s: %s", database, exc
            )
            code = getattr(exc, "code", "VCB-DUMP-030")
            return DumpResult(
                engine=self.engine_name,
                database=database,
                path=None,
                size_bytes=0,
                duration_seconds=time.monotonic() - started,
                success=False,
                error_code=code,
                error_message=str(exc),
            )

        return DumpResult(
            engine=self.engine_name,
            database=database,
            path=str(out),
            size_bytes=size,
            duration_seconds=time.monotonic() - started,
            success=True,
            error_code=None,
            error_message=None,
        )

    # ------------------------------------------------------------------
    def _client_argv(self, extra: list[str]) -> list[str]:
        """argv for psql (read-only)."""
        method = self._creds.postgres_auth_method()
        if method == "peer":
            return ["sudo", "-u", self._creds.postgres_user(), "psql", *extra]
        base = [
            "psql",
            "-h", self._creds.postgres_host(),
            "-p", str(self._creds.postgres_port()),
            "-U", self._creds.postgres_user(),
        ]
        return base + extra

    def _pg_dump_argv(self, database: str) -> list[str]:
        method = self._creds.postgres_auth_method()
        if method == "peer":
            return [
                "sudo", "-u", self._creds.postgres_user(),
                "pg_dump",
                "--format=plain",
                "--no-owner",
                "--no-privileges",
                database,
            ]
        return [
            "pg_dump",
            "-h", self._creds.postgres_host(),
            "-p", str(self._creds.postgres_port()),
            "-U", self._creds.postgres_user(),
            "--format=plain",
            "--no-owner",
            "--no-privileges",
            database,
        ]

    def _client_env(self) -> dict[str, str]:
        env = os.environ.copy()
        if self._creds.postgres_auth_method() == "password":
            pw = self._creds.postgres_password()
            if pw:
                env["PGPASSWORD"] = pw
        return env
