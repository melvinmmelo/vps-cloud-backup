"""GmailNotifier — sends plain-text email through smtp.gmail.com:587 with STARTTLS.

Imported by: providers/__init__.py, tests.
Calls out to: smtplib, ssl, email.message (all stdlib).

Requires a Google **App Password** — not the regular account password.
See docs/notifiers/gmail.md for the setup.

Expected config keys in notifications.conf:
    GMAIL_ENABLED=1
    GMAIL_EVENTS="backup.failure backup.partial setup.completed"
    GMAIL_USER="you@gmail.com"
    GMAIL_APP_PASSWORD="<16-char app password>"
    GMAIL_TO="alerts@example.com"      (defaults to GMAIL_USER)
    GMAIL_FROM_NAME="vps-cloud-backup" (optional display name)
"""
from __future__ import annotations

import smtplib
import ssl
from email.message import EmailMessage

from ..errors import NotifyAuthError, NotifyConnectionError, NotifySendFailed
from ..event import Event
from .base import Notifier

_SMTP_HOST = "smtp.gmail.com"
_SMTP_PORT = 587
_SMTP_TIMEOUT = 30  # seconds


class GmailNotifier(Notifier):
    provider_name = "gmail"
    label = "Gmail"

    # ------------------------------------------------------------------
    def send(self, event: Event) -> None:
        user = self._cfg.extra.get("USER", "")
        password = self._cfg.extra.get("APP_PASSWORD", "")
        to_addr = self._cfg.extra.get("TO") or user
        from_name = self._cfg.extra.get("FROM_NAME", "vps-cloud-backup")

        if not user or not password:
            raise NotifyAuthError(
                "Gmail requires GMAIL_USER and GMAIL_APP_PASSWORD in notifications.conf",
                context={"user_present": bool(user), "password_present": bool(password)},
            )

        msg = EmailMessage()
        msg["Subject"] = event.headline()
        msg["From"] = f"{from_name} <{user}>"
        msg["To"] = to_addr
        msg.set_content(event.formatted_body())

        self._logger.info("sending %s to %s", event.name, to_addr)
        self._deliver(msg, user, password)

    # ------------------------------------------------------------------
    def test(self) -> None:
        probe = Event(
            name="test",
            severity="info",
            host=self._cfg.extra.get("HOST", "unknown"),
            public_ip=self._cfg.extra.get("PUBLIC_IP", "unknown"),
            subject="test notification",
            body="If you are reading this, vps-cloud-backup Gmail notifications work.",
        )
        self.send(probe)

    # ------------------------------------------------------------------
    def _deliver(self, msg: EmailMessage, user: str, password: str) -> None:
        context = ssl.create_default_context()
        try:
            with smtplib.SMTP(_SMTP_HOST, _SMTP_PORT, timeout=_SMTP_TIMEOUT) as smtp:
                smtp.ehlo()
                smtp.starttls(context=context)
                smtp.ehlo()
                try:
                    smtp.login(user, password)
                except smtplib.SMTPAuthenticationError as exc:
                    raise NotifyAuthError(
                        f"Gmail authentication rejected: {exc.smtp_code} {exc.smtp_error!r}",
                        context={"smtp_code": exc.smtp_code},
                    ) from exc
                try:
                    smtp.send_message(msg)
                except smtplib.SMTPException as exc:
                    raise NotifySendFailed(
                        f"Gmail send_message failed: {exc}",
                        context={"to": msg["To"]},
                    ) from exc
        except (OSError, smtplib.SMTPConnectError) as exc:
            raise NotifyConnectionError(
                f"cannot reach {_SMTP_HOST}:{_SMTP_PORT}: {exc}",
                context={"host": _SMTP_HOST, "port": _SMTP_PORT},
            ) from exc
