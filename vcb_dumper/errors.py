"""Exception hierarchy for vcb_dumper with stable error codes.

Imported by: every module in this package + tests.
Calls out to: nothing (leaf module).

Every public error has:
  - a unique code (format: VCB-DUMP-NNN)
  - a one-line docstring describing cause
  - an entry in docs/errors.md with symptoms + fix

Error codes are stable across releases. Never reuse a retired code.
"""
from __future__ import annotations

from typing import ClassVar


class DumperError(Exception):
    """Base class for every dumper error. Never raised directly."""

    code: ClassVar[str] = "VCB-DUMP-000"

    def __init__(self, message: str, *, context: dict | None = None) -> None:
        super().__init__(message)
        self.context = context or {}

    def __str__(self) -> str:
        return f"{self.code}: {super().__str__()}"


class DumperConfigError(DumperError):
    """VCB-DUMP-001 — db.conf missing, malformed, or has unsafe permissions."""

    code = "VCB-DUMP-001"


class DumperStagingError(DumperError):
    """VCB-DUMP-002 — staging directory missing, unwritable, or wrong owner."""

    code = "VCB-DUMP-002"


class DumperConnectionError(DumperError):
    """VCB-DUMP-010 — engine client tool could not reach the database server."""

    code = "VCB-DUMP-010"


class DumperAuthError(DumperConnectionError):
    """VCB-DUMP-011 — authentication rejected by the database server."""

    code = "VCB-DUMP-011"


class DumperDiscoveryError(DumperError):
    """VCB-DUMP-020 — failed to enumerate databases from the server."""

    code = "VCB-DUMP-020"


class DumperDumpFailed(DumperError):
    """VCB-DUMP-030 — the underlying dump tool exited non-zero or produced empty output."""

    code = "VCB-DUMP-030"


class DumperTimeoutError(DumperError):
    """VCB-DUMP-031 — dump ran longer than the configured timeout and was killed."""

    code = "VCB-DUMP-031"


class DumperRegistryError(DumperError):
    """VCB-DUMP-040 — configured engine name is not registered in engines/__init__.py."""

    code = "VCB-DUMP-040"
