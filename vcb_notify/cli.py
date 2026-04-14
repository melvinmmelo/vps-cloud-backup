"""Command-line entry point for the notifier subsystem.

Imported by: __main__.py.
Calls out to: config, providers.PROVIDERS.

Usage (from the generated backup script or bootstrap):
    python3 -m vcb_notify send --event backup.failure \
        --subject "backup failed" --body "..." [--context key=val ...]
    python3 -m vcb_notify test  --provider gmail
"""
from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

from .config import NotificationConfig
from .errors import NotifyConfigError, NotifyError, NotifyProviderNotRegistered, NotifyUnknownEvent
from .event import KNOWN_EVENTS, Event
from .providers import PROVIDERS

_DEFAULT_CONFIG = Path("/etc/vps-cloud-backup/notifications.conf")
_LOG_FMT = "[%(levelname).1s] %(asctime)s %(name)s %(message)s"
_LOG_DATEFMT = "%Y-%m-%dT%H:%M:%S%z"


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="vcb-notify",
        description="Send notifications to the channels configured in notifications.conf.",
    )
    p.add_argument("--config", type=Path, default=_DEFAULT_CONFIG)
    p.add_argument("--log-level", default="INFO")

    sub = p.add_subparsers(dest="command", required=True)

    send = sub.add_parser("send", help="Send an event notification.")
    send.add_argument("--event", required=True, choices=sorted(KNOWN_EVENTS))
    send.add_argument("--severity", default="info", choices=("info", "warning", "error"))
    send.add_argument("--subject", required=True)
    send.add_argument("--body", default="")
    send.add_argument("--context", action="append", default=[], help="key=value, repeatable")

    test = sub.add_parser("test", help="Send a test notification to one or all providers.")
    test.add_argument("--provider", default=None)

    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    logging.basicConfig(level=args.log_level.upper(), format=_LOG_FMT, datefmt=_LOG_DATEFMT)
    logger = logging.getLogger("vcb_notify")

    try:
        config = NotificationConfig.load(args.config)
    except NotifyConfigError as exc:
        logger.error("%s", exc)
        return 2

    if args.command == "test":
        return _cmd_test(config, logger, only=args.provider)
    return _cmd_send(config, logger, args)


def _cmd_send(config: NotificationConfig, logger: logging.Logger, args) -> int:
    if args.event not in KNOWN_EVENTS:
        logger.error("%s", NotifyUnknownEvent(f"unknown event: {args.event}"))
        return 2

    context = {}
    for pair in args.context:
        if "=" not in pair:
            logger.warning("ignoring malformed --context %r (expected key=value)", pair)
            continue
        k, _, v = pair.partition("=")
        context[k.strip()] = v.strip()

    event = Event(
        name=args.event,
        severity=args.severity,
        host=config.host,
        public_ip=config.public_ip,
        subject=args.subject,
        body=args.body,
        context=context,
    )

    any_fail = False
    any_sent = False
    for name in config.enabled_providers():
        cls = PROVIDERS.get(name)
        if cls is None:
            logger.error("%s", NotifyProviderNotRegistered(f"provider {name} not registered"))
            any_fail = True
            continue
        inst = cls(cfg=config.providers[name], logger=logger)
        if not inst.handles(event.name):
            logger.debug("%s not subscribed to %s, skipping", name, event.name)
            continue
        try:
            inst.send(event)
            any_sent = True
        except NotifyError as exc:
            logger.error("%s: %s", name, exc)
            any_fail = True

    if any_fail and any_sent:
        return 1
    if any_fail:
        return 2
    return 0


def _cmd_test(config: NotificationConfig, logger: logging.Logger, *, only: str | None) -> int:
    any_fail = False
    tested_any = False
    for name, pcfg in config.providers.items():
        if only and name != only:
            continue
        if not pcfg.enabled:
            logger.info("%s: disabled, skipping", name)
            continue
        cls = PROVIDERS.get(name)
        if cls is None:
            logger.error("%s: not registered", name)
            any_fail = True
            continue
        inst = cls(cfg=pcfg, logger=logger)
        try:
            inst.test()
            logger.info("%s: test OK", name)
            tested_any = True
        except NotifyError as exc:
            logger.error("%s: test FAIL — %s", name, exc)
            any_fail = True
    if not tested_any and not any_fail:
        logger.warning("no providers tested")
    return 0 if not any_fail else 1
