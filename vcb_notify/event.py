"""Event — the dataclass passed from the backup script to the notifier.

Imported by: cli, providers/base, providers/gmail, tests.
Calls out to: dataclasses, datetime.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Literal

Severity = Literal["info", "warning", "error"]

# Canonical event names the rest of the system uses.
# Adding a new one means: add to this set + handle it in cli.py.
KNOWN_EVENTS = frozenset(
    {
        "setup.completed",
        "backup.success",
        "backup.failure",
        "backup.partial",
        "test",
    }
)


@dataclass(frozen=True)
class Event:
    """One thing that happened on the VPS that the user may want to know about."""

    name: str
    severity: Severity
    host: str
    public_ip: str
    subject: str
    body: str
    context: dict = field(default_factory=dict)
    at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))

    def headline(self) -> str:
        return f"[vcb:{self.host}] {self.subject}"

    def formatted_body(self) -> str:
        lines = [
            f"Host:        {self.host}",
            f"Public IP:   {self.public_ip}",
            f"Event:       {self.name}",
            f"Severity:    {self.severity.upper()}",
            f"Timestamp:   {self.at.isoformat()}",
            "",
            self.body,
        ]
        if self.context:
            lines += ["", "Context:"]
            for k, v in sorted(self.context.items()):
                lines.append(f"  {k} = {v}")
        return "\n".join(lines)
