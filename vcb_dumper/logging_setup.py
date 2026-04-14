"""Unified logging format that interleaves cleanly with bash log output.

Imported by: vcb_dumper.cli, vcb_dumper.orchestrator (for tests).
Calls out to: logging (stdlib).
"""
from __future__ import annotations

import logging

_LEVEL_CHAR = {
    logging.DEBUG: "?",
    logging.INFO: "+",
    logging.WARNING: "!",
    logging.ERROR: "x",
    logging.CRITICAL: "x",
}


class _LevelCharFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.levelchar = _LEVEL_CHAR.get(record.levelno, "?")
        return True


_FMT = "[%(levelchar)s] %(asctime)s %(name)s %(levelname)-7s %(message)s"
_DATEFMT = "%Y-%m-%dT%H:%M:%S%z"


def configure_logging(level: str = "INFO") -> logging.Logger:
    """Set up root logging once. Returns the `vcb_dumper` logger."""
    root = logging.getLogger()
    if getattr(root, "_vcb_configured", False):
        return logging.getLogger("vcb_dumper")

    handler = logging.StreamHandler()
    handler.addFilter(_LevelCharFilter())
    handler.setFormatter(logging.Formatter(_FMT, datefmt=_DATEFMT))

    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(level.upper())
    root._vcb_configured = True  # type: ignore[attr-defined]
    return logging.getLogger("vcb_dumper")
