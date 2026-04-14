"""CredentialStore — typed, masked access to secrets in db.conf.

Imported by: vcb_dumper.cli, vcb_dumper.orchestrator, engines/*.
Calls out to: pathlib, shlex only.

The store NEVER leaks secrets through __repr__, __str__, or logging.
Callers use typed accessors (mysql_password, postgres_password, ...).
"""
from __future__ import annotations

from pathlib import Path
from typing import Literal

from .errors import DumperConfigError

_SECRET_KEY_PATTERNS = ("PASSWORD", "SECRET", "TOKEN", "ACCESS_KEY")

MySQLAuth = Literal["socket", "my_cnf", "password"]
PostgresAuth = Literal["peer", "pgpass", "password"]


class CredentialStore:
    """Holds secret-bearing keys from db.conf. Typed accessors only."""

    def __init__(self, raw: dict[str, str]) -> None:
        self._raw = dict(raw)

    @classmethod
    def from_file(cls, path: Path) -> "CredentialStore":
        from .config import _assert_safe_perms, _parse_file  # reuse parser

        _assert_safe_perms(path)
        raw = _parse_file(path)
        return cls(raw)

    def _get(self, key: str, default: str | None = None) -> str | None:
        return self._raw.get(key, default)

    # --- MySQL ------------------------------------------------------------
    def mysql_auth_method(self) -> MySQLAuth:
        val = self._get("MYSQL_AUTH", "socket") or "socket"
        if val not in ("socket", "my_cnf", "password"):
            raise DumperConfigError(f"MYSQL_AUTH must be socket|my_cnf|password, got {val!r}")
        return val  # type: ignore[return-value]

    def mysql_user(self) -> str:
        return self._get("MYSQL_USER", "root") or "root"

    def mysql_host(self) -> str:
        return self._get("MYSQL_HOST", "localhost") or "localhost"

    def mysql_port(self) -> int:
        return int(self._get("MYSQL_PORT", "3306") or 3306)

    def mysql_socket(self) -> str:
        return self._get("MYSQL_SOCKET", "/var/run/mysqld/mysqld.sock") or ""

    def mysql_defaults_file(self) -> str:
        return self._get("MYSQL_DEFAULTS_FILE", "/root/.my.cnf") or ""

    def mysql_password(self) -> str | None:
        return self._get("MYSQL_PASSWORD")

    # --- Postgres ---------------------------------------------------------
    def postgres_auth_method(self) -> PostgresAuth:
        val = self._get("POSTGRES_AUTH", "peer") or "peer"
        if val not in ("peer", "pgpass", "password"):
            raise DumperConfigError(f"POSTGRES_AUTH must be peer|pgpass|password, got {val!r}")
        return val  # type: ignore[return-value]

    def postgres_user(self) -> str:
        return self._get("POSTGRES_USER", "postgres") or "postgres"

    def postgres_host(self) -> str:
        return self._get("POSTGRES_HOST", "localhost") or "localhost"

    def postgres_port(self) -> int:
        return int(self._get("POSTGRES_PORT", "5432") or 5432)

    def postgres_password(self) -> str | None:
        return self._get("POSTGRES_PASSWORD")

    # --- masking ----------------------------------------------------------
    def _visible_keys(self) -> list[str]:
        return sorted(k for k in self._raw if not _is_secret(k))

    def _secret_count(self) -> int:
        return sum(1 for k in self._raw if _is_secret(k))

    def __repr__(self) -> str:
        return (
            f"CredentialStore(visible={self._visible_keys()}, "
            f"secrets={self._secret_count()} masked)"
        )

    __str__ = __repr__


def _is_secret(key: str) -> bool:
    return any(pat in key for pat in _SECRET_KEY_PATTERNS)
