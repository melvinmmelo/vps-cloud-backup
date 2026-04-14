"""Notifier ABC — the contract every notification channel implements.

Imported by: providers/__init__.py, providers/<name>.py, cli.
Calls out to: logging (stdlib only).
"""
from __future__ import annotations

import logging
from abc import ABC, abstractmethod
from typing import ClassVar

from ..config import ProviderConfig
from ..event import Event


class Notifier(ABC):
    """Abstract base class for a notification channel.

    Subclasses must set `provider_name` and `label`, and implement `send`
    and `test`. The base class holds a pristine ProviderConfig, the current
    Event context, and a logger scoped to `vcb_notify.<provider_name>`.
    """

    provider_name: ClassVar[str] = ""
    label: ClassVar[str] = ""

    def __init__(self, cfg: ProviderConfig, logger: logging.Logger) -> None:
        if not self.provider_name:
            raise ValueError(f"{type(self).__name__}.provider_name must be set")
        self._cfg = cfg
        self._logger = logger.getChild(self.provider_name)

    def handles(self, event_name: str) -> bool:
        """Return True if this provider is subscribed to event_name."""
        if not self._cfg.enabled:
            return False
        if not self._cfg.events:
            return True  # empty subscription list = all events
        return event_name in self._cfg.events

    # ------------------------------------------------------------------
    @abstractmethod
    def send(self, event: Event) -> None:
        """Deliver the event. Raise NotifyError on failure."""

    @abstractmethod
    def test(self) -> None:
        """Deliver a test notification. Raise NotifyError on failure."""
