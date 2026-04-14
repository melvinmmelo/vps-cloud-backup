"""Exception hierarchy for vcb_notify with stable error codes.

Imported by: every module in this package.
Calls out to: nothing.

Codes are documented in docs/errors.md.
"""
from __future__ import annotations

from typing import ClassVar


class NotifyError(Exception):
    """Base class for notifier errors. Never raised directly."""

    code: ClassVar[str] = "VCB-NOTIFY-000"

    def __init__(self, message: str, *, context: dict | None = None) -> None:
        super().__init__(message)
        self.context = context or {}

    def __str__(self) -> str:
        return f"{self.code}: {super().__str__()}"


class NotifyConfigError(NotifyError):
    """VCB-NOTIFY-001 — notifications.conf missing, malformed, or unsafe perms."""

    code = "VCB-NOTIFY-001"


class NotifyProviderNotRegistered(NotifyError):
    """VCB-NOTIFY-002 — the configured provider name is not in the registry."""

    code = "VCB-NOTIFY-002"


class NotifyConnectionError(NotifyError):
    """VCB-NOTIFY-010 — could not reach the notification endpoint (SMTP/HTTP/API)."""

    code = "VCB-NOTIFY-010"


class NotifyAuthError(NotifyConnectionError):
    """VCB-NOTIFY-011 — authentication rejected by the notification provider."""

    code = "VCB-NOTIFY-011"


class NotifySendFailed(NotifyError):
    """VCB-NOTIFY-020 — provider accepted credentials but failed to send the message."""

    code = "VCB-NOTIFY-020"


class NotifyUnknownEvent(NotifyError):
    """VCB-NOTIFY-030 — the caller requested an event name that is not recognized."""

    code = "VCB-NOTIFY-030"
