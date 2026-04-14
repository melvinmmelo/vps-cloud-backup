# Error reference

Every failure this project can produce has a stable code of the form
`VCB-<SUBSYSTEM>-NNN`. Codes are never reused once retired. When you see
an error in the logs, look it up here.

Error message format is always:

```
[x] VCB-XXXX-NNN: <short human description>
```

Grep the log file for the code to find context:

```bash
grep VCB- /var/log/vcb-backup.log
journalctl -u vcb-backup.service | grep VCB-
```

---

## Bootstrap errors (VCB-BOOT-*)

Raised by `bootstrap.sh` and the helper libs in `lib/`.

### VCB-BOOT-001 — bootstrap must run as root

**Cause:** you invoked `./bootstrap.sh` without `sudo`.
**Fix:** `sudo ./bootstrap.sh`.

### VCB-BOOT-002 — unsupported distribution

**Cause:** `/etc/os-release` is missing or unreadable.
**Fix:** confirm you're on a supported distro (Ubuntu, Debian, Amazon Linux,
RHEL/Rocky/Alma, Fedora). On very stripped-down systems you may need to
install `base-files` or equivalent.

### VCB-BOOT-003 — no supported package manager (apt/dnf/yum) found

**Cause:** none of `apt-get`, `dnf`, `yum` is on `$PATH`.
**Fix:** install the right distro tooling, or open an issue describing
your environment if you're on something like Alpine (musl-libc).

### VCB-BOOT-004 — public IP detection failed on every backend

**Cause:** cloud metadata service is unreachable AND the bootstrap can't
talk to `ifconfig.me` / `api.ipify.org`.
**Symptoms:** you'll see `unknown` as the Public IP in the summary.
**Fix:** this is a warning, not a fatal error — the bootstrap continues.
The hostname alone will be used in the destination folder slug. If you
care about the public IP tag, fix network egress and re-run.

### VCB-BOOT-005 — required dependency could not be installed

**Cause:** `apt-get install` / `dnf install` returned non-zero.
**Fix:** check for dpkg locks (`ps aux | grep dpkg`), broken repos, or
network issues. Re-run the bootstrap; installs are idempotent.

### VCB-BOOT-010 — rclone config produced no remote

**Cause:** you cancelled out of `rclone config` or the remote was never saved.
**Fix:** re-run bootstrap and make sure to press `y` to save the remote
and `q` to quit `rclone config`.

### VCB-BOOT-011 — rclone remote verification failed

**Cause:** the remote was saved but `rclone lsd remote:` failed — usually
an auth problem (expired token, wrong bucket name, bad S3 keys).
**Fix:** `rclone config reconnect <remote>:` for OAuth providers, or
`sudo ./bootstrap.sh --force-reconfigure` to redo the whole thing.

### VCB-BOOT-020 — state file could not be read or has unsafe permissions

**Cause:** `/etc/vps-cloud-backup/bootstrap.env` exists but is not owned
by root or has group/world access.
**Fix:** `sudo chown root:root /etc/vps-cloud-backup/bootstrap.env &&
sudo chmod 600 /etc/vps-cloud-backup/bootstrap.env`.

### VCB-BOOT-021 — state file could not be written

**Cause:** the parent directory is unwritable or the filesystem is full.
**Fix:** `df -h /etc`; `mount | grep /etc`.

### VCB-BOOT-030 — systemd unit install failed

**Cause:** `systemctl daemon-reload` returned non-zero.
**Fix:** `journalctl -xe` to see what systemd is unhappy about.
Commonly: the unit file has a typo — the bootstrap regenerates it, so
re-running with `--force-reconfigure` usually fixes it.

### VCB-BOOT-031 — systemd timer could not be enabled

**Cause:** `systemctl enable --now vcb-backup.timer` returned non-zero.
**Fix:** inspect with `systemctl status vcb-backup.timer` and
`journalctl -u vcb-backup.timer`.

### VCB-BOOT-040 — template rendering failed

**Cause:** one of `templates/*.tmpl` is missing or `sed` failed on a
value containing a `|` character.
**Fix:** make sure you haven't modified the templates by hand. Re-clone
the repo if unsure.

### VCB-BOOT-050 — db.conf could not be written with correct permissions

**Cause:** `write_secure_conf` could not set 0600 root:root on the file.
**Fix:** check `/etc/vps-cloud-backup/` exists and is writable by root.
This almost always means the filesystem is read-only.

### VCB-BOOT-051 — database client tool missing after install

**Cause:** you selected a database engine but the client package
(`mysql-client`, `postgresql-client`, `sqlite3`) is still not on `$PATH`.
**Fix:** install it manually and re-run; the bootstrap will detect the
tool the second time.

### VCB-BOOT-060 — notifications.conf could not be written with correct permissions

Same root cause as VCB-BOOT-050. Same fix.

### VCB-BOOT-070 — invalid OnCalendar expression

**Cause:** you picked the "Custom" schedule option and the expression
you typed isn't valid systemd calendar syntax.
**Fix:** test it with `systemd-analyze calendar '<your-expression>'`.
Pick one of the non-custom presets if you're not sure.

### VCB-BOOT-999 — unexpected error, see trap output

**Cause:** an uncaught bash error. The trap handler printed the file
and line number immediately before this code.
**Fix:** look at the line mentioned, and file an issue.

---

## Dumper errors (VCB-DUMP-*)

Raised by `vcb_dumper` (Python). Documented in `vcb_dumper/errors.py`
and raised through `DumperError` subclasses.

### VCB-DUMP-001 — db.conf missing, malformed, or unsafe permissions

**Cause:** `/etc/vps-cloud-backup/db.conf` is missing, not 0600 root:root,
or contains a line that isn't parseable.
**Fix:** run `sudo ls -l /etc/vps-cloud-backup/db.conf` — if permissions
are wrong, `chown root:root` and `chmod 600`. If content is wrong,
`sudo ./bootstrap.sh --force-reconfigure` to regenerate it.

### VCB-DUMP-002 — staging directory missing, unwritable, or wrong owner

**Cause:** `/var/backups/vcb-staging/` doesn't exist or root can't write to it.
**Fix:** `sudo mkdir -p /var/backups/vcb-staging && sudo chmod 700 /var/backups/vcb-staging`.

### VCB-DUMP-010 — engine client tool could not reach the database server

**Cause:** `mysql` / `psql` / `sqlite3` returned a non-auth error — most
often the server isn't running, or is listening on a different socket.
**Fix:** confirm the service is up: `systemctl status mysql`,
`systemctl status postgresql`. Check socket paths for custom installs.

### VCB-DUMP-011 — authentication rejected by the database server

**Cause:** the stored credentials are wrong.
**Fix:** `sudo ./bootstrap.sh --force-reconfigure` to redo the credential
prompts. The bootstrap will re-probe auth methods before asking.

### VCB-DUMP-020 — failed to enumerate databases from the server

**Cause:** the connection worked (auth OK) but `SHOW DATABASES` / `SELECT
datname FROM pg_database` failed. Usually a permission issue on the user
the dumper is connecting as.
**Fix:** make sure the user (`root` for MySQL, `postgres` for Postgres)
has global read permissions. Consider using a dedicated backup user
instead — edit `/etc/vps-cloud-backup/db.conf` and set the `*_USER` key.

### VCB-DUMP-030 — the underlying dump tool exited non-zero or produced empty output

**Cause:** `mysqldump` / `pg_dump` / `sqlite3 .backup` itself failed.
**Fix:** run the exact command by hand (copy it from
`journalctl -u vcb-backup.service`) and observe the real error. Most
common: disk full, table locks, or the `postgres` user losing access to
a specific database.

### VCB-DUMP-031 — dump ran longer than the configured timeout and was killed

**Cause:** a dump took longer than 4 hours (the default `_stream_to_gzip`
timeout).
**Fix:** split the database, use a faster disk for the staging dir, or
adjust the timeout in `vcb_dumper/engines/base.py`. Open an issue if you
need this to be user-configurable.

### VCB-DUMP-040 — configured engine is not registered

**Cause:** `db.conf` enables an engine that isn't in
`vcb_dumper/engines/__init__.py`.
**Fix:** you've either edited the config by hand or you're running with a
mismatched version of the Python package and the bootstrap.
`sudo ./bootstrap.sh --force-reconfigure` fixes both.

---

## Notifier errors (VCB-NOTIFY-*)

Raised by `vcb_notify`.

### VCB-NOTIFY-001 — notifications.conf missing, malformed, or unsafe perms

Same class of problem as VCB-DUMP-001. Same fix.

### VCB-NOTIFY-002 — configured provider not in the registry

**Cause:** `notifications.conf` has `XYZ_ENABLED=1` for a provider that
isn't in `vcb_notify/providers/__init__.py`.
**Fix:** re-run the bootstrap, which will overwrite notifications.conf.

### VCB-NOTIFY-010 — cannot reach SMTP/HTTP endpoint

**Cause:** outbound port 587 (Gmail SMTP) is blocked, or Gmail is down.
**Fix:** `nc -vz smtp.gmail.com 587` to test connectivity. Some cloud
providers block outbound 587 — open it in your firewall, or switch to a
different notifier.

### VCB-NOTIFY-011 — authentication rejected

**Cause for Gmail:** the App Password is wrong, was revoked, or you
used your regular Gmail password instead of an App Password.
**Fix:** generate a new App Password at
<https://myaccount.google.com/apppasswords> and re-run
`sudo ./bootstrap.sh --force-reconfigure`.

### VCB-NOTIFY-020 — provider accepted credentials but failed to send

**Cause:** the recipient rejected the mail, or Gmail throttled you.
**Fix:** check the Gmail "Sent" folder for bounces; try a different
`GMAIL_TO` address.

### VCB-NOTIFY-030 — unknown event name

**Cause:** something called `python3 -m vcb_notify send --event X`
with an X not in `KNOWN_EVENTS`.
**Fix:** only a developer error. File an issue.

---

## How to add a new error code

1. Pick the next free number in the right subsystem range.
2. Add it to the corresponding file:
   - Bash: `lib/errors.sh` (`VCB_ERROR_CODES` map)
   - Python dumper: `vcb_dumper/errors.py`
   - Python notifier: `vcb_notify/errors.py`
3. Add an entry to this file under the matching subsystem header.
4. Never reuse a retired code.
