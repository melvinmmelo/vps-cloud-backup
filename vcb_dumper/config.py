"""DumperConfig — immutable snapshot of /etc/vps-cloud-backup/db.conf.

Imported by: vcb_dumper.cli, vcb_dumper.orchestrator, tests.
Calls out to: pathlib, re, shlex; never to the filesystem beyond read().
"""
from __future__ import annotations

import shlex
from dataclasses import dataclass, field
from pathlib import Path

from .errors import DumperConfigError

# Keys that hold credentials. Filtered out of DumperConfig; handled by CredentialStore.
_SECRET_KEY_PATTERNS = ("PASSWORD", "SECRET", "TOKEN", "ACCESS_KEY")

_KNOWN_ENGINES = ("mysql", "postgres", "sqlite")


@dataclass(frozen=True)
class EngineConfig:
    """Per-engine configuration subset. One of these per engine listed in db.conf."""

    enabled: bool
    include: tuple[str, ...] = ()   # empty = "all discovered databases"
    exclude: tuple[str, ...] = ()   # always excluded on top of engine built-in exclusions
    extra: dict[str, str] = field(default_factory=dict)


@dataclass(frozen=True)
class DumperConfig:
    """Complete runtime configuration for a single dumper invocation."""

    staging_dir: Path
    log_level: str
    stamp_format: str
    engines: dict[str, EngineConfig]

    @classmethod
    def load(cls, path: Path) -> "DumperConfig":
        """Parse a db.conf file. Raises DumperConfigError on anything unexpected.

        The file must be mode 0600, owned by root. See docs/errors.md VCB-DUMP-001.
        """
        _assert_safe_perms(path)
        raw = _parse_file(path)
        return cls._from_raw(raw)

    @classmethod
    def _from_raw(cls, raw: dict[str, str]) -> "DumperConfig":
        try:
            staging_dir = Path(raw.get("STAGING_DIR", "/var/backups/vcb-staging"))
            log_level = raw.get("LOG_LEVEL", "INFO").upper()
            stamp_format = raw.get("STAMP_FORMAT", "%Y-%m-%d_%H%M%S")
        except Exception as exc:
            raise DumperConfigError(f"invalid top-level keys: {exc}") from exc

        engines: dict[str, EngineConfig] = {}
        for eng in _KNOWN_ENGINES:
            prefix = eng.upper()
            enabled = raw.get(f"{prefix}_ENABLED", "0") == "1"
            include = tuple(raw.get(f"{prefix}_INCLUDE", "").split())
            exclude = tuple(raw.get(f"{prefix}_EXCLUDE", "").split())
            extra = {
                k[len(prefix) + 1:]: v
                for k, v in raw.items()
                if k.startswith(f"{prefix}_")
                and k not in (f"{prefix}_ENABLED", f"{prefix}_INCLUDE", f"{prefix}_EXCLUDE")
                and not _is_secret_key(k)
            }
            engines[eng] = EngineConfig(
                enabled=enabled, include=include, exclude=exclude, extra=extra
            )

        return cls(
            staging_dir=staging_dir,
            log_level=log_level,
            stamp_format=stamp_format,
            engines=engines,
        )

    def enabled_engines(self) -> list[str]:
        return [name for name, cfg in self.engines.items() if cfg.enabled]


def _is_secret_key(key: str) -> bool:
    return any(pat in key for pat in _SECRET_KEY_PATTERNS)


def _parse_file(path: Path) -> dict[str, str]:
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        raise DumperConfigError(f"config file not found: {path}") from exc
    except OSError as exc:
        raise DumperConfigError(f"cannot read {path}: {exc}") from exc

    out: dict[str, str] = {}
    for lineno, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise DumperConfigError(
                f"{path}:{lineno} missing '=' in line: {raw_line!r}"
            )
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip()
        if not key.replace("_", "").isalnum():
            raise DumperConfigError(f"{path}:{lineno} invalid key: {key!r}")
        try:
            # shlex.split unwraps bash-style quoting/escaping. When the
            # value round-trips through `printf '%q'` (as db_conf_writer.sh
            # does), an include list like "db1 db2 db3" becomes
            # "db1\ db2\ db3" on disk and parses back to a single token.
            # If a hand-edited file leaves the value unquoted we rejoin
            # the tokens with spaces so callers who then call .split()
            # recover the original list.
            parts = shlex.split(val) if val else [""]
            out[key] = " ".join(parts) if parts else ""
        except ValueError as exc:
            raise DumperConfigError(
                f"{path}:{lineno} cannot parse value for {key}: {exc}"
            ) from exc
    return out


def _assert_safe_perms(path: Path) -> None:
    """Refuse to read the config if it's world/group-readable or not owned by root."""
    try:
        st = path.stat()
    except FileNotFoundError as exc:
        raise DumperConfigError(f"config file not found: {path}") from exc
    if st.st_uid != 0:
        raise DumperConfigError(
            f"{path} must be owned by root (uid=0), found uid={st.st_uid}"
        )
    if st.st_mode & 0o077:
        raise DumperConfigError(
            f"{path} must be mode 0600, found {st.st_mode & 0o777:04o}"
        )
