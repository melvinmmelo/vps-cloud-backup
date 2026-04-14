"""NotificationConfig — immutable snapshot of /etc/vps-cloud-backup/notifications.conf.

Imported by: cli, providers/gmail, tests.
Calls out to: pathlib, shlex.

Shares the "shell KEY=value" format with db.conf. Uses the same safe-perms
check so secrets never live in a world-readable file.
"""
from __future__ import annotations

import shlex
from dataclasses import dataclass, field
from pathlib import Path

from .errors import NotifyConfigError


@dataclass(frozen=True)
class ProviderConfig:
    """Per-provider settings. Values are raw strings from the config file."""

    enabled: bool
    events: tuple[str, ...]
    extra: dict[str, str] = field(default_factory=dict)


@dataclass(frozen=True)
class NotificationConfig:
    """Complete notifier configuration, loaded once per CLI invocation."""

    host: str
    public_ip: str
    providers: dict[str, ProviderConfig]
    raw: dict[str, str]

    @classmethod
    def load(cls, path: Path) -> "NotificationConfig":
        """Parse notifications.conf. Raises NotifyConfigError on any problem."""
        _assert_safe_perms(path)
        raw = _parse_file(path)
        return cls._from_raw(raw)

    @classmethod
    def _from_raw(cls, raw: dict[str, str]) -> "NotificationConfig":
        host = raw.get("HOST", "unknown")
        public_ip = raw.get("PUBLIC_IP", "unknown")

        providers: dict[str, ProviderConfig] = {}
        # One provider per prefix. Current prefixes: GMAIL_, (future: TELEGRAM_, SLACK_, ...)
        for name in _discover_provider_names(raw):
            prefix = name.upper() + "_"
            enabled = raw.get(f"{prefix}ENABLED", "0") == "1"
            events = tuple(raw.get(f"{prefix}EVENTS", "").split())
            extra = {
                k[len(prefix):]: v
                for k, v in raw.items()
                if k.startswith(prefix)
                and k not in (f"{prefix}ENABLED", f"{prefix}EVENTS")
            }
            providers[name] = ProviderConfig(enabled=enabled, events=events, extra=extra)

        return cls(host=host, public_ip=public_ip, providers=providers, raw=raw)

    def enabled_providers(self) -> list[str]:
        return [name for name, p in self.providers.items() if p.enabled]


def _discover_provider_names(raw: dict[str, str]) -> set[str]:
    """Pull provider names out of the *_ENABLED keys."""
    names: set[str] = set()
    for key in raw:
        if key.endswith("_ENABLED"):
            names.add(key[: -len("_ENABLED")].lower())
    return names


def _parse_file(path: Path) -> dict[str, str]:
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        raise NotifyConfigError(f"config file not found: {path}") from exc
    except OSError as exc:
        raise NotifyConfigError(f"cannot read {path}: {exc}") from exc

    out: dict[str, str] = {}
    for lineno, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise NotifyConfigError(f"{path}:{lineno} missing '=': {raw_line!r}")
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip()
        try:
            # Rejoin tokens with spaces so values like GMAIL_EVENTS, which
            # legitimately contain whitespace, survive the round-trip
            # whether the writer chose `'a b'` or `a\ b` for quoting.
            parts = shlex.split(val) if val else [""]
            out[key] = " ".join(parts) if parts else ""
        except ValueError as exc:
            raise NotifyConfigError(
                f"{path}:{lineno} cannot parse value for {key}: {exc}"
            ) from exc
    return out


def _assert_safe_perms(path: Path) -> None:
    try:
        st = path.stat()
    except FileNotFoundError as exc:
        raise NotifyConfigError(f"config file not found: {path}") from exc
    if st.st_uid != 0:
        raise NotifyConfigError(
            f"{path} must be owned by root (uid=0), found uid={st.st_uid}"
        )
    if st.st_mode & 0o077:
        raise NotifyConfigError(
            f"{path} must be mode 0600, found {st.st_mode & 0o777:04o}"
        )
