"""DumpOrchestrator — top-level coordinator for a single dumper run.

Imported by: vcb_dumper.cli.
Calls out to: engines.*, result.DumperRun.

The orchestrator composes engine instances from the registry, runs
test_connection + discover + dump per engine, records results in a
DumperRun, writes summary.json, and returns an exit code.
"""
from __future__ import annotations

import logging
import os
import time
from datetime import datetime, timezone
from pathlib import Path

from .config import DumperConfig
from .credentials import CredentialStore
from .engines import ENGINES, Dumper
from .errors import (
    DumperConnectionError,
    DumperDiscoveryError,
    DumperRegistryError,
    DumperStagingError,
)
from .result import DumpResult, DumperRun


class DumpOrchestrator:
    """Runs a full dumper pipeline and writes a summary."""

    def __init__(
        self,
        config: DumperConfig,
        creds: CredentialStore,
        logger: logging.Logger,
        stamp: str | None = None,
    ) -> None:
        self._config = config
        self._creds = creds
        self._logger = logger.getChild("orchestrator")
        self._stamp = stamp or datetime.now(timezone.utc).strftime("%Y-%m-%d_%H%M%S")
        self._run_state = DumperRun(started_at=datetime.now(timezone.utc))

    # ------------------------------------------------------------------
    def run(self) -> int:
        """Execute the full pipeline. Returns an exit code.

        Exit codes:
          0 — every dump succeeded (or zero engines enabled, which is fine)
          1 — at least one dump failed but at least one succeeded OR all
              dumps failed but for recoverable per-engine reasons
          2 — catastrophic failure: config error, unwritable staging, etc.
        """
        # SQL dump files contain raw database rows. Force root-only perms
        # for everything the run creates (staging subdirs, .sql.gz files,
        # summary.json) regardless of the inherited process umask.
        prev_umask = os.umask(0o077)
        try:
            self._assert_staging_writable()
            dumpers = self._build_dumpers()

            if not dumpers:
                self._logger.info("no engines enabled — nothing to dump")
                self._write_summary()
                return 0

            for dumper in dumpers:
                self._process_engine(dumper)

            self._write_summary()
            return self._run_state.overall_exit_code()
        finally:
            os.umask(prev_umask)

    # ------------------------------------------------------------------
    def _assert_staging_writable(self) -> None:
        staging = self._config.staging_dir
        try:
            staging.mkdir(parents=True, exist_ok=True)
            staging.chmod(0o700)
        except OSError as exc:
            raise DumperStagingError(
                f"cannot create staging dir {staging}: {exc}",
                context={"staging": str(staging)},
            ) from exc
        probe = staging / ".vcb-writable"
        try:
            probe.write_text("ok")
            probe.unlink()
        except OSError as exc:
            raise DumperStagingError(
                f"staging dir {staging} is not writable: {exc}",
                context={"staging": str(staging)},
            ) from exc

    # ------------------------------------------------------------------
    def _build_dumpers(self) -> list[Dumper]:
        """Iterate over every engine declared in the config, not a hardcoded
        list, so adding a new engine requires zero edits here."""
        built: list[Dumper] = []
        for name, cfg in self._config.engines.items():
            if not cfg.enabled:
                continue
            cls = ENGINES.get(name)
            if cls is None:
                raise DumperRegistryError(
                    f"engine {name!r} enabled but not registered",
                    context={"engine": name},
                )
            built.append(
                cls(
                    cfg=cfg,
                    creds=self._creds,
                    staging=self._config.staging_dir,
                    logger=self._logger.parent or self._logger,
                    stamp=self._stamp,
                )
            )
        return built

    # ------------------------------------------------------------------
    def _process_engine(self, dumper: Dumper) -> None:
        self._logger.info("=== engine: %s ===", dumper.label)

        try:
            dumper.test_connection()
        except DumperConnectionError as exc:
            self._logger.error("skipping %s: %s", dumper.engine_name, exc)
            self._record_engine_skipped(dumper, exc.code, str(exc))
            return

        try:
            discovered = dumper.discover()
        except DumperDiscoveryError as exc:
            self._logger.error("discovery failed for %s: %s", dumper.engine_name, exc)
            self._record_engine_skipped(dumper, exc.code, str(exc))
            return

        selected = dumper.apply_filters(discovered)
        if not selected:
            self._logger.warning(
                "no databases selected for %s after filters", dumper.engine_name
            )
            return

        for db in selected:
            t0 = time.monotonic()
            result = dumper.dump(db)
            self._run_state.record(result)
            suffix = "OK" if result.success else f"FAIL ({result.error_code})"
            self._logger.info(
                "%s.%s: %s in %.1fs",
                dumper.engine_name, db, suffix, time.monotonic() - t0,
            )

    def _record_engine_skipped(self, dumper: Dumper, code: str, message: str) -> None:
        self._run_state.record(
            DumpResult(
                engine=dumper.engine_name,
                database="(engine)",
                path=None,
                size_bytes=0,
                duration_seconds=0.0,
                success=False,
                error_code=code,
                error_message=message,
            )
        )

    def _write_summary(self) -> None:
        path = self._config.staging_dir / "summary.json"
        self._run_state.write_summary(path)
        self._logger.info("summary written to %s", path)
