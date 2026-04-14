# Architecture

A single diagram + a few paragraphs for contributors and future-you.

## 10,000-foot view

```
   ┌──────────────────────────┐
   │        bootstrap.sh       │   thin orchestrator (~250 lines)
   │  ────────────────────────│   sources lib/*.sh + lib/providers/*.sh
   │  parse_args → phases 1-10 │   + lib/sources/*.sh + lib/notifiers/*.sh
   └───────┬───────────────────┘
           │
           ▼
  ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
  │   destinations   │   │     sources      │   │   notifiers      │
  │  (providers/*.sh)│   │  (sources/*.sh)  │   │ (notifiers/*.sh) │
  ├──────────────────┤   ├──────────────────┤   ├──────────────────┤
  │ gdrive.sh        │   │ filesystem.sh    │   │ gmail.sh         │
  │ s3.sh            │   │ database.sh ─┐   │   │ telegram.sh (TBD)│
  │ (future: azure…) │   │  (future…)   │   │   │ (future: slack…) │
  └──────────────────┘   └──────────────┼───┘   └──────────────────┘
                                        │
                                        ▼
                              ┌──────────────────────┐
                              │   Python subsystems   │
                              ├──────────────────────┤
                              │ vcb_dumper  (OOP)    │
                              │  Dumper (ABC)        │
                              │    ↳ MySQLDumper     │
                              │    ↳ PostgresDumper  │
                              │    ↳ SQLiteDumper    │
                              │  DumpOrchestrator    │
                              │  DumperConfig        │
                              │  CredentialStore     │
                              │  DumpResult+DumperRun│
                              ├──────────────────────┤
                              │ vcb_notify  (OOP)    │
                              │  Notifier (ABC)      │
                              │    ↳ GmailNotifier   │
                              │  Event, Config       │
                              └──────────────────────┘
                                        │
                                        ▼
                              ┌──────────────────────┐
                              │  systemd: vcb-backup │
                              │   .service + .timer  │
                              └───────────┬──────────┘
                                          │
                                          ▼
                            /usr/local/bin/vcb-backup.sh
                            (generated from backup.sh.tmpl)
                              1. dump DBs to staging
                              2. rclone copy → remote
                              3. prune by retention
                              4. notify on result
```

## Three independent abstractions

All three follow the same discovery pattern but for different axes:

1. **Destinations** (`lib/providers/`) — WHERE the backup goes. Mutually
   exclusive; pick one per VPS. The provider owns the rclone remote
   config and the `REMOTE:DEST` URI string.
2. **Sources** (`lib/sources/`) — WHAT gets backed up. Multi-select; each
   source contributes paths into the SOURCES array that `backup.sh` reads.
   `filesystem` is pass-through; `database` invokes the Python dumper.
3. **Notifiers** (`lib/notifiers/`) — HOW you're told about results.
   Multi-select (v1 ships Gmail only). Each notifier owns its config
   section in `notifications.conf` and a corresponding class in
   `vcb_notify/providers/`.

Each of the three has:
- A `*_api.sh` file with `list`, `call`, `has` helpers
- One `.sh` file per concrete implementation
- A directory-scan registration — no central array to edit

Adding a new destination, source, or notifier is always "drop a new file,
don't touch existing ones."

## Bash ↔ Python boundary

The two sides of this project have strict, minimal contracts:

- Bash writes **two config files** in `/etc/vps-cloud-backup/`:
  - `db.conf`    → read by `vcb_dumper`
  - `notifications.conf` → read by `vcb_notify`
  Both mode `0600 root:root`. Both plain `KEY=value` shell-env format.
- Bash invokes Python as a subprocess:
  - `PYTHONPATH=/usr/local/lib python3 -m vcb_dumper run --config … --staging … --stamp …`
  - `PYTHONPATH=/usr/local/lib python3 -m vcb_notify send --event … --subject … --body …`
- Bash reads Python's **exit code**:
  - `vcb_dumper`: `0` = all clean, `1` = partial (continue upload), `2` = fatal abort
  - `vcb_notify`: `0` = delivered to all channels, `1` = partial, `2` = all failed
- Python never reads bash state directly. No shared env vars (except
  the `PGPASSWORD`/`MYSQL_PWD` that Python sets itself for its own
  subprocesses). No shared files beyond the two config files and the
  `summary.json` that the dumper writes to the staging directory.

This is deliberately the smallest possible surface. If you find yourself
wanting to add a new bash→Python channel, add a new config-file key first.

## Data flow for one scheduled backup

1. `systemd` timer fires. `vcb-backup.service` invokes
   `/usr/local/bin/vcb-backup.sh`.
2. The script checks `INCLUDE_DATABASES`. If yes, runs
   `python3 -m vcb_dumper run`, which:
   - Loads `db.conf` via `DumperConfig.load()` (stat-checks perms).
   - Loads credentials via `CredentialStore.from_file()`.
   - Instantiates enabled engines (`MySQLDumper`, ...) from `ENGINES` dict.
   - Runs `test_connection → discover → dump` per database in sequence.
   - Writes `.sql.gz` files into `/var/backups/vcb-staging/<engine>/`.
   - Writes `summary.json` with per-DB results.
   - Exits 0, 1, or 2.
3. The bash script interprets the exit code; on 2, it notifies and aborts.
4. On 0 or 1, it calls `rclone copy` for each source path (filesystem
   paths + the staging dir) to the destination URI provided by the
   active destination provider.
5. Then `rclone delete --min-age Nd` prunes old files on the remote.
6. Staging is wiped.
7. A notification is sent via
   `python3 -m vcb_notify send --event backup.success` (or `.partial`,
   or `.failure`) if notifications are enabled.

## File layout cheat sheet

```
bootstrap.sh                       top-level orchestrator (phases 1-10)
uninstall.sh                       reverses the bootstrap
lib/
  core.sh              traps, globals, parse_args, render_template
  log.sh               log/warn/err/banner (stderr only)
  errors.sh            bash error code registry + err_code()
  prompt.sh            ask_default/ask_yes_no/ask_secret/ask_choice
  state.sh             /etc/vps-cloud-backup/bootstrap.env load/save
  secure_conf.sh       write_secure_conf (atomic, 0600 root:root)
  detect.sh            detect_distro/pkgmgr/arch/hostname/cloud/public_ip
  pkg.sh               pkg_install / ensure_cmd / ensure_rclone
  schedule.sh          schedule_prompt + OnCalendar rendering
  systemd.sh           install_systemd_units
  backup_script.sh     render /usr/local/bin/vcb-backup.sh
  db_conf_writer.sh    render /etc/vps-cloud-backup/db.conf
  notifications_writer.sh   render /etc/vps-cloud-backup/notifications.conf
  python_install.sh    copy vcb_dumper + vcb_notify to /usr/local/lib
  provider_api.sh      destination discovery + dispatch
  sources.sh           source discovery + dispatch
  notifier_api.sh      notifier discovery + dispatch
  providers/gdrive.sh  Google Drive destination (via rclone drive)
  providers/s3.sh      S3-compatible destination (via rclone s3)
  sources/filesystem.sh   filesystem paths source
  sources/database.sh     database source (calls lib/db/*.sh)
  db/mysql.sh          MySQL auth probing & discovery
  db/postgres.sh       PostgreSQL auth probing & discovery
  db/sqlite.sh         SQLite file scanning
  notifiers/gmail.sh   Gmail notifier bash side
templates/
  backup.sh.tmpl       generated /usr/local/bin/vcb-backup.sh
  backup.service.tmpl  generated systemd service
  backup.timer.tmpl    (unused — schedule.sh writes timers directly)
vcb_dumper/            Python OOP dumper package
vcb_notify/            Python OOP notifier package
docs/                  this directory
  errors.md            every VCB-* error code
  architecture.md      (this file)
  credentials/         per-provider/per-engine credential walkthroughs
  notifiers/           per-notifier credential walkthroughs
```
