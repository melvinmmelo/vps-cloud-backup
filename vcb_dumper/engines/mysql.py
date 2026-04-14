"""MySQLDumper — dumps MySQL and MariaDB databases via mysqldump.

Imported by: engines/__init__.py, tests.
Calls out to: mysql, mysqldump (via Dumper._run / _stream_to_gzip).

Credentials never appear on argv. Passwords are passed via the MYSQL_PWD
environment variable to the mysql/mysqldump client, per the official docs.
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

_SYSTEM_SCHEMAS = frozenset({"mysql", "information_schema", "performance_schema", "sys"})


class MySQLDumper(Dumper):
    """MySQL / MariaDB dumper. Always excludes system schemas."""

    engine_name = "mysql"
    label = "MySQL / MariaDB"

    # ------------------------------------------------------------------
    def test_connection(self) -> None:
        try:
            self._run(self._client_argv(["-e", "SELECT 1"]), env=self._client_env())
        except DumperDumpFailed as exc:
            msg = str(exc).lower()
            if "access denied" in msg or "authentication" in msg:
                raise DumperAuthError(
                    f"MySQL authentication failed: {exc}", context=exc.context
                ) from exc
            raise DumperConnectionError(
                f"MySQL unreachable: {exc}", context=exc.context
            ) from exc

    # ------------------------------------------------------------------
    def discover(self) -> list[str]:
        try:
            proc = self._run(
                self._client_argv(["-N", "-B", "-e", "SHOW DATABASES"]),
                env=self._client_env(),
            )
        except DumperDumpFailed as exc:
            raise DumperDiscoveryError(
                f"SHOW DATABASES failed: {exc}", context=exc.context
            ) from exc

        names = [
            line.strip()
            for line in proc.stdout.decode("utf-8", "replace").splitlines()
            if line.strip() and line.strip() not in _SYSTEM_SCHEMAS
        ]
        self._logger.info("discovered %d MySQL databases", len(names))
        return names

    # ------------------------------------------------------------------
    def dump(self, database: str) -> DumpResult:
        out = self._target_path(database)
        argv = [
            "mysqldump",
            "--single-transaction",
            "--routines",
            "--triggers",
            "--events",
            "--set-gtid-purged=OFF",
        ]
        argv += self._dump_auth_args()
        argv += [database]

        started = time.monotonic()
        try:
            size = self._stream_to_gzip(argv, out, env=self._client_env())
        except Exception as exc:
            self._logger.error(
                "mysql dump failed for %s: %s", database, exc
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
        """argv for the `mysql` client (read-only operations)."""
        method = self._creds.mysql_auth_method()
        base = ["mysql"]
        if method == "socket":
            base += ["--protocol=socket", "-u", self._creds.mysql_user()]
            sock = self._creds.mysql_socket()
            if sock:
                base += [f"--socket={sock}"]
        elif method == "my_cnf":
            base += [f"--defaults-file={self._creds.mysql_defaults_file()}"]
        else:  # password
            base += [
                "-u", self._creds.mysql_user(),
                "-h", self._creds.mysql_host(),
                "-P", str(self._creds.mysql_port()),
            ]
        return base + extra

    def _dump_auth_args(self) -> list[str]:
        """auth args for mysqldump (appended to the mysqldump argv)."""
        method = self._creds.mysql_auth_method()
        if method == "socket":
            sock = self._creds.mysql_socket()
            args = ["--protocol=socket", "-u", self._creds.mysql_user()]
            if sock:
                args += [f"--socket={sock}"]
            return args
        if method == "my_cnf":
            return [f"--defaults-file={self._creds.mysql_defaults_file()}"]
        return [
            "-u", self._creds.mysql_user(),
            "-h", self._creds.mysql_host(),
            "-P", str(self._creds.mysql_port()),
        ]

    def _client_env(self) -> dict[str, str]:
        env = os.environ.copy()
        if self._creds.mysql_auth_method() == "password":
            pw = self._creds.mysql_password()
            if pw:
                env["MYSQL_PWD"] = pw
        return env
