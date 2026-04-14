# CLAUDE.md

Coding standards and contribution guide for AI agents (and humans)
working on **vps-cloud-backup**. This file is the source of truth for
project conventions; anything that contradicts it is a bug to fix.

## Project overview

A one-shot installer plus runtime for automated cloud backups on fresh
Linux VPSes. Users clone the repo, run `sudo ./bootstrap.sh`, answer
prompts, and walk away with a systemd-driven backup job that dumps
databases, tarballs / mirrors filesystem paths, uploads to a cloud
destination via rclone, and emails them on failure.

**This is NOT:**
- A replacement for restic / borg — no dedup, no incremental, no encryption in v1.
- An agent / central-server management tool — each VPS is independent.
- A Windows-compatible tool — Linux/systemd only.
- A Python project with bash glue — it's a **bash project with a small,
  well-defined Python subsystem** for database dumping and notifications.

**Re-running:** `sudo ./bootstrap.sh --reconfigure [SECTION]` re-runs a single
section (provider, sources, schedule, notifiers, ...) against an existing
install without redoing the full 10 phases or taking a new timeshift snapshot.

## Three independent abstractions

Every new feature fits into one of three buckets:

1. **Destinations** — WHERE backups go. `lib/providers/<name>.sh`.
   Mutually exclusive: one per VPS. Currently: Google Drive, S3.
2. **Sources** — WHAT gets backed up. `lib/sources/<name>.sh`.
   Multi-select: filesystem + databases can both be on. Currently: filesystem, database.
3. **Notifiers** — HOW you're alerted. `lib/notifiers/<name>.sh` +
   `vcb_notify/providers/<name>.py`. Multi-select. Currently: Gmail.

Each has a `*_api.sh` file with `list`, `call`, `has` helpers that
dispatch by function name via directory scan. **No central registry to
edit.** Dropping a new file in the right directory registers the plugin.

## Directory map (canonical)

```
bootstrap.sh                         top-level orchestrator (phases 1–10 + sub-phases 2b/5b/5c/7a/7c/7d)
uninstall.sh                         reverses the bootstrap
lib/                                 bash helpers (sourced by bootstrap.sh)
  core.sh              globals, traps, parse_args, render_template
  log.sh               log / warn / err / banner (stderr only)
  errors.sh            bash error code registry + err_code()
  prompt.sh            ask_default / ask_yes_no / ask_secret / ask_choice
  state.sh             /etc/vps-cloud-backup/bootstrap.env I/O
  secure_conf.sh       write_secure_conf (atomic, 0600 root:root)
  detect.sh            env detection: distro, pkgmgr, IP, cloud, ...
  pkg.sh               distro-agnostic install helpers
  system_snapshot.sh   pre-install timeshift snapshot (phase 2b)
  schedule.sh          schedule menu + OnCalendar rendering
  systemd.sh           systemd unit installation
  backup_script.sh     renders /usr/local/bin/vcb-backup.sh
  db_conf_writer.sh    renders /etc/vps-cloud-backup/db.conf
  notifications_writer.sh   renders /etc/vps-cloud-backup/notifications.conf
  python_install.sh    copies vcb_dumper + vcb_notify to /usr/local/lib
  provider_api.sh      destination dispatch
  sources.sh           source dispatch
  notifier_api.sh      notifier dispatch
  providers/           destination plugins
  sources/             source plugins
  notifiers/           notifier plugins
  db/                  per-engine auth probing (bash side)
templates/                           template files with @TOKEN@ markers
  backup.sh.tmpl       generated /usr/local/bin/vcb-backup.sh
  backup.service.tmpl  generated systemd .service
vcb_dumper/                          Python package, stdlib-only OOP
  __init__.py, __main__.py, cli.py
  config.py            DumperConfig + EngineConfig (frozen dataclasses)
  credentials.py       CredentialStore (masked __repr__)
  errors.py            exception hierarchy with stable VCB-DUMP-* codes
  result.py            DumpResult + DumperRun + summary.json writer
  orchestrator.py      DumpOrchestrator
  logging_setup.py     bash-compatible log format
  engines/             one file per engine + base ABC
vcb_notify/                          Python package, stdlib-only OOP
  __init__.py, __main__.py, cli.py
  config.py            NotificationConfig + ProviderConfig
  event.py             Event dataclass + KNOWN_EVENTS
  errors.py            exception hierarchy with stable VCB-NOTIFY-* codes
  providers/           one file per channel + base ABC
docs/
  errors.md            every VCB-* error: cause, symptoms, fix
  architecture.md      big picture + data flow
  credentials/         per-destination + per-engine walkthroughs
  notifiers/           per-notifier walkthroughs
CLAUDE.md                            this file
README.md                            user-facing (beginner-friendly)
LICENSE                              MIT
```

**Rule: new code goes into the directory that matches its concern.**
Adding a destination → `lib/providers/`. Adding an engine → `vcb_dumper/engines/`
AND `lib/db/` AND `docs/credentials/`. Never sprinkle responsibility
across unrelated files.

## Tech stack and constraints

- **Bash 4.4+** for the orchestration layer. POSIX `sh` is rejected (we
  use arrays, `[[ ... ]]`, process substitution, `declare -p`).
- **Python 3.9+, stdlib only** for the dumper + notifier. **No pip,
  no venv, no third-party imports.** If you catch yourself wanting
  `pyyaml`, use the shell-env parser we already have. If you want
  `requests`, use `urllib.request`. If you want `psycopg2`, shell out
  to `psql` / `pg_dump` via `subprocess`.
- **rclone** is the upload engine for every destination. Providers
  configure an rclone remote and emit a `REMOTE:DEST` URI. The generated
  backup script never knows what provider it's talking to.
- **systemd** is the scheduler. No cron fallback — every distro we
  support ships systemd. If you want cron support, you want a different tool.
- External commands allowed: `curl`, `tar`, `rclone`, `systemctl`,
  `systemd-analyze`, `mktemp`, `stat`, `chmod`, `chown`, `mv`,
  `mkdir`, `find`, `grep`, `sed`, `awk`, `tr`, `cat`, `printf`, `date`,
  `hostname`, `uname`, plus the distro package manager (`apt-get`, `dnf`, `yum`)
  and database client tools (`mysql`, `mysqldump`, `psql`, `pg_dump`,
  `sqlite3`). Anything outside this list needs justification in the PR.

## Shell coding standards

Every sourced file starts with `set -euo pipefail`. Files that install
ERR traps also use `set -E`.

- **Always quote variables**: `"$var"`, never `$var`. Arrays expanded as `"${arr[@]}"`.
- **Function naming**: `snake_case`, namespace-prefixed per file. Examples:
  `detect_distro`, `pkg_install`, `provider_s3_configure`, `phase_3_select_provider`.
- **`local` declarations** for every function variable. Functions never
  write to globals unless the function name makes that explicit (`state_set`, `detect_*`).
- **Stdout = data, stderr = logging.** Never mix. Functions that return
  a value print ONLY that value to stdout; their log output goes to
  stderr via `log` / `warn` / `err`.
- **`printf` over `echo`**. Never `echo -e`.
- **`return` from functions, `exit` only from `bootstrap.sh`** (and
  `uninstall.sh`). Every other file uses `return 1` on failure so the
  caller's trap fires cleanly.
- **No `eval`.** The only remaining uses are `eval "var=\${$name:-}"` in
  `lib/prompt.sh` (indirect read of a variable named by a caller) and
  `lib/state.sh` (reading state keys during save). Both expand a
  controlled identifier, never a user-supplied string. Any new `eval`
  needs a comment explaining why it's safe.
- **No `curl | bash`** — except for `ensure_rclone` in `lib/pkg.sh`,
  which pulls the official rclone installer. That line is commented and
  is the ONLY exception.
- **Prompts** always go through `ask_default` / `ask_yes_no` /
  `ask_secret` / `ask_choice`. Never call `read` directly.
- **Logging** always goes through `log` / `warn` / `err` / `banner`.
  Never raw `echo` or `printf` for status messages.
- **Error reporting** with `err_code VCB-XXXX-NNN "message"` for known
  failures. The code must exist in `lib/errors.sh` AND `docs/errors.md`.

## Python coding standards

Every module starts with a 3-line docstring: one-line purpose, one-line
"who imports this," one-line "who it calls out to."

- **`from __future__ import annotations`** at the top of every module.
- **Type hints required** on every public method and `@classmethod`.
  Private helpers (leading `_`) may skip them when they'd only add noise.
- **`@dataclass(frozen=True)`** for plain data holders. (Do NOT use
  `slots=True` — it was added in Python 3.10 and we support 3.9+.)
  Mutable state goes in regular classes.
- **One class per responsibility.** If `__init__` stores more than ~6
  attributes, or methods touch non-overlapping attribute subsets, split.
- **`print()` is forbidden** except in the CLI top-level error path
  (`cli.py` can write to `sys.stderr` directly for pre-logger failures).
  All other output goes through `logging`.
- **`pathlib.Path`** over `os.path.join` / `os.path.exists`.
- **`subprocess.run(..., check=False)`** explicit, never `shell=True`
  unless the argv is a literal constant. Never `os.system`.
- **Bare `except:`** is forbidden. Bare `except Exception:` only at the
  CLI top level as a last-resort safety net.
- **`__repr__` must never leak secrets.** `CredentialStore.__repr__`
  returns a masked form with key names and a count of redacted secrets.
- **No logger call may format a credential as an argument.** If you
  need to mention that a password was used, say `"auth method=password"`,
  not `"password=%s"`.
- **Secrets never go on the command line.** `MYSQL_PWD` / `PGPASSWORD`
  env vars only.

## Error code conventions

Every user-visible failure has a stable code of the form `VCB-<SUB>-NNN`
where `<SUB>` is one of:

| Subsystem | Range             | Location                                  |
|-----------|-------------------|-------------------------------------------|
| BOOT      | `VCB-BOOT-NNN`    | `lib/errors.sh` + `docs/errors.md`         |
| DUMP      | `VCB-DUMP-NNN`    | `vcb_dumper/errors.py` + `docs/errors.md`  |
| NOTIFY    | `VCB-NOTIFY-NNN`  | `vcb_notify/errors.py` + `docs/errors.md`  |

**Every new error code requires all three of:**

1. A registry entry (bash: `VCB_ERROR_CODES` map, Python: a subclass of `*Error`).
2. A raising site that actually uses it.
3. An entry in `docs/errors.md` with **cause + symptoms + fix**.

Codes are stable. Never reuse a retired number.

## Adding a new destination provider

1. Create `lib/providers/<name>.sh` implementing the eight required
   functions (`provider_<name>_label`, `_description`, `_deps`,
   `_rclone_backend`, `_prompt_config`, `_configure`, `_verify`,
   `_remote_uri`) plus optionally `_uninstall_hint`, `_credentials_doc`.
2. Create `docs/credentials/<name>.md`.
3. Do not edit any existing provider, the dispatcher, or the backup
   script template. The dispatcher auto-discovers the new file.

## Adding a new database engine

1. Create `vcb_dumper/engines/<name>.py` with a class subclassing
   `Dumper`. Implement `test_connection`, `discover`, `dump`. Raise
   `DumperConnectionError` / `DumperAuthError` / `DumperDiscoveryError`
   / `DumperDumpFailed` — never catch in the subclass.
2. Add one line to `vcb_dumper/engines/__init__.py` registering the class.
3. Create `lib/db/<name>.sh` with `db_<name>_configure` that probes auth
   methods, prompts credentials via `ask_secret`, and calls `state_set`
   for non-secret keys.
4. Add `"<name>"` to `DB_KNOWN_ENGINES` in `lib/sources/database.sh`.
5. Extend `lib/db_conf_writer.sh` with a section for `<NAME>_*` keys.
6. Create `docs/credentials/<name>.md`.
7. Add a unit test under `test/python/unit/engines/test_<name>.py` (when
   the test suite lands).
8. Do NOT edit `Dumper`, `DumpOrchestrator`, `DumperConfig`,
   `CredentialStore`, or any other engine class.

## Adding a new notification channel

1. Create `vcb_notify/providers/<name>.py` with a class subclassing
   `Notifier`. Implement `send` and `test`. Raise `NotifyAuthError`,
   `NotifyConnectionError`, or `NotifySendFailed` on failure.
2. Add one line to `vcb_notify/providers/__init__.py` registering it.
3. Create `lib/notifiers/<name>.sh` with `notifier_<name>_label`,
   `_description`, `_deps`, `_prompt_config`, `_verify`.
4. Extend `lib/notifications_writer.sh` with a case arm for the new name.
5. Create `docs/notifiers/<name>.md` with credential setup instructions.
6. Do not edit existing notifier files, the base class, or the CLI.

## How bash and Python talk

Two config files in `/etc/vps-cloud-backup/` are the entire interface:

- `db.conf` — read by `vcb_dumper`, written by bash
- `notifications.conf` — read by `vcb_notify`, written by bash

Both are `0600 root:root`, plain `KEY=value` shell-env format. The
`secure_conf.sh:write_secure_conf` helper guarantees perms on write;
`DumperConfig._assert_safe_perms` and
`NotificationConfig._assert_safe_perms` enforce them on read.

Bash invokes Python via `PYTHONPATH=/usr/local/lib python3 -m vcb_*`.
Bash reads Python's **exit code**:

- `vcb_dumper`: `0` clean, `1` partial (continue upload), `2` fatal (abort)
- `vcb_notify`: `0` all delivered, `1` partial, `2` all failed

**There is no other channel.** No shared env vars (except
`MYSQL_PWD`/`PGPASSWORD` that Python sets itself). No JSON inputs. No
command-line arguments carrying credentials. If you need a new
bash→Python channel, add a new config-file key first.

## Security rules (non-negotiable)

1. **`db.conf` and `notifications.conf` must always be `0600 root:root`.**
   Both bash and Python assert this on read; bash sets it on write via
   `write_secure_conf`. Any code path that writes to either file without
   going through `write_secure_conf` is a bug.
2. **Secrets never land in `/etc/vps-cloud-backup/bootstrap.env`.**
   `state_set` filters keys matching `*PASSWORD*|*SECRET*|*TOKEN*|*KEY_ID*|*ACCESS_KEY*`
   from the persisted state file.
3. **Secrets never go on the command line** where `ps` can see them.
   Always via `MYSQL_PWD` / `PGPASSWORD` env vars.
4. **`__repr__`** on anything holding secrets returns a masked form.
5. **Log messages** never contain credential values.

## Testing before committing

```bash
# Shell: bash -n on every file, plus shellcheck if installed
bash test/shellcheck.sh

# Python: stdlib compileall on both packages
python3 -m compileall -q vcb_dumper vcb_notify
```

A bats + Dockerized dry-run suite is planned for v1.1. When adding new code,
at minimum:

- Run both commands above; both must be silent.
- If touching prompts / state: do a dry re-run of the bootstrap on a
  VM and verify the state file round-trips correctly.

## What NOT to do

- Do not `pip install` anything. Stdlib only.
- Do not add a TUI library (`dialog`, `whiptail`, `gum`, `fzf`) to
  the prompts. Simple `read` in `lib/prompt.sh` is the whole UI.
- Do not introduce a JSON/YAML/TOML config format. Two config files,
  plain `KEY=value` shell env, period.
- Do not replace the bash orchestrator with Python. Bash talks to
  `systemd`, `apt`, `rclone`, and the user. Python talks to databases
  and SMTP.
- Do not use Python for anything already in `lib/detect.sh`, `lib/pkg.sh`,
  or `lib/state.sh`.
- Do not silently swallow `rclone` errors; they must surface through
  the trap so the user sees them.
- Do not mix POSIX `sh` and bash. Everything is bash. No `#!/bin/sh`.
- Do not add distro-specific logic outside `lib/detect.sh` and `lib/pkg.sh`.
- Do not pass passwords as command-line arguments.
- Do not log at INFO or above with any value from `CredentialStore`.
- Do not add new abstractions without a second plugin to validate them.
  Three destinations OK; one abstraction with one implementation is a
  smell.

## Commit style

Conventional commits, imperative mood, lowercase, ≤72 chars subject:

```
feat: add azure blob destination provider
fix(dumper): handle postgres role without pg_read_all_data
refactor(lib/schedule.sh): extract systemd-analyze validation
docs(errors.md): add VCB-DUMP-045 for pg_dump format mismatch
test(vcb_dumper): stub subprocess for mysql engine discovery
```

Body explains the WHY. Reference issue numbers as `#123`. PRs
squash-merge so the subject becomes the merge commit.

## When unsure

Read `docs/architecture.md` for the big picture. Read
`lib/provider_api.sh` + `lib/providers/gdrive.sh` to understand how the
plugin pattern works before touching `lib/sources/` or `lib/notifiers/`.
Read `vcb_dumper/engines/base.py` and `vcb_dumper/engines/mysql.py`
before touching the dumper.

When in doubt about scope: the rule is **"boring, explicit, and local."**
Code that a tired sysadmin can understand in 60 seconds at 3am beats
code that a senior engineer would call elegant.
