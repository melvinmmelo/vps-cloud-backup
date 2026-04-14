"""Notification provider registry — single edit point for adding a new channel.

Adding a new provider:
  1. Create providers/<name>.py with a class subclassing Notifier.
  2. Import it here and register it in PROVIDERS.
"""
from __future__ import annotations

from .base import Notifier
from .gmail import GmailNotifier

PROVIDERS: dict[str, type[Notifier]] = {
    "gmail": GmailNotifier,
}

__all__ = ["Notifier", "PROVIDERS", "GmailNotifier"]
