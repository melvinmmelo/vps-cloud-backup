"""Command-line entry point for the dumper subsystem.

Imported by: __main__.py.
Calls out to: orchestrator, config, credentials, logging_setup.

Usage (from the generated backup script):
    python3 -m vcb_dumper run --config /etc/vps-cloud-backup/db.conf \
                              --staging /var/backups/vcb-staging \
                              --stamp 2026-04-14_023000
"""
from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

from .config import DumperConfig
from .credentials import CredentialStore
from .errors import DumperConfigError, DumperError, DumperStagingError
from .logging_setup import configure_logging
from .orchestrator import DumpOrchestrator


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="vcb-dumper",
        description="Back up MySQL / PostgreSQL / SQLite databases to a staging directory.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    run = sub.add_parser("run", help="Dump every enabled database into the staging dir.")
    run.add_argument("--config", required=True, type=Path, help="Path to db.conf")
    run.add_argument(
        "--staging", type=Path, default=None,
        help="Override staging dir from db.conf",
    )
    run.add_argument("--stamp", type=str, default=None, help="Timestamp string for output filenames")
    run.add_argument("--log-level", default=None, help="Override LOG_LEVEL from config")

    test = sub.add_parser("test", help="Test connections to every enabled engine and exit.")
    test.add_argument("--config", required=True, type=Path, help="Path to db.conf")
    test.add_argument("--log-level", default=None)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        config = DumperConfig.load(args.config)
    except DumperConfigError as exc:
        sys.stderr.write(f"[x] {exc}\n")
        return 2

    log_level = args.log_level or config.log_level
    logger = configure_logging(log_level)

    try:
        creds = CredentialStore.from_file(args.config)
    except DumperConfigError as exc:
        logger.error("credential file error: %s", exc)
        return 2

    if args.staging is not None:
        # Rebuild with the override while preserving immutability.
        config = DumperConfig(
            staging_dir=args.staging,
            log_level=config.log_level,
            stamp_format=config.stamp_format,
            engines=config.engines,
        )

    if args.command == "test":
        return _cmd_test(config, creds, logger)

    return _cmd_run(config, creds, logger, stamp=args.stamp)


def _cmd_run(
    config: DumperConfig, creds: CredentialStore, logger: logging.Logger, *, stamp: str | None
) -> int:
    try:
        orch = DumpOrchestrator(config, creds, logger, stamp=stamp)
        return orch.run()
    except DumperStagingError as exc:
        logger.error("%s", exc)
        return 2
    except DumperError as exc:
        logger.error("fatal: %s", exc)
        return 2
    except Exception as exc:  # noqa: BLE001 — top-level safety net
        logger.exception("unexpected error: %s", exc)
        return 2


def _cmd_test(
    config: DumperConfig, creds: CredentialStore, logger: logging.Logger
) -> int:
    from .engines import ENGINES

    any_fail = False
    for name in config.enabled_engines():
        cls = ENGINES.get(name)
        if cls is None:
            logger.error("engine %s not registered (VCB-DUMP-040)", name)
            any_fail = True
            continue
        cfg = config.engines[name]
        d = cls(cfg=cfg, creds=creds, staging=config.staging_dir, logger=logger)
        try:
            d.test_connection()
            logger.info("%s: OK", d.label)
        except DumperError as exc:
            logger.error("%s: FAIL — %s", d.label, exc)
            any_fail = True
    return 1 if any_fail else 0
